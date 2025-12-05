package opcm

import (
	"github.com/ethereum-optimism/optimism/op-chain-ops/script"
	"github.com/ethereum/go-ethereum/common"
)

type ReadSuperchainDeploymentInput struct {
	OPCMAddress           common.Address `abi:"opcmAddress"` // TODO: Deprecate OPCMAddress field in OPCM v2
	SuperchainConfigProxy common.Address `abi:"superchainConfigProxy"`
}

type ReadSuperchainDeploymentOutput struct {
	// TODO: Deprecate ProtocolVersions fields in OPCM v2
	ProtocolVersionsImpl       common.Address
	ProtocolVersionsProxy      common.Address
	ProtocolVersionsOwner      common.Address
	RecommendedProtocolVersion [32]byte
	RequiredProtocolVersion    [32]byte

	SuperchainConfigImpl      common.Address
	SuperchainConfigProxy     common.Address
	SuperchainProxyAdmin      common.Address
	Guardian                  common.Address
	SuperchainProxyAdminOwner common.Address
}

type ReadSuperchainDeploymentScript script.DeployScriptWithOutput[ReadSuperchainDeploymentInput, ReadSuperchainDeploymentOutput]

func NewReadSuperchainDeploymentScript(host *script.Host) (ReadSuperchainDeploymentScript, error) {
	return script.NewDeployScriptWithOutputFromFile[ReadSuperchainDeploymentInput, ReadSuperchainDeploymentOutput](host, "ReadSuperchainDeployment.s.sol", "ReadSuperchainDeployment")
}
