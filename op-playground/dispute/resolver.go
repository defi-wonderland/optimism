package dispute

import (
	"context"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

// resolverABIJSON has only the methods this package writes to or reads from
// during the resolve flow. Kept narrow on purpose — the Reader uses a separate
// ABI for its read-only surface.
const resolverABIJSON = `[
  {"type":"function","name":"resolveClaim","inputs":[{"name":"_claimIndex","type":"uint256"},{"name":"_numToResolve","type":"uint256"}],"outputs":[]},
  {"type":"function","name":"resolve","inputs":[],"outputs":[{"type":"uint8"}]},
  {"type":"function","name":"status","inputs":[],"outputs":[{"type":"uint8"}],"stateMutability":"view"},
  {"type":"function","name":"createdAt","inputs":[],"outputs":[{"type":"uint64"}],"stateMutability":"view"},
  {"type":"function","name":"maxClockDuration","inputs":[],"outputs":[{"type":"uint64"}],"stateMutability":"view"}
]`

var resolverABI abi.ABI

func init() {
	a, err := abi.JSON(strings.NewReader(resolverABIJSON))
	if err != nil {
		panic(fmt.Sprintf("dispute resolver ABI: %v", err))
	}
	resolverABI = a
}

// ResolveResult is what the API hands back after a fast-forward + resolve.
type ResolveResult struct {
	GameAddress     common.Address `json:"game_address"`
	PreStatus       uint8          `json:"pre_status"`
	PreStatusName   string         `json:"pre_status_name"`
	PostStatus      uint8          `json:"post_status"`
	PostStatusName  string         `json:"post_status_name"`
	AdvancedSeconds int64          `json:"advanced_seconds"`
	ResolveClaimTx  string         `json:"resolve_claim_tx,omitempty"`
	ResolveTx       string         `json:"resolve_tx,omitempty"`
	Note            string         `json:"note,omitempty"`
}

// FastForwardSeconds tells the caller how much wall time should be advanced
// to push the game past its deadline. Callers (the server handler) advance
// time with sys.AdvanceTime then call ResolveGame.
func FastForwardSeconds(ctx context.Context, l1RPC string, gameAddr common.Address) (int64, error) {
	cli, err := ethclient.DialContext(ctx, l1RPC)
	if err != nil {
		return 0, err
	}
	defer cli.Close()
	bc := bind.NewBoundContract(gameAddr, resolverABI, cli, cli, cli)
	opts := &bind.CallOpts{Context: ctx}

	var createdOut, maxOut []interface{}
	if err := bc.Call(opts, &createdOut, "createdAt"); err != nil {
		return 0, fmt.Errorf("createdAt: %w", err)
	}
	if err := bc.Call(opts, &maxOut, "maxClockDuration"); err != nil {
		return 0, fmt.Errorf("maxClockDuration: %w", err)
	}
	created, _ := createdOut[0].(uint64)
	maxClock, _ := maxOut[0].(uint64)
	deadline := int64(created + maxClock)
	now := time.Now().Unix()
	if now >= deadline {
		return 0, nil
	}
	// Add a small buffer past the deadline so resolveClaim doesn't race.
	return deadline - now + 5, nil
}

// ResolveGame sends resolveClaim(0,0) then resolve() against the given proxy
// from the supplied private key. Caller is responsible for advancing L1 time
// past the deadline first if the game uses one.
func ResolveGame(ctx context.Context, l1RPC string, gameAddr common.Address, privKeyHex string) (*ResolveResult, error) {
	cli, err := ethclient.DialContext(ctx, l1RPC)
	if err != nil {
		return nil, err
	}
	defer cli.Close()

	chainID, err := cli.ChainID(ctx)
	if err != nil {
		return nil, err
	}

	pkHex := strings.TrimPrefix(privKeyHex, "0x")
	pk, err := crypto.HexToECDSA(pkHex)
	if err != nil {
		return nil, fmt.Errorf("parse privkey: %w", err)
	}
	auth, err := bind.NewKeyedTransactorWithChainID(pk, chainID)
	if err != nil {
		return nil, err
	}
	auth.Context = ctx

	bc := bind.NewBoundContract(gameAddr, resolverABI, cli, cli, cli)

	// Read pre-status. If the game is already resolved, return early.
	var preOut []interface{}
	if err := bc.Call(&bind.CallOpts{Context: ctx}, &preOut, "status"); err != nil {
		return nil, fmt.Errorf("read status: %w", err)
	}
	pre, _ := preOut[0].(uint8)
	res := &ResolveResult{
		GameAddress:   gameAddr,
		PreStatus:     pre,
		PreStatusName: gameStatusName(pre),
	}
	if pre != 0 {
		res.PostStatus = pre
		res.PostStatusName = gameStatusName(pre)
		res.Note = "Game already resolved — nothing to do."
		return res, nil
	}

	// resolveClaim(0, 0): resolve the root claim, no count limit. May revert
	// if claims aren't ready yet (clock not fully drained, sub-claims still
	// pending). We surface the revert text so the caller knows.
	tx, err := bc.Transact(auth, "resolveClaim", big.NewInt(0), big.NewInt(0))
	if err != nil {
		return res, fmt.Errorf("resolveClaim send: %w", err)
	}
	res.ResolveClaimTx = tx.Hash().Hex()
	rcpt, err := bind.WaitMined(ctx, cli, tx)
	if err != nil {
		return res, fmt.Errorf("resolveClaim wait: %w", err)
	}
	if rcpt.Status != 1 {
		return res, fmt.Errorf("resolveClaim reverted (tx %s) — clock probably hasn't fully drained", tx.Hash().Hex())
	}

	// resolve(): now flip the overall game status.
	auth2 := *auth
	auth2.GasLimit = 0
	tx2, err := bc.Transact(&auth2, "resolve")
	if err != nil {
		return res, fmt.Errorf("resolve send: %w", err)
	}
	res.ResolveTx = tx2.Hash().Hex()
	rcpt2, err := bind.WaitMined(ctx, cli, tx2)
	if err != nil {
		return res, fmt.Errorf("resolve wait: %w", err)
	}
	if rcpt2.Status != 1 {
		return res, fmt.Errorf("resolve reverted (tx %s)", tx2.Hash().Hex())
	}

	// Read post-status.
	var postOut []interface{}
	if err := bc.Call(&bind.CallOpts{Context: ctx}, &postOut, "status"); err != nil {
		return res, fmt.Errorf("read post-status: %w", err)
	}
	post, _ := postOut[0].(uint8)
	res.PostStatus = post
	res.PostStatusName = gameStatusName(post)
	return res, nil
}
