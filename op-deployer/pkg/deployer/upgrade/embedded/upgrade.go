package embedded

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

// ScriptInput represents the input struct that is actually passed to the script.
// It contains the prank, opcm, and upgrade input.
type ScriptInput struct {
	Prank        common.Address `evm:"prank"`
	Opcm         common.Address `evm:"opcm"`
	UpgradeInput []byte         `evm:"upgradeInput"`
}

// UpgradeOPChainInput represents the struct that is read from the config file.
// It contains both fields for the old and new upgrade input.
type UpgradeOPChainInput struct {
	Prank          common.Address  `json:"prank"`
	Opcm           common.Address  `json:"opcm"`
	ChainConfigs   []OPChainConfig `json:"chainConfigs,omitempty"`
	UpgradeInputV2 *UpgradeInputV2 `json:"upgradeInput,omitempty"`
}

// UpgradeInputV2 represents the new upgrade input in OPCM v2.
type UpgradeInputV2 struct {
	SystemConfig       common.Address      `json:"systemConfig"`
	DisputeGameConfigs []DisputeGameConfig `json:"disputeGameConfigs"`
	ExtraInstructions  []ExtraInstruction  `json:"extraInstructions"`
}

// DisputeGameConfig represents the configuration for a dispute game.
type DisputeGameConfig struct {
	Enabled                       bool                           `json:"enabled"`
	InitBond                      *big.Int                       `json:"initBond"`
	GameType                      GameType                       `json:"gameType"`
	FaultDisputeGameConfig        *FaultDisputeGameConfig        `json:"faultDisputeGameConfig,omitempty"`
	PermissionedDisputeGameConfig *PermissionedDisputeGameConfig `json:"permissionedDisputeGameConfig,omitempty"`
}

type FaultDisputeGameConfig struct {
	AbsolutePrestate common.Hash `json:"absolutePrestate"`
}

type PermissionedDisputeGameConfig struct {
	AbsolutePrestate common.Hash    `json:"absolutePrestate"`
	Proposer         common.Address `json:"proposer"`
	Challenger       common.Address `json:"challenger"`
}

// ExtraInstruction represents an additional upgrade instruction for the upgrade on OPCM v2.
type ExtraInstruction struct {
	Key  string `json:"key"`
	Data []byte `json:"data"`
}

// GameType represents the type of dispute game.
type GameType uint32

const (
	GameTypeCannon             GameType = 0
	GameTypePermissionedCannon GameType = 1
	GameTypeSuperCannon        GameType = 4
	GameTypeSuperPermCannon    GameType = 5
	GameTypeCannonKona         GameType = 8
	GameTypeSuperCannonKona    GameType = 9
)

var (
	// This is used to encode the fault dispute game config for the upgrade input
	faultEncoder = w3.MustNewFunc("dummy((bytes32 absolutePrestate))", "")

	// This is used to encode the permissioned dispute game config for the upgrade input
	permEncoder = w3.MustNewFunc("dummy((bytes32 absolutePrestate,address proposer,address challenger))", "")

	// This is used to encode the upgrade input for the upgrade input
	upgradeInputEncoder = w3.MustNewFunc("dummy((address systemConfig,(bool enabled,uint256 initBond,uint32 gameType,bytes gameArgs)[] disputeGameConfigs,(string key,bytes data)[] extraInstructions))",
		"")

	// This is used to encode the OP Chain config for the upgrade input
	opChainConfigEncoder = w3.MustNewFunc("dummy((address systemConfigProxy,bytes32 cannonPrestate,bytes32 cannonKonaPrestate)[])", "")
)

// OPChainConfig represents the configuration for an OP Chain upgrade on OPCM v1.
type OPChainConfig struct {
	SystemConfigProxy  common.Address `json:"systemConfigProxy"`
	CannonPrestate     common.Hash    `json:"cannonPrestate"`
	CannonKonaPrestate common.Hash    `json:"cannonKonaPrestate"`
}

func (u *UpgradeOPChainInput) EncodedOpChainConfigs() ([]byte, error) {
	data, err := opChainConfigEncoder.EncodeArgs(u.ChainConfigs)
	if err != nil {
		return nil, fmt.Errorf("failed to encode chain configs: %w", err)
	}
	return data[4:], nil
}

func (u *UpgradeOPChainInput) EncodedUpgradeInputV2() ([]byte, error) {

	// We need to create another intermediate struct to match the encoder expectation
	type EncodableDisputeGameConfig struct {
		Enabled  bool
		InitBond *big.Int
		GameType uint32
		GameArgs []byte
	}

	type EncodableUpgradeInput struct {
		SystemConfig       common.Address
		DisputeGameConfigs []EncodableDisputeGameConfig
		ExtraInstructions  []ExtraInstruction
	}

	encodableConfigs := make([]EncodableDisputeGameConfig, len(u.UpgradeInputV2.DisputeGameConfigs))

	// Validate and encode each game config
	for i, gameConfig := range u.UpgradeInputV2.DisputeGameConfigs {
		var gameArgs []byte
		var err error

		if gameConfig.Enabled {
			if gameConfig.GameType == GameTypeCannon || gameConfig.GameType == GameTypeCannonKona {
				if gameConfig.FaultDisputeGameConfig == nil {
					return nil, fmt.Errorf("faultDisputeGameConfig is required for game type %d", gameConfig.GameType)
				}
				gameArgs, err = faultEncoder.EncodeArgs(gameConfig.FaultDisputeGameConfig)
				if err != nil {
					return nil, fmt.Errorf("failed to encode fault game config: %w", err)
				}
				gameArgs = gameArgs[4:]
			}

			if gameConfig.GameType == GameTypePermissionedCannon {
				if gameConfig.PermissionedDisputeGameConfig == nil {
					return nil, fmt.Errorf("permissionedDisputeGameConfig is required for game type %d", gameConfig.GameType)
				}
				gameArgs, err = permEncoder.EncodeArgs(gameConfig.PermissionedDisputeGameConfig)
				if err != nil {
					return nil, fmt.Errorf("failed to encode permissioned game config: %w", err)
				}
				gameArgs = gameArgs[4:]
			}
		}

		encodableConfigs[i] = EncodableDisputeGameConfig{
			Enabled:  gameConfig.Enabled,
			InitBond: gameConfig.InitBond,
			GameType: uint32(gameConfig.GameType),
			GameArgs: gameArgs,
		}
	}

	// Create encodable input
	encodableInput := EncodableUpgradeInput{
		SystemConfig:       u.UpgradeInputV2.SystemConfig,
		DisputeGameConfigs: encodableConfigs,
		ExtraInstructions:  u.UpgradeInputV2.ExtraInstructions,
	}

	data, err := upgradeInputEncoder.EncodeArgs(encodableInput)
	if err != nil {
		return nil, fmt.Errorf("failed to encode upgrade input: %w", err)
	}

	return data[4:], nil
}

type UpgradeOPChain struct {
	Run func(input common.Address)
}

func Upgrade(host *script.Host, input UpgradeOPChainInput) error {
	// Determine which input format to use and encode it
	var encodedUpgradeInput []byte
	var encodedError error

	if input.UpgradeInputV2 != nil {
		// Prefer V2 input if present
		encodedUpgradeInput, encodedError = input.EncodedUpgradeInputV2()
	} else if len(input.ChainConfigs) > 0 {
		// Fall back to V1 input if V2 is not present
		encodedUpgradeInput, encodedError = input.EncodedOpChainConfigs()
	} else {
		// Neither input format is present
		return fmt.Errorf("failed to read either an upgrade input or config array")
	}

	if encodedError != nil {
		return encodedError
	}

	scriptInput := ScriptInput{
		Prank:        input.Prank,
		Opcm:         input.Opcm,
		UpgradeInput: encodedUpgradeInput,
	}
	return opcm.RunScriptVoid[ScriptInput](host, scriptInput, "UpgradeOPChain.s.sol", "UpgradeOPChain")
}

type Upgrader struct{}

func (u *Upgrader) Upgrade(host *script.Host, input json.RawMessage) error {
	var upgradeInput UpgradeOPChainInput
	if err := json.Unmarshal(input, &upgradeInput); err != nil {
		return fmt.Errorf("failed to unmarshal input: %w", err)
	}
	return Upgrade(host, upgradeInput)
}

func (u *Upgrader) ArtifactsURL() string {
	return artifacts.EmbeddedLocatorString
}

var DefaultUpgrader = new(Upgrader)
