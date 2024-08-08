# `OptimismSuperchainERC20` Invariants

## Calls to sendERC20 should always succeed as long as the actor has enough balance. Actor's balance should also not increase out of nowhere.
**Test:** [`OptimismSuperchainERC20.t.sol#L193`](../test/invariants/OptimismSuperchainERC20.t.sol#L193)



## Calls to relayERC20 should when a message is received from another chain. Actor's balance should get his amount minted when the message is realyed and the amount is greater than 0.
**Test:** [`OptimismSuperchainERC20.t.sol#L212`](../test/invariants/OptimismSuperchainERC20.t.sol#L212)

