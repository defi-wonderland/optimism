package explorer

// Minimal ABI fragments for the contracts the playground UI cares about
// decoding. We only include functions and events that are actually invoked
// by the bundled tools or that show up in the upgrade story.

const dgfABI = `[
  {"type":"function","name":"setImplementation","inputs":[{"name":"gameType","type":"uint32"},{"name":"impl","type":"address"}],"outputs":[]},
  {"type":"function","name":"setImplementation","inputs":[{"name":"gameType","type":"uint32"},{"name":"impl","type":"address"},{"name":"args","type":"bytes"}],"outputs":[]},
  {"type":"function","name":"setInitBond","inputs":[{"name":"gameType","type":"uint32"},{"name":"initBond","type":"uint256"}],"outputs":[]},
  {"type":"function","name":"create","inputs":[{"name":"gameType","type":"uint32"},{"name":"rootClaim","type":"bytes32"},{"name":"extraData","type":"bytes"}],"outputs":[{"name":"proxy","type":"address"}],"stateMutability":"payable"},
  {"type":"event","name":"DisputeGameCreated","inputs":[{"name":"disputeProxy","type":"address","indexed":true},{"name":"gameType","type":"uint32","indexed":true},{"name":"rootClaim","type":"bytes32","indexed":true}],"anonymous":false},
  {"type":"event","name":"ImplementationSet","inputs":[{"name":"impl","type":"address","indexed":false},{"name":"gameType","type":"uint32","indexed":true}],"anonymous":false},
  {"type":"event","name":"ImplementationArgsSet","inputs":[{"name":"gameType","type":"uint32","indexed":true},{"name":"args","type":"bytes","indexed":false}],"anonymous":false},
  {"type":"event","name":"InitBondUpdated","inputs":[{"name":"gameType","type":"uint32","indexed":true},{"name":"initBond","type":"uint256","indexed":false}],"anonymous":false}
]`

const portalABI = `[
  {"type":"function","name":"depositTransaction","inputs":[{"name":"to","type":"address"},{"name":"value","type":"uint256"},{"name":"gasLimit","type":"uint64"},{"name":"isCreation","type":"bool"},{"name":"data","type":"bytes"}],"outputs":[],"stateMutability":"payable"},
  {"type":"function","name":"proveWithdrawalTransaction","inputs":[{"name":"tx","type":"tuple","components":[{"name":"nonce","type":"uint256"},{"name":"sender","type":"address"},{"name":"target","type":"address"},{"name":"value","type":"uint256"},{"name":"gasLimit","type":"uint256"},{"name":"data","type":"bytes"}]},{"name":"disputeGameIndex","type":"uint256"},{"name":"outputRootProof","type":"tuple","components":[{"name":"version","type":"bytes32"},{"name":"stateRoot","type":"bytes32"},{"name":"messagePasserStorageRoot","type":"bytes32"},{"name":"latestBlockhash","type":"bytes32"}]},{"name":"withdrawalProof","type":"bytes[]"}],"outputs":[]},
  {"type":"function","name":"finalizeWithdrawalTransaction","inputs":[{"name":"tx","type":"tuple","components":[{"name":"nonce","type":"uint256"},{"name":"sender","type":"address"},{"name":"target","type":"address"},{"name":"value","type":"uint256"},{"name":"gasLimit","type":"uint256"},{"name":"data","type":"bytes"}]}],"outputs":[]},
  {"type":"event","name":"TransactionDeposited","inputs":[{"name":"from","type":"address","indexed":true},{"name":"to","type":"address","indexed":true},{"name":"version","type":"uint256","indexed":true},{"name":"opaqueData","type":"bytes","indexed":false}],"anonymous":false}
]`

const anchorRegistryABI = `[
  {"type":"function","name":"setRespectedGameType","inputs":[{"name":"gameType","type":"uint32"}],"outputs":[]},
  {"type":"function","name":"updateRetirementTimestamp","inputs":[],"outputs":[]},
  {"type":"function","name":"blacklistDisputeGame","inputs":[{"name":"game","type":"address"}],"outputs":[]},
  {"type":"function","name":"setAnchorState","inputs":[{"name":"game","type":"address"}],"outputs":[]},
  {"type":"event","name":"RespectedGameTypeSet","inputs":[{"name":"gameType","type":"uint32","indexed":false}],"anonymous":false},
  {"type":"event","name":"AnchorUpdated","inputs":[{"name":"game","type":"address","indexed":false}],"anonymous":false},
  {"type":"event","name":"DisputeGameBlacklisted","inputs":[{"name":"game","type":"address","indexed":false}],"anonymous":false},
  {"type":"event","name":"RetirementTimestampSet","inputs":[{"name":"timestamp","type":"uint256","indexed":false}],"anonymous":false}
]`

const systemConfigABI = `[
  {"type":"function","name":"setGasLimit","inputs":[{"name":"gasLimit","type":"uint64"}],"outputs":[]},
  {"type":"function","name":"setUnsafeBlockSigner","inputs":[{"name":"signer","type":"address"}],"outputs":[]},
  {"type":"function","name":"setBatcherHash","inputs":[{"name":"batcherHash","type":"bytes32"}],"outputs":[]},
  {"type":"function","name":"setEIP1559Params","inputs":[{"name":"eip1559Params","type":"bytes8"}],"outputs":[]}
]`

// AbiSet is the canonical map used by the server to populate the registry.
var AbiSet = map[string]string{
	"DisputeGameFactory":  dgfABI,
	"OptimismPortal":      portalABI,
	"AnchorStateRegistry": anchorRegistryABI,
	"SystemConfig":        systemConfigABI,
}
