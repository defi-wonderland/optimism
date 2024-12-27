# Interop Advanced Testing Campaign

The goal of this campaign is to develop a testing suite that fuzzes over the interop invariants introduced or modified by the Wonderland team. The main focus is to test stateful properties and dismiss unit tests that are already covered by the existing test suite.

## Milestones

- SupERC20: Mainly composed of invariants related to `SuperchainERC20` and `SuperchainWETH` contracts, as well as the `SuperchainTokenBridge` and other contracts that interact with them.
- SharedLockbox: Mainly composed of invariants related to the `SharedLockbox` and `OptimismPortal` contracts, as well as other contracts that interact with them.

# Properties

**Legend:**

- `[ ]`: property not yet tested
- `[X]`: tested/proven property
- `[~]`: partially tested/proven property
- `:(`: property won't be tested due to some limitation

| id  | milestone     | description                                                                                                                                                                                                      | tested |
| --- | ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| 1   | SupERC20      | Bridging `SuperchainERC20s` from the origin to the destination chain decreases the token's `totalSupply` and the sender's balance on the origin chain by exactly the input amount.                               | [ ]    |
| 2   | SupERC20      | Relaying `SuperchainERC20`s sent from the origin chain increases the token's `totalSupply` and the sender's balance on the destination chain by exactly the input amount.                                        | [ ]    |
| 3   | SupERC20      | Bridging `SuperchainWETH` from the origin to the destination chain increases the `ETHLiquidity` Ether balance and decreases the `SuperchainWETH` Ether balance and sender's balance by exactly the input amount. | [ ]    |
| 4   | SupERC20      | Relaying `SuperchainWETH` sent from the origin chain decreases the `ETHLiquidity` Ether balance and increases the `SuperchainWETH` Ether balance and the sender's balance by exactly the input amount.           | [ ]    |
| 5   | SupERC20      | Calls to `sendERC20` succeed as long as the caller has enough balance.                                                                                                                                           | [ ]    |
| 6   | SupERC20      | Calls to `relayERC20` always succeed as long as the sender and cross-domain caller are valid.                                                                                                                    | [ ]    |
| 7   | SupERC20      | The `ETHLiquidity#mint` call MUST always succeed when the caller is the `SuperchainWETH` contract.                                                                                                               | [ ]    |
| 8   | SupERC20      | The `ETHLiquidity#burn` call MUST always succeed when the caller is the `SuperchainWETH` contract.                                                                                                               | [ ]    |
| 9   | SupERC20      | `sendERC20` MUST use the token address from which it is sending as the target on the destination.                                                                                                                | [ ]    |
| 10  | SupERC20      | Calls to `SuperchainERC20#crosschainBurn` MUST always succeed as long as the caller is `SuperchainTokenBridge`.                                                                                                  | [ ]    |
| 11  | SupERC20      | Calls to `SuperchainERC20#crosschainMint` MUST always succeed as long as the caller is `SuperchainTokenBridge`.                                                                                                  | [ ]    |
| 12  | SupERC20      | The `SuperchainTokenBridge#sendERC20()` function MUST exclusively use the `L2toL2CrossDomainMessenger` for messaging.                                                                                            | [ ]    |
| 13  | SupERC20      | The `SuperchainTokenBridge#relayERC20()` function MUST only process messages originating from the `L2toL2CrossDomainMessenger`.                                                                                  | [ ]    |
| 14  | SupERC20      | `ETHLiquidity#mint()` MUST never be callable such that balance would decrease below `0`.                                                                                                                         | [ ]    |
| 15  | SupERC20      | `ETHLiquidity#burn()` MUST never be callable such that balance would increase beyond `type(uint256).max`.                                                                                                        | [ ]    |
| 16  | SharedLockbox | The total withdrawable ETH amount present on all the dependency set chains MUST NEVER be more than the amount held by the `SharedLockbox` of the cluster.                                                        | [ ]    |
| 17  | SharedLockbox | The `OptimismPortal` MUST lock the ETH amount on the `SharedLockbox` when on a deposit transaction with value greater than zero, without holding any ETH balance from the depositing users.                      | [ ]    |
| 18  | SharedLockbox | The `OptimismPortal` MUST unlock the ETH amount being withdrawn from the `SharedLockbox` if it is greater than zero.                                                                                             | [ ]    |
| 19  | SharedLockbox | The `SharedLockbox` MUST NOT trigger a new deposit transaction when unlocking ETH from the `OptimismPortal`.                                                                                                     | [ ]    |
| 20  | SharedLockbox | Once `SuperchainConfig#addChain` is successfully called, the chain must be added to the dependency set, and the `OptimismPortal` of it is set as authorized on the `SharedLockbox`.                              | [ ]    |
| 21  | SharedLockbox | No Ether MUST flow out from the `SharedLockbox` contract when in a paused state.                                                                                                                                 | [ ]    |
| 22  | SharedLockbox | The `LiquidityMigrator` MUST migrate the whole `OptimismPortal` ETH balance to the `SharedLockbox`.                                                                                                              | [ ]    |

---

<br><br>
The following properties are considered to be easily coverable by **Unit tests**, so they **won't be included in this campaign**:

| Id  | Description                                                                                                                 |
| --- | --------------------------------------------------------------------------------------------------------------------------- |
| 1   | Message to the same chain MUST be disallowed                                                                                |
| 2   | Only the Guardian MUST be able to authorize an `OptimismPortal`                                                             |
| 3   | Adding an `OptimismPortal` during a paused state MUST revert                                                                |
| 4   | Only `authorizedPortals` MUST be able to call `lockETH` and `unlockETH`                                                     |
| 5   | Only the `SuperchainConfig` contract MUST be able to add a new dependency                                                   |
| 6   | Only the `SuperchainConfig` contract MUST be able to remove a dependency                                                    |
| 7   | `isDeposit` MUST only be callable by the `CrossL2Inbox`                                                                     |
| 8   | `depositsComplete` and `setConfig` MUST be only callable by the `DEPOSITOR_ACCOUNT`                                         |
| 9   | Both minting and burning operations MUST be triggered only by the `Predeploys.SUPERCHAIN_TOKEN_BRIDGE`                      |
| 10  | Minting and burning operations MUST be done under the same address on origin and destination                                |
| 11  | `crosschainBurn()` MUST be called only by the `SuperchainTokenBridge`.                                                      |
| 12  | `crosschainBurn()` MUST Revert if attempting to send more than the sender's available balance.                              |
| 13  | `crosschainMint()` MUST be called only by the `SuperchainTokenBridge`.                                                      |
| 14  | `SuperchainTokenBridge#sendERC20()` function MUST exclusively send a message to the same address on the target chain        |
| 15  | `SuperchainTokenBridge#relayERC20()` function should only process messages originating from the same address.               |
| 16  | `ETHLiquidity` Initial balance MUST be set to `type(uint248).max`                                                           |
| 17  | `ETHLiquidity#mint()` MUST be called only by `SuperchainWETH`.                                                              |
| 18  | `ETHLiquidity#mint()` MUST Transfer the requested ETH value to the sending address.                                         |
| 19  | `ETHLiquidity#burn()` MUST be called only by `SuperchainWETH`.                                                              |
| 20  | `ETHLiquidity#burn()` MUST Accept ETH value.                                                                                |
| 21  | `isInDependencySet()` MUST return true for all the chain IDs of the chains that integrate the cluster, and false otherwise. |
| 22  | `addChain()` MUST be called only by the authorized `updater` role of the `SuperchainConfig`.                                |
| 23  | It MUST not be possible to validate or execute deposit transactions as messages                                             |
| 24  | `SuperchainWETH#withdraw()` MUST revert if triggered on a chain that does not use ETH as a native token.                    |
| 25  | `SuperchainWETH#deposit()` MUST Revert if triggered on a chain that does not use ETH as a native token                      |
| 26  | `ETHLiquidity#burn()` MUST Revert if called on a chain that does not use ETH as a native token.                             |
| 27  | `ETHLiquidity#mint()` MUST Revert if called on a chain that does not use ETH as a native token.                             |

---
