package derive

import (
	"bytes"
	"errors"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"

	"github.com/ethereum-optimism/optimism/op-node/rollup"
	"github.com/ethereum-optimism/optimism/op-service/eth"
	"github.com/ethereum-optimism/optimism/op-service/predeploys"
	"github.com/ethereum-optimism/optimism/op-service/solabi"
)

const (
	AddDependencySignature = "addDependency(address,uint256,address)"
	AddDependencyLen       = 4 + 32*3
	AddDependencyGas       = uint64(21_000 + 250_000)
)

var (
	AddDependencyBytes4 = crypto.Keccak256([]byte(AddDependencySignature))[:4]
	DependencyManager   = predeploys.DependencyManagerAddr
)

// AddDependencyData represents the data needed to add a new dependency to the cluster.
type AddDependencyData struct {
	superchainConfig common.Address
	chainId          *big.Int
	systemConfig     common.Address
}

// AddDependencyDeposit Binary Format
// +---------+--------------------------+
// | Bytes   | Field                    |
// +---------+--------------------------+
// | 4       | Function signature       |
// | 32      | superchainConfig address |
// | 32      | chainId uint256          |
// | 32      | systemConfig address     |
// +---------+--------------------------+

func (addDep *AddDependencyData) marshalBinaryAddDependencyDeposit() ([]byte, error) {
	w := bytes.NewBuffer(make([]byte, 0, AddDependencyLen))
	if err := solabi.WriteSignature(w, AddDependencyBytes4); err != nil {
		return nil, err
	}
	if err := solabi.WriteAddress(w, addDep.superchainConfig); err != nil {
		return nil, err
	}
	if err := solabi.WriteUint256(w, addDep.chainId); err != nil {
		return nil, err
	}
	if err := solabi.WriteAddress(w, addDep.systemConfig); err != nil {
		return nil, err
	}
	return w.Bytes(), nil
}

func (addDep *AddDependencyData) unmarshalBinaryAddDependencyDeposit(data []byte) error {
	if len(data) != AddDependencyLen {
		return fmt.Errorf("data is unexpected length: %d", len(data))
	}
	reader := bytes.NewReader(data)

	var err error
	if _, err := solabi.ReadAndValidateSignature(reader, AddDependencyBytes4); err != nil {
		return err
	}
	if addDep.superchainConfig, err = solabi.ReadAddress(reader); err != nil {
		return err
	}
	if addDep.chainId, err = solabi.ReadUint256(reader); err != nil {
		return err
	}
	if addDep.systemConfig, err = solabi.ReadAddress(reader); err != nil {
		return err
	}
	if !solabi.EmptyReader(reader) {
		return errors.New("too many bytes")
	}
	return nil
}

// AddDependencyDeposit creates a deposit transaction to add a new chainId to the dependency set.
// The new dependency is added on L2 through the DependencyManager contract.
// This triggers an L2 to L1 withdrawal, which calls the L1 SuperchainConfig with the added chainId and it's corresponding L1 SystemConfig address
// It also enables the Portal to interact with the SharedLockbox, and migrates it's ETH liquidity.
func AddDependencyDeposit(seqNumber uint64, block eth.BlockInfo, addDependencyData *AddDependencyData) (*types.DepositTx, error) {
	source := AfterForceIncludeSource{
		L1BlockHash: block.Hash(),
		SeqNumber:   seqNumber,
	}
	addDependencyBytes, err := addDependencyData.marshalBinaryAddDependencyDeposit()
	if err != nil {
		return nil, fmt.Errorf("failed to marshal AddDependency data: %w", err)
	}

	out := &types.DepositTx{
		SourceHash:          source.SourceHash(),
		From:                L1InfoDepositerAddress,
		To:                  &DependencyManager,
		Mint:                nil,
		Value:               big.NewInt(0),
		Gas:                 AddDependencyGas,
		IsSystemTransaction: false,
		Data:                addDependencyBytes,
	}
	return out, nil
}

func AddDependencyBytes(seqNumber uint64, l1Info eth.BlockInfo, rollupCfg *rollup.Config, newDependency *big.Int) ([]byte, error) {
	newDependencyData := &AddDependencyData{
		superchainConfig: rollupCfg.ClusterConfig.SuperchainConfig,
		chainId:          newDependency,
		systemConfig:     rollupCfg.ClusterConfig.SystemConfig[newDependency],
	}

	dep, err := AddDependencyDeposit(seqNumber, l1Info, newDependencyData)
	if err != nil {
		return nil, fmt.Errorf("failed to create AddDependency tx: %w", err)
	}
	addDependencyTx := types.NewTx(dep)
	opaqueAddDependencyTx, err := addDependencyTx.MarshalBinary()
	if err != nil {
		return nil, fmt.Errorf("failed to encode AddDependency tx: %w", err)
	}
	return opaqueAddDependencyTx, nil
}
