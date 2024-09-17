# `OptimismSuperchainERC20` Invariants

## sum of supertoken total supply across all chains is always <= to convert(legacy, super)- convert(super, legacy)
**Test:** [`OptimismSuperchainERC20#L36`](../test/invariants/OptimismSuperchainERC20#L36)



## sum of supertoken total supply across all chains is equal to convert(legacy, super)- convert(super, legacy) when all when all cross-chain messages are processed
**Test:** [`OptimismSuperchainERC20#L57`](../test/invariants/OptimismSuperchainERC20#L57)



## many other assertion mode invariants are also defined  under `test/invariants/OptimismSuperchainERC20/fuzz/` .
**Test:** [`OptimismSuperchainERC20#L79`](../test/invariants/OptimismSuperchainERC20#L79)

since setting`fail_on_revert=false` also ignores StdAssertion failures, this invariant explicitly asks the handler for assertion test failures 

## Calls to sendERC20 should always succeed as long as the actor has enough balance. Actor's balance should also not increase out of nowhere but instead should decrease by the amount sent.
**Test:** [`OptimismSuperchainERC20.t.sol#L196`](../test/invariants/OptimismSuperchainERC20.t.sol#L196)



## Calls to relayERC20 should always succeeds when a message is received from another chain. Actor's balance should only increase by the amount relayed.
**Test:** [`OptimismSuperchainERC20.t.sol#L214`](../test/invariants/OptimismSuperchainERC20.t.sol#L214)

