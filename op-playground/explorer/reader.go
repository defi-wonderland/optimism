// Package explorer provides minimal Etherscan-style read APIs for the
// playground UI: recent blocks, block detail, and tx detail with decoded
// calldata and logs against a small registry of known contracts.
package explorer

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/rpc"
)

type BlockSummary struct {
	Number    uint64 `json:"number"`
	Hash      string `json:"hash"`
	Timestamp uint64 `json:"timestamp"`
	GasUsed   uint64 `json:"gas_used"`
	GasLimit  uint64 `json:"gas_limit"`
	Miner     string `json:"miner"`
	TxCount   int    `json:"tx_count"`
}

type BlockDetail struct {
	Summary
	BlockSummary
	ParentHash   string   `json:"parent_hash"`
	StateRoot    string   `json:"state_root"`
	BaseFee      string   `json:"base_fee_wei,omitempty"`
	Transactions []string `json:"transactions"`
}

type Summary struct{}

type AddressDetail struct {
	Address     string         `json:"address"`
	Name        string         `json:"name,omitempty"`
	IsContract  bool           `json:"is_contract"`
	BalanceWei  string         `json:"balance_wei"`
	BalanceETH  string         `json:"balance_eth"`
	Nonce       uint64         `json:"nonce"`
	CodeSize    int            `json:"code_size"`
	ABIFunctions []string      `json:"abi_functions,omitempty"`
	ABIEvents    []string      `json:"abi_events,omitempty"`
	RecentTxs    []TxRef       `json:"recent_txs"`
	ScannedFrom  uint64        `json:"scanned_from_block"`
	ScannedTo    uint64        `json:"scanned_to_block"`
}

type TxRef struct {
	Hash        string `json:"hash"`
	BlockNumber uint64 `json:"block_number"`
	BlockTime   uint64 `json:"block_time"`
	Direction   string `json:"direction"` // "out" if from == addr, "in" if to == addr
	From        string `json:"from"`
	To          string `json:"to,omitempty"`
	ValueWei    string `json:"value_wei"`
}

type TxDetail struct {
	Hash             string         `json:"hash"`
	BlockNumber      uint64         `json:"block_number"`
	BlockHash        string         `json:"block_hash"`
	Index            uint64         `json:"index"`
	From             string         `json:"from"`
	To               string         `json:"to,omitempty"`
	ContractAddress  string         `json:"contract_address,omitempty"`
	Value            string         `json:"value_wei"`
	Nonce            uint64         `json:"nonce"`
	GasLimit         uint64         `json:"gas_limit"`
	GasUsed          uint64         `json:"gas_used"`
	GasPrice         string         `json:"gas_price_wei,omitempty"`
	Status           uint64         `json:"status"`
	Type             uint8          `json:"type"`
	InputHex         string         `json:"input_hex"`
	DecodedCall      *DecodedCall   `json:"decoded_call,omitempty"`
	Logs             []DecodedLog   `json:"logs"`
}

type DecodedCall struct {
	Contract  string         `json:"contract"`
	Method    string         `json:"method"`
	Selector  string         `json:"selector"`
	Arguments []DecodedArg   `json:"arguments,omitempty"`
}

type DecodedArg struct {
	Name  string `json:"name"`
	Type  string `json:"type"`
	Value string `json:"value"`
}

type DecodedLog struct {
	Address  string       `json:"address"`
	Contract string       `json:"contract,omitempty"`
	Event    string       `json:"event,omitempty"`
	Topic0   string       `json:"topic0"`
	Args     []DecodedArg `json:"args,omitempty"`
	DataHex  string       `json:"data_hex"`
}

// Reader reads from a single chain's RPC endpoint.
type Reader struct {
	rpc      string
	registry *Registry
}

func New(rpcURL string, registry *Registry) *Reader {
	return &Reader{rpc: rpcURL, registry: registry}
}

// CallTrace is a single frame in a debug_traceTransaction(callTracer) tree.
type CallTrace struct {
	Type      string       `json:"type"`            // CALL, STATICCALL, DELEGATECALL, CREATE, CREATE2
	From      string       `json:"from"`
	To        string       `json:"to,omitempty"`
	Gas       string       `json:"gas,omitempty"`
	GasUsed   string       `json:"gas_used,omitempty"`
	Value     string       `json:"value,omitempty"`
	Input     string       `json:"input,omitempty"`
	Output    string       `json:"output,omitempty"`
	Error     string       `json:"error,omitempty"`
	Revert    string       `json:"revert_reason,omitempty"`
	Decoded   *DecodedCall `json:"decoded,omitempty"`
	Contract  string       `json:"contract,omitempty"` // friendly name from registry
	Selector  string       `json:"selector,omitempty"`
	Children  []CallTrace  `json:"children,omitempty"`
}

// rawCallTracer mirrors the JSON shape returned by callTracer.
type rawCallTracer struct {
	Type         string          `json:"type"`
	From         string          `json:"from"`
	To           string          `json:"to,omitempty"`
	Gas          string          `json:"gas,omitempty"`
	GasUsed      string          `json:"gasUsed,omitempty"`
	Value        string          `json:"value,omitempty"`
	Input        string          `json:"input,omitempty"`
	Output       string          `json:"output,omitempty"`
	Error        string          `json:"error,omitempty"`
	RevertReason string          `json:"revertReason,omitempty"`
	Calls        []rawCallTracer `json:"calls,omitempty"`
}

func (r *Reader) RecentBlocks(ctx context.Context, limit int) ([]BlockSummary, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	cli, err := ethclient.DialContext(ctx, r.rpc)
	if err != nil {
		return nil, err
	}
	defer cli.Close()

	head, err := cli.BlockNumber(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]BlockSummary, 0, limit)
	for i := 0; i < limit; i++ {
		if uint64(i) > head {
			break
		}
		n := head - uint64(i)
		b, err := cli.BlockByNumber(ctx, new(big.Int).SetUint64(n))
		if err != nil {
			continue
		}
		out = append(out, summarize(b))
	}
	return out, nil
}

func (r *Reader) Block(ctx context.Context, ref string) (*BlockDetail, error) {
	cli, err := ethclient.DialContext(ctx, r.rpc)
	if err != nil {
		return nil, err
	}
	defer cli.Close()

	var b *types.Block
	if strings.HasPrefix(ref, "0x") && len(ref) == 66 {
		b, err = cli.BlockByHash(ctx, common.HexToHash(ref))
	} else {
		var n *big.Int
		if ref == "latest" {
			b, err = cli.BlockByNumber(ctx, nil)
		} else {
			n, ok := new(big.Int).SetString(ref, 10)
			if !ok {
				return nil, fmt.Errorf("bad block ref: %q", ref)
			}
			b, err = cli.BlockByNumber(ctx, n)
		}
		_ = n
	}
	if err != nil {
		return nil, err
	}
	d := &BlockDetail{BlockSummary: summarize(b), ParentHash: b.ParentHash().Hex(), StateRoot: b.Root().Hex()}
	if b.BaseFee() != nil {
		d.BaseFee = b.BaseFee().String()
	}
	d.Transactions = make([]string, 0, len(b.Transactions()))
	for _, tx := range b.Transactions() {
		d.Transactions = append(d.Transactions, tx.Hash().Hex())
	}
	return d, nil
}

func (r *Reader) Tx(ctx context.Context, hash string) (*TxDetail, error) {
	cli, err := ethclient.DialContext(ctx, r.rpc)
	if err != nil {
		return nil, err
	}
	defer cli.Close()

	h := common.HexToHash(hash)
	tx, _, err := cli.TransactionByHash(ctx, h)
	if err != nil {
		return nil, err
	}
	receipt, err := cli.TransactionReceipt(ctx, h)
	if err != nil {
		return nil, err
	}

	chainID, _ := cli.ChainID(ctx)
	signer := types.LatestSignerForChainID(chainID)
	from, _ := types.Sender(signer, tx)

	d := &TxDetail{
		Hash:        h.Hex(),
		BlockNumber: receipt.BlockNumber.Uint64(),
		BlockHash:   receipt.BlockHash.Hex(),
		Index:       uint64(receipt.TransactionIndex),
		From:        from.Hex(),
		Value:       tx.Value().String(),
		Nonce:       tx.Nonce(),
		GasLimit:    tx.Gas(),
		GasUsed:     receipt.GasUsed,
		Status:      receipt.Status,
		Type:        tx.Type(),
		InputHex:    "0x" + hex.EncodeToString(tx.Data()),
	}
	if tx.GasPrice() != nil {
		d.GasPrice = tx.GasPrice().String()
	}
	if tx.To() != nil {
		d.To = tx.To().Hex()
	}
	if receipt.ContractAddress != (common.Address{}) {
		d.ContractAddress = receipt.ContractAddress.Hex()
	}

	// Decode calldata if we know the recipient.
	if tx.To() != nil && len(tx.Data()) >= 4 {
		if dc := r.registry.DecodeCall(*tx.To(), tx.Data()); dc != nil {
			d.DecodedCall = dc
		}
	}

	d.Logs = make([]DecodedLog, 0, len(receipt.Logs))
	for _, l := range receipt.Logs {
		d.Logs = append(d.Logs, r.registry.DecodeLog(l))
	}
	return d, nil
}

// Address returns balance, code-presence, ABI methods (if known), and a
// best-effort recent-tx history scanned from the last `scanBlocks` blocks.
func (r *Reader) Address(ctx context.Context, addr string, scanBlocks uint64) (*AddressDetail, error) {
	cli, err := ethclient.DialContext(ctx, r.rpc)
	if err != nil {
		return nil, err
	}
	defer cli.Close()

	a := common.HexToAddress(addr)
	out := &AddressDetail{Address: a.Hex()}

	if name, ok := r.registry.Name(a); ok {
		out.Name = name
		// Surface known function/event names.
		if e, ok := r.registry.byAddr[a]; ok {
			for _, m := range e.abi.Methods {
				out.ABIFunctions = append(out.ABIFunctions, m.Sig)
			}
			for _, ev := range e.abi.Events {
				out.ABIEvents = append(out.ABIEvents, ev.Sig)
			}
		}
	}

	bal, err := cli.BalanceAt(ctx, a, nil)
	if err == nil && bal != nil {
		out.BalanceWei = bal.String()
		out.BalanceETH = formatETHWei(bal)
	}
	nonce, err := cli.NonceAt(ctx, a, nil)
	if err == nil {
		out.Nonce = nonce
	}
	code, err := cli.CodeAt(ctx, a, nil)
	if err == nil {
		out.CodeSize = len(code)
		out.IsContract = len(code) > 0
	}

	// Scan recent blocks for txs touching this address.
	if scanBlocks == 0 {
		scanBlocks = 50
	}
	head, err := cli.BlockNumber(ctx)
	if err == nil {
		from := uint64(0)
		if head > scanBlocks {
			from = head - scanBlocks
		}
		out.ScannedFrom = from
		out.ScannedTo = head
		chainID, _ := cli.ChainID(ctx)
		signer := types.LatestSignerForChainID(chainID)
		for n := head; n >= from; n-- {
			b, err := cli.BlockByNumber(ctx, new(big.Int).SetUint64(n))
			if err != nil {
				if n == 0 {
					break
				}
				continue
			}
			for _, tx := range b.Transactions() {
				from2, _ := types.Sender(signer, tx)
				to := tx.To()
				match := from2 == a || (to != nil && *to == a)
				if !match {
					continue
				}
				ref := TxRef{
					Hash:        tx.Hash().Hex(),
					BlockNumber: b.NumberU64(),
					BlockTime:   b.Time(),
					From:        from2.Hex(),
					ValueWei:    tx.Value().String(),
				}
				if to != nil {
					ref.To = to.Hex()
				}
				if from2 == a {
					ref.Direction = "out"
				} else {
					ref.Direction = "in"
				}
				out.RecentTxs = append(out.RecentTxs, ref)
				if len(out.RecentTxs) >= 25 {
					break
				}
			}
			if len(out.RecentTxs) >= 25 {
				break
			}
			if n == 0 {
				break
			}
		}
	}
	return out, nil
}

func formatETHWei(wei *big.Int) string {
	if wei == nil || wei.Sign() == 0 {
		return "0"
	}
	num := new(big.Float).SetInt(wei)
	denom := new(big.Float).SetInt(new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil))
	q := new(big.Float).Quo(num, denom)
	return q.Text('f', 6)
}

// Trace fetches a debug_traceTransaction(callTracer) result and enriches
// each frame with decoded calldata where the destination address is in the
// registry. Returns the root frame; call tree is in `Children`.
func (r *Reader) Trace(ctx context.Context, hash string) (*CallTrace, error) {
	cli, err := rpc.DialContext(ctx, r.rpc)
	if err != nil {
		return nil, err
	}
	defer cli.Close()

	cfg := map[string]interface{}{
		"tracer": "callTracer",
		"tracerConfig": map[string]bool{
			"withLog": false,
		},
	}
	var raw json.RawMessage
	if err := cli.CallContext(ctx, &raw, "debug_traceTransaction", hash, cfg); err != nil {
		return nil, fmt.Errorf("debug_traceTransaction: %w", err)
	}
	var root rawCallTracer
	if err := json.Unmarshal(raw, &root); err != nil {
		return nil, fmt.Errorf("decode trace: %w", err)
	}
	enriched := r.enrichTrace(root)
	return &enriched, nil
}

func (r *Reader) enrichTrace(raw rawCallTracer) CallTrace {
	out := CallTrace{
		Type:    raw.Type,
		From:    raw.From,
		To:      raw.To,
		Gas:     raw.Gas,
		GasUsed: raw.GasUsed,
		Value:   raw.Value,
		Input:   raw.Input,
		Output:  raw.Output,
		Error:   raw.Error,
		Revert:  raw.RevertReason,
	}
	// Decode if we know the destination + have calldata.
	if raw.To != "" && len(raw.Input) >= 10 { // "0x" + 4 bytes selector hex
		addr := common.HexToAddress(raw.To)
		data := common.FromHex(raw.Input)
		if dc := r.registry.DecodeCall(addr, data); dc != nil {
			out.Decoded = dc
			out.Contract = dc.Contract
			out.Selector = dc.Selector
		}
		if out.Contract == "" {
			if name, ok := r.registry.Name(addr); ok {
				out.Contract = name
			}
		}
		if out.Selector == "" && len(data) >= 4 {
			out.Selector = "0x" + hex.EncodeToString(data[:4])
		}
	}
	for _, child := range raw.Calls {
		out.Children = append(out.Children, r.enrichTrace(child))
	}
	return out
}

func summarize(b *types.Block) BlockSummary {
	return BlockSummary{
		Number:    b.NumberU64(),
		Hash:      b.Hash().Hex(),
		Timestamp: b.Time(),
		GasUsed:   b.GasUsed(),
		GasLimit:  b.GasLimit(),
		Miner:     b.Coinbase().Hex(),
		TxCount:   len(b.Transactions()),
	}
}

// ─── ABI registry ────────────────────────────────────────────────────────

type Registry struct {
	byAddr map[common.Address]*entry
	byEvt  map[common.Hash]*evtEntry // topic0 → event
}

type entry struct {
	name string
	abi  abi.ABI
}

type evtEntry struct {
	contract string
	abi      abi.ABI
	event    abi.Event
}

func NewRegistry() *Registry {
	return &Registry{
		byAddr: make(map[common.Address]*entry),
		byEvt:  make(map[common.Hash]*evtEntry),
	}
}

func (r *Registry) Register(name string, addr common.Address, abiJSON string) error {
	parsed, err := abi.JSON(strings.NewReader(abiJSON))
	if err != nil {
		return fmt.Errorf("registry %s: %w", name, err)
	}
	r.byAddr[addr] = &entry{name: name, abi: parsed}
	for _, ev := range parsed.Events {
		ev := ev
		r.byEvt[ev.ID] = &evtEntry{contract: name, abi: parsed, event: ev}
	}
	return nil
}

func (r *Registry) Name(addr common.Address) (string, bool) {
	if e, ok := r.byAddr[addr]; ok {
		return e.name, true
	}
	return "", false
}

func (r *Registry) DecodeCall(addr common.Address, data []byte) *DecodedCall {
	e, ok := r.byAddr[addr]
	if !ok {
		return nil
	}
	if len(data) < 4 {
		return nil
	}
	method, err := e.abi.MethodById(data[:4])
	if err != nil {
		return nil
	}
	dc := &DecodedCall{
		Contract: e.name,
		Method:   method.Name,
		Selector: "0x" + hex.EncodeToString(data[:4]),
	}
	if vals, err := method.Inputs.Unpack(data[4:]); err == nil && len(vals) == len(method.Inputs) {
		for i, in := range method.Inputs {
			dc.Arguments = append(dc.Arguments, DecodedArg{
				Name:  in.Name,
				Type:  in.Type.String(),
				Value: stringifyVal(vals[i]),
			})
		}
	}
	return dc
}

func (r *Registry) DecodeLog(l *types.Log) DecodedLog {
	out := DecodedLog{
		Address: l.Address.Hex(),
		DataHex: "0x" + hex.EncodeToString(l.Data),
	}
	if len(l.Topics) > 0 {
		out.Topic0 = l.Topics[0].Hex()
		if e, ok := r.byEvt[l.Topics[0]]; ok {
			out.Contract = e.contract
			out.Event = e.event.Name
			// Decode indexed + data args.
			indexed := []abi.Argument{}
			for _, in := range e.event.Inputs {
				if in.Indexed {
					indexed = append(indexed, in)
				}
			}
			if dataVals, err := e.event.Inputs.NonIndexed().Unpack(l.Data); err == nil {
				di := 0
				ti := 1
				for _, in := range e.event.Inputs {
					if in.Indexed {
						if ti < len(l.Topics) {
							out.Args = append(out.Args, DecodedArg{Name: in.Name, Type: in.Type.String(), Value: l.Topics[ti].Hex()})
							ti++
						}
					} else {
						if di < len(dataVals) {
							out.Args = append(out.Args, DecodedArg{Name: in.Name, Type: in.Type.String(), Value: stringifyVal(dataVals[di])})
							di++
						}
					}
				}
			}
		}
	}
	if name, ok := r.Name(l.Address); ok && out.Contract == "" {
		out.Contract = name
	}
	return out
}

func stringifyVal(v interface{}) string {
	switch x := v.(type) {
	case common.Address:
		return x.Hex()
	case common.Hash:
		return x.Hex()
	case []byte:
		return "0x" + hex.EncodeToString(x)
	case *big.Int:
		return x.String()
	case [32]byte:
		return "0x" + hex.EncodeToString(x[:])
	default:
		return fmt.Sprintf("%v", v)
	}
}

// EventID is exported for tests that want to recompute topic0 from a sig.
func EventID(sig string) common.Hash { return crypto.Keccak256Hash([]byte(sig)) }
