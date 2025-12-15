package v5_0_0

import (
	"encoding/json"
	"fmt"
	"math/big"

	"github.com/ethereum-optimism/optimism/op-chain-ops/script"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/artifacts"
	"github.com/ethereum-optimism/optimism/op-deployer/pkg/deployer/opcm"
	"github.com/ethereum/go-ethereum/common"
	"github.com/lmittmann/w3"
)

// GameType represents the type of dispute game.
type GameType uint32

const (
	GameTypeCannon             GameType = 0
	GameTypePermissionedCannon GameType = 1
	GameTypeCannonKona         GameType = 2
)

// UpgradeOPChainInput is the top-level input for upgrading an OP Chain.
// While both OPCM versions are supported this struct is used for JSON unmarshaling only and contains structured data.
type UpgradeOPChainInput struct {
	Prank          common.Address `json:"prank"`
	Opcm           common.Address `json:"opcm"`
	UpgradeInputV2 UpgradeInputV2 `json:"upgradeInput"`
}

// UpgradeInputV2 contains the configuration for upgrading an OP Chain.
type UpgradeInputV2 struct {
	SystemConfig       common.Address      `json:"systemConfig"`
	DisputeGameConfigs []DisputeGameConfig `json:"disputeGameConfigs"`
	ExtraInstructions  []ExtraInstruction  `json:"extraInstructions"`
}

// DisputeGameConfig contains configuration for a dispute game.
type DisputeGameConfig struct {
	Enabled  bool     `json:"enabled"`
	InitBond *big.Int `json:"initBond"`
	GameType GameType `json:"gameType"`
	GameArgs []byte   `json:"gameArgs"`
}

// ExtraInstruction represents additional upgrade instructions.
type ExtraInstruction struct {
	Key  string `json:"key"`
	Data []byte `json:"data"`
}

// ScriptInput is the input struct that matches the Solidity UpgradeOPChainInput contract.
// Since the script receives the upgrade input as opaque bytes, this is a intermediary struct to match the script input.
// Once OPCM v1 is sunset, this struct can be removed and the UpgradeInputV2 struct can be used directly.
type ScriptInput struct {
	Prank        common.Address `abi:"prank"`
	Opcm         common.Address `abi:"opcm"`
	UpgradeInput []byte         `abi:"upgradeInput"`
}

var upgradeInputEncoder = w3.MustNewFunc(
	"dummy((address systemConfig,(bool enabled,uint256 initBond,uint32 gameType,bytes gameArgs)[] disputeGameConfigs,(string key,bytes data)[] extraInstructions))",
	"",
)

// encodeUpgradeInput encodes the UpgradeInputV2 to opaque bytes.
func encodeUpgradeInput(input UpgradeInputV2) ([]byte, error) {
	data, err := upgradeInputEncoder.EncodeArgs(&input)
	if err != nil {
		return nil, fmt.Errorf("failed to encode upgrade input: %w", err)
	}

	// Strip the 4-byte function selector
	return data[4:], nil
}

// UpgradeOPChain is the script interface for upgrading an OP Chain.
type UpgradeOPChain struct {
	Run func(input common.Address)
}

// Upgrade executes the OP Chain upgrade script.
func Upgrade(host *script.Host, input UpgradeOPChainInput) error {
	// Encode the UpgradeInputV2 to opaque bytes
	upgradeInputBytes, err := encodeUpgradeInput(input.UpgradeInputV2)
	if err != nil {
		return fmt.Errorf("failed to encode upgrade input: %w", err)
	}

	// Create the script input with opaque bytes
	scriptInput := ScriptInput{
		Prank:        input.Prank,
		Opcm:         input.Opcm,
		UpgradeInput: upgradeInputBytes,
	}

	return opcm.RunScriptVoid(host, scriptInput, "UpgradeOPChain.s.sol", "UpgradeOPChain")
}

// Upgrader implements the upgrade interface for v5.0.0.
type Upgrader struct{}

// Upgrade executes the upgrade with the given input.
func (u *Upgrader) Upgrade(host *script.Host, input json.RawMessage) error {
	var upgradeInput UpgradeOPChainInput
	if err := json.Unmarshal(input, &upgradeInput); err != nil {
		return fmt.Errorf("failed to unmarshal input: %w", err)
	}
	return Upgrade(host, upgradeInput)
}

// ArtifactsURL returns the URL for the artifacts for this version.
func (u *Upgrader) ArtifactsURL() string {
	return artifacts.CreateHttpLocator("579f43b5bbb43e74216b7ed33125280567df86eaf00f7621f354e4a68c07323e")
}

// DefaultUpgrader is the default upgrader instance for v5.0.0.
var DefaultUpgrader = new(Upgrader)
