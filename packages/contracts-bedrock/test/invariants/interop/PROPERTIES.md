# Interop Advanced Testing Campaign

The goal of this campaign is to come up with a testing suite that fuzzes over the interop invariants introduced or modified by the Wonderland team. The main focus is to test stateful properties, and dismiss unit tests that are already covered by the existing test suite.

## Milestones

- SupERC20: Mainly composed of invariants related to `SuperchainERC20` and `SuperchainWETH` contracts, as well as the `SuperchainTokenBridge` and other contracts that interact with them.
- SharedLockbox: Mainly composed of invariants related to the `SharedLockbox` and `OptimismPortal` contracts, as well as other contracts that interact with them.

# Properties

**Legend:**

- `[ ]`: property not yet tested
- `**[ ]**`: property not yet tested, dev/research team has asked for extra focus on it
- `[X]`: tested/proven property
- `[~]`: partially tested/proven property
- `:(`: property won't be tested due to some limitation

| id  | milestone     | description                                                                                                                                                                                                              | tested |
| --- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| 1   | SupERC20      | Bridging `SuperchainERC20s` from the origin to the destination chain decreases the token's `totalSupply` and the sender's balance on the origin chain by exactly the input amount.                                       | [ ]    |
| 2   | SupERC20      | Relaying `SuperchainERC20`s sent from the origin chain increases the token's `totalSupply` and the sender's balance on the destination chain by exactly the input amount.                                                | [ ]    |
| 3   | SupERC20      | Bridging `SuperchainWETH` from the origin to the destination chain increases the `ETHLiquidity` Ether balance and decreases the `SuperchainWETH` Ether balance and sender's balance by exactly the input amount.         | [ ]    |
| 4   | SupERC20      | Relaying `SuperchainWETH` sent from the origin chain decreases the `ETHLiquidity` Ether balance and increases the `SuperchainWETH` Ether balance and the sender's balance by exactly the input amount.                   | [ ]    |
| 5   | SupERC20      | Calls to `sendERC20` succeed as long as the caller has enough balance and the destination chain is on the dependency set.                                                                                                | [ ]    |
| 6   | SupERC20      | Calls to `relayERC20` always succeed as long as the sender and cross-domain caller are valid.                                                                                                                            | [ ]    |
| 7   | SupERC20      | The `ETHLiquidity#mint` call MUST always succeed when the caller is the `SuperchainWETH` contract.                                                                                                                       | [ ]    |
| 8   | SupERC20      | The `ETHLiquidity#burn` call MUST always succeed when the caller is the `SuperchainWETH` contract.                                                                                                                       | [ ]    |
| 9   | SupERC20      | `sendERC20` MUST use the token address from which it is sending as the target on the destination.                                                                                                                        | [ ]    |
| 10  | SupERC20      | Calls to `SuperchainERC20#crosschainBurn` MUST always succeed as long as the caller is `SuperchainTokenBridge`.                                                                                                          | [ ]    |
| 11  | SupERC20      | Calls to `SuperchainERC20#crosschainMint` MUST always succeed as long as the caller is `SuperchainTokenBridge`.                                                                                                          | [ ]    |
| 12  | SupERC20      | The `SuperchainTokenBridge#sendERC20()` function MUST exclusively use the `L2toL2CrossDomainMessenger` for messaging.                                                                                                    | [ ]    |
| 13  | SupERC20      | The `SuperchainTokenBridge#relayERC20()` function MUST only process messages originating from the `L2toL2CrossDomainMessenger`.                                                                                          | [ ]    |
| 14  | SupERC20      | `ETHLiquidity#mint()` MUST never be callable such that balance would decrease below `0`.                                                                                                                                 | [ ]    |
| 15  | SupERC20      | `ETHLiquidity#burn()` MUST never be callable such that balance would increase beyond `type(uint256).max`.                                                                                                                | [ ]    |
| 16  | SharedLockbox | The total withdrawable ETH amount present on all the dependency set chains MUST NEVER be more than the amount held by the `SharedLockbox` of the cluster.                                                                | [ ]    |
| 17  | SharedLockbox | The `OptimismPortal` MUST lock the ETH amount on the `SharedLockbox` when on a deposit transaction with value greater than zero, without holding any ETH balance from the depositing users.                              | [ ]    |
| 18  | SharedLockbox | The `OptimismPortal` MUST unlock the ETH amount being withdrawn from the `SharedLockbox` if it is greater than zero.                                                                                                     | [ ]    |
| 19  | SharedLockbox | The `SharedLockbox` MUST NOT trigger a new deposit transaction when unlocking ETH from the `OptimismPortal`.                                                                                                             | [ ]    |
| 20  | SharedLockbox | Once `SuperchainConfig#addChain` is called, a message to each chain on the dependency set MUST be sent to include the input chain, as well as a message to the input chain for each current chain on the dependency set. | [ ]    |
| 21  | SharedLockbox | The chain MUST be added to the dependency set on L2 as long as the config deposit transaction and the caller are valid.                                                                                                  | [ ]    |
| 22  | SharedLockbox | Valid messages MUST revert if the message comes from a chain that is not in the destination chain's dependency set.                                                                                                      | [ ]    |
| 23  | SharedLockbox | `SuperchainConfig#addChain` MUST revert if the new chain dependency set size is greater than zero.                                                                                                                       | [ ]    |
| 24  | SharedLockbox | No Ether MUST flow out from the `SharedLockbox` contract when in a paused state.                                                                                                                                         | [ ]    |
| 25  | SharedLockbox | The `LiquidityMigrator` MUST migrate the whole `OptimismPortal` ETH balance to the `SharedLockbox`.                                                                                                                      | [ ]    |
