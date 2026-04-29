// Package dispute reads the live state of an L2 chain's dispute system
// (DisputeGameFactory + AnchorStateRegistry) from L1, so the playground UI
// can show how that L2 currently reaches consensus.
package dispute

import (
	"context"
	"fmt"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

// abiJSON exposes only the read-only methods we need across DisputeGameFactory,
// AnchorStateRegistry, and OptimismPortal2. One ABI is enough — bind.BoundContract
// dispatches by selector regardless of which contract the call targets.
const abiJSON = `[
  {"type":"function","name":"version","stateMutability":"view","inputs":[],"outputs":[{"type":"string"}]},
  {"type":"function","name":"owner","stateMutability":"view","inputs":[],"outputs":[{"type":"address"}]},
  {"type":"function","name":"gameCount","stateMutability":"view","inputs":[],"outputs":[{"type":"uint256"}]},
  {"type":"function","name":"gameImpls","stateMutability":"view","inputs":[{"type":"uint32"}],"outputs":[{"type":"address"}]},
  {"type":"function","name":"initBonds","stateMutability":"view","inputs":[{"type":"uint32"}],"outputs":[{"type":"uint256"}]},
  {"type":"function","name":"gameAtIndex","stateMutability":"view","inputs":[{"type":"uint256"}],"outputs":[{"type":"uint32","name":"gameType"},{"type":"uint64","name":"timestamp"},{"type":"address","name":"proxy"}]},
  {"type":"function","name":"respectedGameType","stateMutability":"view","inputs":[],"outputs":[{"type":"uint32"}]},
  {"type":"function","name":"anchorStateRegistry","stateMutability":"view","inputs":[],"outputs":[{"type":"address"}]},
  {"type":"function","name":"disputeGameFactory","stateMutability":"view","inputs":[],"outputs":[{"type":"address"}]},
  {"type":"function","name":"optimismPortal","stateMutability":"view","inputs":[],"outputs":[{"type":"address"}]},
  {"type":"function","name":"status","stateMutability":"view","inputs":[],"outputs":[{"type":"uint8"}]},
  {"type":"function","name":"createdAt","stateMutability":"view","inputs":[],"outputs":[{"type":"uint64"}]},
  {"type":"function","name":"resolvedAt","stateMutability":"view","inputs":[],"outputs":[{"type":"uint64"}]},
  {"type":"function","name":"l2BlockNumber","stateMutability":"view","inputs":[],"outputs":[{"type":"uint256"}]},
  {"type":"function","name":"l2SequenceNumber","stateMutability":"view","inputs":[],"outputs":[{"type":"uint256"}]},
  {"type":"function","name":"rootClaim","stateMutability":"view","inputs":[],"outputs":[{"type":"bytes32"}]},
  {"type":"function","name":"maxClockDuration","stateMutability":"view","inputs":[],"outputs":[{"type":"uint64"}]},
  {"type":"function","name":"clockExtension","stateMutability":"view","inputs":[],"outputs":[{"type":"uint64"}]},
  {"type":"function","name":"splitDepth","stateMutability":"view","inputs":[],"outputs":[{"type":"uint256"}]},
  {"type":"function","name":"maxDepth","stateMutability":"view","inputs":[],"outputs":[{"type":"uint256"}]},
  {"type":"function","name":"maxChallengeDuration","stateMutability":"view","inputs":[],"outputs":[{"type":"uint64"}]},
  {"type":"function","name":"maxProveDuration","stateMutability":"view","inputs":[],"outputs":[{"type":"uint64"}]},
  {"type":"function","name":"claimData","stateMutability":"view","inputs":[{"type":"uint256"}],"outputs":[{"type":"uint32","name":"parentIndex"},{"type":"address","name":"counteredBy"},{"type":"address","name":"claimant"},{"type":"uint128","name":"bond"},{"type":"bytes32","name":"claim"},{"type":"uint128","name":"position"},{"type":"uint128","name":"clock"}]}
]`

var parsedABI abi.ABI

func init() {
	a, err := abi.JSON(strings.NewReader(abiJSON))
	if err != nil {
		panic(fmt.Sprintf("dispute: bad ABI: %v", err))
	}
	parsedABI = a
}

type Snapshot struct {
	Chain string `json:"chain"`

	SystemConfig        common.Address `json:"system_config"`
	OptimismPortal      common.Address `json:"optimism_portal"`
	DisputeGameFactory  common.Address `json:"dispute_game_factory"`
	AnchorStateRegistry common.Address `json:"anchor_state_registry"`

	FactoryVersion string         `json:"factory_version"`
	FactoryOwner   common.Address `json:"factory_owner"`
	GameCount      uint64         `json:"game_count"`

	RespectedGameType     uint32 `json:"respected_game_type"`
	RespectedGameTypeName string `json:"respected_game_type_name"`
	RespectedGameTypeDesc string `json:"respected_game_type_desc"`

	Implementations []GameTypeInfo `json:"implementations"`
	RecentGames     []GameRef      `json:"recent_games"`

	Explainer []string `json:"explainer"`
}

type GameTypeInfo struct {
	GameType    uint32         `json:"game_type"`
	Name        string         `json:"name"`
	Family      string         `json:"family"`
	Description string         `json:"description"`
	Impl        common.Address `json:"impl"`
	InitBondWei string         `json:"init_bond_wei"`
	InitBondETH string         `json:"init_bond_eth"`
	Registered  bool           `json:"registered"`
	IsRespected bool           `json:"is_respected"`

	// Timing & shape, populated when the impl exposes them. Zeroed for game
	// types we don't recognise.
	MaxClockDuration     uint64 `json:"max_clock_duration_seconds,omitempty"`     // FDG/Permissioned
	ClockExtension       uint64 `json:"clock_extension_seconds,omitempty"`        // FDG/Permissioned
	MaxChallengeDuration uint64 `json:"max_challenge_duration_seconds,omitempty"` // ZK
	MaxProveDuration     uint64 `json:"max_prove_duration_seconds,omitempty"`     // ZK
	SplitDepth           uint64 `json:"split_depth,omitempty"`                    // FDG/Permissioned
	MaxDepth             uint64 `json:"max_depth,omitempty"`                      // FDG/Permissioned
}

type GameRef struct {
	Index        uint64         `json:"index"`
	GameType     uint32         `json:"game_type"`
	GameTypeName string         `json:"game_type_name"`
	CreatedAt    uint64         `json:"created_at"`
	Proxy        common.Address `json:"proxy"`

	// Live state, best-effort. Zero/empty if the proxy doesn't expose the field.
	Status              uint8  `json:"status"`                // 0 IN_PROGRESS, 1 CHALLENGER_WINS, 2 DEFENDER_WINS
	StatusName          string `json:"status_name"`
	ResolvedAt          uint64 `json:"resolved_at,omitempty"`
	L2SequenceNumber    uint64 `json:"l2_sequence_number,omitempty"`
	RootClaim           string `json:"root_claim,omitempty"`
	MaxClockDuration    uint64 `json:"max_clock_duration_seconds,omitempty"`
	DeadlineTimestamp   uint64 `json:"deadline_timestamp,omitempty"` // unix seconds; 0 if unknown
}

// gameTypeMeta is the static catalogue of every game type OPCM can register.
type gameTypeMeta struct {
	id     uint32
	name   string
	family string
	desc   string
}

var gameTypes = []gameTypeMeta{
	{0, "CANNON", "fault-proof", "Permissionless FaultDisputeGame backed by the MIPS-based Cannon VM. Anyone can propose or challenge; resolution requires bisection to a single instruction."},
	{1, "PERMISSIONED_CANNON", "fault-proof (permissioned)", "Same Cannon VM, but only a whitelisted proposer can create games and only a whitelisted challenger can dispute. Used during early rollouts."},
	{2, "ASTERISC", "fault-proof", "RISC-V execution under the Asterisc VM. Permissionless."},
	{3, "ASTERISC_KONA", "fault-proof", "Asterisc VM running the Kona Rust fault-proof program."},
	{4, "SUPER_CANNON", "fault-proof (interop)", "Cannon VM proving an interop super-root spanning multiple chains."},
	{5, "SUPER_PERMISSIONED_CANNON", "fault-proof (interop, permissioned)", "Permissioned variant of SUPER_CANNON for interop bring-up."},
	{6, "OP_SUCCINCT", "validity-proof", "OP Succinct ZK proofs (legacy/preview integration)."},
	{8, "CANNON_KONA", "fault-proof", "MIPS Cannon VM running the Kona program."},
	{9, "SUPER_CANNON_KONA", "fault-proof (interop)", "Super variant of Cannon-on-Kona."},
	{10, "ZK_DISPUTE_GAME", "validity-proof", "ZKDisputeGame: a proposer posts a claim, a verifier contract (e.g. SP1) checks a succinct proof. Resolves on-chain in a single proof verification, no bisection."},
}

// Read fetches the full dispute-system snapshot for one L2.
func Read(ctx context.Context, l1RPCURL, chainName string, sysConfig, dgf, portal common.Address) (Snapshot, error) {
	cli, err := ethclient.DialContext(ctx, l1RPCURL)
	if err != nil {
		return Snapshot{}, fmt.Errorf("dial l1: %w", err)
	}
	defer cli.Close()

	snap := Snapshot{
		Chain:              chainName,
		SystemConfig:       sysConfig,
		OptimismPortal:     portal,
		DisputeGameFactory: dgf,
	}

	dgfBC := bind.NewBoundContract(dgf, parsedABI, cli, nil, nil)
	portalBC := bind.NewBoundContract(portal, parsedABI, cli, nil, nil)

	callOpts := &bind.CallOpts{Context: ctx}

	// Portal-side reads: respectedGameType + anchorStateRegistry.
	if v, err := callAddress(portalBC, callOpts, "anchorStateRegistry"); err == nil {
		snap.AnchorStateRegistry = v
	}
	if v, err := callUint32(portalBC, callOpts, "respectedGameType"); err == nil {
		snap.RespectedGameType = v
	}

	// Factory-side reads.
	if v, err := callString(dgfBC, callOpts, "version"); err == nil {
		snap.FactoryVersion = v
	}
	if v, err := callAddress(dgfBC, callOpts, "owner"); err == nil {
		snap.FactoryOwner = v
	}
	if v, err := callBigInt(dgfBC, callOpts, "gameCount"); err == nil {
		snap.GameCount = v.Uint64()
	}

	// Per-game-type implementation + bond + impl-level config.
	snap.Implementations = make([]GameTypeInfo, 0, len(gameTypes))
	for _, gt := range gameTypes {
		info := GameTypeInfo{
			GameType:    gt.id,
			Name:        gt.name,
			Family:      gt.family,
			Description: gt.desc,
			IsRespected: gt.id == snap.RespectedGameType,
		}
		if impl, err := callAddressArg(dgfBC, callOpts, "gameImpls", gt.id); err == nil {
			info.Impl = impl
			info.Registered = impl != (common.Address{})
		}
		if bond, err := callBigIntArg(dgfBC, callOpts, "initBonds", gt.id); err == nil {
			info.InitBondWei = bond.String()
			info.InitBondETH = formatETH(bond)
		}
		// Pull impl-level timing config when the impl is registered. Errors
		// are silently ignored — different game types expose different
		// surfaces and that's expected.
		if info.Registered {
			implBC := bind.NewBoundContract(info.Impl, parsedABI, cli, nil, nil)
			if v, err := callUint64(implBC, callOpts, "maxClockDuration"); err == nil {
				info.MaxClockDuration = v
			}
			if v, err := callUint64(implBC, callOpts, "clockExtension"); err == nil {
				info.ClockExtension = v
			}
			if v, err := callUint64(implBC, callOpts, "maxChallengeDuration"); err == nil {
				info.MaxChallengeDuration = v
			}
			if v, err := callUint64(implBC, callOpts, "maxProveDuration"); err == nil {
				info.MaxProveDuration = v
			}
			if v, err := callBigInt(implBC, callOpts, "splitDepth"); err == nil && v != nil {
				info.SplitDepth = v.Uint64()
			}
			if v, err := callBigInt(implBC, callOpts, "maxDepth"); err == nil && v != nil {
				info.MaxDepth = v.Uint64()
			}
		}
		snap.Implementations = append(snap.Implementations, info)

		if info.IsRespected {
			snap.RespectedGameTypeName = info.Name
			snap.RespectedGameTypeDesc = info.Description
		}
	}

	// Last few games (newest first), capped.
	const recentCap = 5
	if snap.GameCount > 0 {
		start := uint64(0)
		if snap.GameCount > recentCap {
			start = snap.GameCount - recentCap
		}
		for i := snap.GameCount; i > start; i-- {
			idx := i - 1
			gameType, ts, proxy, err := callGameAtIndex(dgfBC, callOpts, idx)
			if err != nil {
				continue
			}
			ref := GameRef{
				Index:        idx,
				GameType:     gameType,
				GameTypeName: nameForGameType(gameType),
				CreatedAt:    ts,
				Proxy:        proxy,
			}
			// Best-effort live read on the game proxy itself.
			gameBC := bind.NewBoundContract(proxy, parsedABI, cli, nil, nil)
			if s, err := callUint8(gameBC, callOpts, "status"); err == nil {
				ref.Status = s
				ref.StatusName = gameStatusName(s)
			}
			if v, err := callUint64(gameBC, callOpts, "resolvedAt"); err == nil {
				ref.ResolvedAt = v
			}
			if v, err := callBigInt(gameBC, callOpts, "l2SequenceNumber"); err == nil && v != nil {
				ref.L2SequenceNumber = v.Uint64()
			}
			if v, err := callBytes32(gameBC, callOpts, "rootClaim"); err == nil {
				ref.RootClaim = v
			}
			if v, err := callUint64(gameBC, callOpts, "maxClockDuration"); err == nil {
				ref.MaxClockDuration = v
			}
			// Compute the deadline from createdAt + maxClockDuration where we
			// have both. For ZK games this is meaningless (deadline is per-claim
			// and lives in claimData); leaving it to the frontend to decide.
			if ref.MaxClockDuration > 0 && ref.CreatedAt > 0 {
				ref.DeadlineTimestamp = ref.CreatedAt + ref.MaxClockDuration
			}
			snap.RecentGames = append(snap.RecentGames, ref)
		}
	}

	snap.Explainer = explain(snap)
	return snap, nil
}

func nameForGameType(t uint32) string {
	for _, gt := range gameTypes {
		if gt.id == t {
			return gt.name
		}
	}
	return fmt.Sprintf("GameType(%d)", t)
}

func gameStatusName(s uint8) string {
	switch s {
	case 0:
		return "IN_PROGRESS"
	case 1:
		return "CHALLENGER_WINS"
	case 2:
		return "DEFENDER_WINS"
	default:
		return fmt.Sprintf("UNKNOWN(%d)", s)
	}
}

func explain(s Snapshot) []string {
	out := []string{
		fmt.Sprintf("This L2 finalizes via the dispute game at type %d (%s).", s.RespectedGameType, s.RespectedGameTypeName),
		s.RespectedGameTypeDesc,
	}
	switch s.RespectedGameType {
	case 0:
		out = append(out, "Anyone can propose an output root (after posting an init bond) and anyone can challenge it. Disagreements are resolved by interactive bisection over the MIPS execution trace until a single instruction can be re-executed on L1.")
	case 1:
		out = append(out, "Only the whitelisted proposer creates games; only the whitelisted challenger can challenge. The bisection mechanics are identical to CANNON, but censorship-resistance is reduced — a misbehaving proposer can stall finality.")
	case 10:
		out = append(out, "There is no bisection. The proposer submits a ZK proof attesting that the claim is the correct successor of the anchor state, and a verifier contract checks it on-chain. Resolution is a single tx; latency = proof generation + L1 inclusion.")
	}
	out = append(out, fmt.Sprintf("Switching consensus method = call DisputeGameFactory.setImplementation(GameType.wrap(N), impl, args) from the factory owner (%s) for the new type N, then point AnchorStateRegistry at it.", s.FactoryOwner.Hex()))
	return out
}

func formatETH(wei *big.Int) string {
	if wei == nil || wei.Sign() == 0 {
		return "0"
	}
	// Wei → ETH with 6 decimals of precision.
	num := new(big.Float).SetInt(wei)
	denom := new(big.Float).SetInt(new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil))
	q := new(big.Float).Quo(num, denom)
	return q.Text('f', 6)
}

// --- thin helpers around bind.BoundContract.Call ---

func callString(bc *bind.BoundContract, opts *bind.CallOpts, method string, args ...interface{}) (string, error) {
	var out []interface{}
	if err := bc.Call(opts, &out, method, args...); err != nil {
		return "", err
	}
	v, _ := out[0].(string)
	return v, nil
}

func callAddress(bc *bind.BoundContract, opts *bind.CallOpts, method string, args ...interface{}) (common.Address, error) {
	var out []interface{}
	if err := bc.Call(opts, &out, method, args...); err != nil {
		return common.Address{}, err
	}
	v, _ := out[0].(common.Address)
	return v, nil
}

func callAddressArg(bc *bind.BoundContract, opts *bind.CallOpts, method string, gameType uint32) (common.Address, error) {
	return callAddress(bc, opts, method, gameType)
}

func callUint32(bc *bind.BoundContract, opts *bind.CallOpts, method string, args ...interface{}) (uint32, error) {
	var out []interface{}
	if err := bc.Call(opts, &out, method, args...); err != nil {
		return 0, err
	}
	v, _ := out[0].(uint32)
	return v, nil
}

func callUint64(bc *bind.BoundContract, opts *bind.CallOpts, method string, args ...interface{}) (uint64, error) {
	var out []interface{}
	if err := bc.Call(opts, &out, method, args...); err != nil {
		return 0, err
	}
	v, _ := out[0].(uint64)
	return v, nil
}

func callUint8(bc *bind.BoundContract, opts *bind.CallOpts, method string, args ...interface{}) (uint8, error) {
	var out []interface{}
	if err := bc.Call(opts, &out, method, args...); err != nil {
		return 0, err
	}
	v, _ := out[0].(uint8)
	return v, nil
}

func callBytes32(bc *bind.BoundContract, opts *bind.CallOpts, method string, args ...interface{}) (string, error) {
	var out []interface{}
	if err := bc.Call(opts, &out, method, args...); err != nil {
		return "", err
	}
	v, _ := out[0].([32]byte)
	return "0x" + fmt.Sprintf("%x", v[:]), nil
}

func callBigInt(bc *bind.BoundContract, opts *bind.CallOpts, method string, args ...interface{}) (*big.Int, error) {
	var out []interface{}
	if err := bc.Call(opts, &out, method, args...); err != nil {
		return nil, err
	}
	v, _ := out[0].(*big.Int)
	if v == nil {
		v = big.NewInt(0)
	}
	return v, nil
}

func callBigIntArg(bc *bind.BoundContract, opts *bind.CallOpts, method string, gameType uint32) (*big.Int, error) {
	return callBigInt(bc, opts, method, gameType)
}

func callGameAtIndex(bc *bind.BoundContract, opts *bind.CallOpts, idx uint64) (uint32, uint64, common.Address, error) {
	var out []interface{}
	if err := bc.Call(opts, &out, "gameAtIndex", new(big.Int).SetUint64(idx)); err != nil {
		return 0, 0, common.Address{}, err
	}
	if len(out) < 3 {
		return 0, 0, common.Address{}, fmt.Errorf("gameAtIndex returned %d values", len(out))
	}
	gt, _ := out[0].(uint32)
	ts, _ := out[1].(uint64)
	proxy, _ := out[2].(common.Address)
	return gt, ts, proxy, nil
}
