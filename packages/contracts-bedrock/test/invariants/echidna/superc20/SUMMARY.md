supERC20 advanced testing campaign
==================================

Contracts in scope
------------------
- [ ] [OptimismSuperchainERC20](src/L2/OptimismSuperchainERC20.sol)
- [ ] [OptimismMintableERC20](src/universal/OptimismMintableERC20.sol)
- [ ] SuperchainERC20 (not yet implemented)
- [ ] SuperchainERC20Factory (not yet implemented, in PR #8)
- [ ] L2StandardBridgeInterop (not yet implemented, in PR #10)

Behavior assumed correct
-------------------------
- [ ] inclusion of relay transactions
- [ ] sequencer implementation
- [ ] [L2ToL2CrossDomainMessenger](src/L2/L2CrossDomainMessenger.sol)
- [ ] [CrossL2Inbox](src/L2/CrossL2Inbox.sol)


Pain points
-----------
- extensive use of transient storage by `L2ToL2CrossDomainMessenger` combined with lack of support for it in `hevm`
- a given supertoken should be guaranteed to have the same address across all chains, however we won't be able to replicate that in the fuzzing campaign since they have to all run in the same EVM

