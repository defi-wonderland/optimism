# Interop Advanced Testing Campaign

The goal of this campaign is to develop a testing suite that fuzzes over the interop invariants introduced or modified by the Wonderland team. The main focus is to test stateful properties and dismiss unit tests that are already covered by the existing test suite.

## Milestones

- SuperchainERC20: Mainly composed of invariants related to `SuperchainERC20` and `SuperchainWETH` contracts, as well as the `SuperchainTokenBridge` and other contracts that interact with them.
- SharedLockbox: Mainly composed of invariants related to the `SharedLockbox` and `OptimismPortal` contracts, as well as other contracts that interact with them.

# Properties

**Legend:**

- `[ ]`: property not yet tested
- `[X]`: tested/proven property
- `[~]`: partially tested/proven property
- `:(`: property won't be tested due to some limitation

| id  | Milestone       | Invariant                                                                                                                                                                                                                                              | Tested |
| --- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :----: |
| 1   | SuperchainERC20 | Bridging `SuperchainERC20s` from the origin to the destination chain decreases the token's `totalSupply` and the sender's balance on the origin chain by exactly the input amount.                                                                     |  [ ]   |
| 2   | SuperchainERC20 | Relaying `SuperchainERC20`s sent from the origin chain increases the token's `totalSupply` and the sender's balance on the destination chain by exactly the input amount.                                                                              |  [ ]   |
| 3   | SuperchainERC20 | Bridging `SuperchainWETH` from the origin to the destination chain increases the `ETHLiquidity` Ether balance, and decreases the `SuperchainWETH` Ether balance and sender's `SuperchainWETH` balance on the origin chain by exactly the input amount. |  [ ]   |
| 4   | SuperchainERC20 | Relaying `SuperchainWETH` sent from the origin chain decreases the `ETHLiquidity` Ether balance, and increases `SuperchainWETH` Ether balance and the sender's `SuperchainWETH` balance on the origin chain by exactly the input amount.               |  [ ]   |
| 5   | SuperchainERC20 | The `SuperchainERC20` token MUST be compliant with the ERC20 standard.                                                                                                                                                                                 |  [ ]   |
| 6   | SuperchainERC20 | The `ETHLiquidity#mint` call MUST always succeed when the caller is the `SuperchainWETH` contract.                                                                                                                                                     |  [ ]   |
| 7   | SuperchainERC20 | The `ETHLiquidity#burn` call MUST always succeed when the caller is the `SuperchainWETH` contract.                                                                                                                                                     |  [ ]   |
| 8   | SuperchainERC20 | `ETHLiquidity#mint()` MUST never be callable such that balance would decrease below `0`.                                                                                                                                                               |  [ ]   |
| 9   | SuperchainERC20 | `ETHLiquidity#burn()` MUST never be callable such that balance would increase beyond `type(uint256).max`.                                                                                                                                              |  [ ]   |
| 10  | SharedLockbox   | The total withdrawable ETH amount present on all the dependency set’s chains MUST NEVER be more than the amount held by the `SharedLockbox` of the cluster.                                                                                            |  [ ]   |
| 11  | SharedLockbox   | The `OptimismPortal` MUST lock the ETH amount on the `SharedLockbox` when on a deposit transaction with value greater than zero, without holding any ETH balance from the depositing users.                                                            |  [ ]   |
| 12  | SharedLockbox   | The `OptimismPortal` MUST unlock the ETH amount being withdrawn from the `SharedLockbox` if it is greater than zero.                                                                                                                                   |  [ ]   |
| 13  | SharedLockbox   | The `LiquidityMigrator` MUST migrate the whole `OptimismPortal` ETH balance to the `SharedLockbox`.                                                                                                                                                    |  [ ]   |

---

<br><br>
The following properties are considered to be easily coverable by **Unit tests**, so they **won't be included in this campaign**:

| Id  | Description                                                                                                                                                                         |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 14  | Message to the same chain MUST be disallowed                                                                                                                                        |
| 15  | Only the `SuperchainConfig` MUST be able to authorize an `OptimismPortal`                                                                                                           |
| 16  | Adding an `OptimismPortal` during a paused state MUST revert                                                                                                                        |
| 17  | Only `authorizedPortals` MUST be able to call `lockETH` and `unlockETH`                                                                                                             |
| 18  | Only the `DependencyManager` MUST be able to add a new dependency                                                                                                                   |
| 19  | `isDeposit` MUST only be callable by the `CrossL2Inbox`                                                                                                                             |
| 20  | `depositsComplete` and `setConfig` MUST be only callable by the `DEPOSITOR_ACCOUNT`                                                                                                 |
| 21  | `crosschainBurn()` MUST be called only by the `SuperchainTokenBridge`.                                                                                                              |
| 22  | `crosschainMint()` MUST Revert if attempting to send more than the sender's available balance.                                                                                      |
| 23  | `crosschainMint()` MUST be called only by any the `SuperchainTokenBridge`.                                                                                                          |
| 24  | `SuperchainTokenBridge#sendERC20()` function MUST exclusively send a message to the same address on the target chain                                                                |
| 25  | `SuperchainTokenBridge#relayERC20()` function should only process messages originating from the same address.                                                                       |
| 26  | `ETHLiquidity` Initial balance MUST be set to `type(uint248).max`                                                                                                                   |
| 27  | `ETHLiquidity#mint()` MUST be called only by `SuperchainWETH`.                                                                                                                      |
| 28  | `ETHLiquidity#mint()` MUST Transfer requested ETH value to the sending address.                                                                                                     |
| 29  | `ETHLiquidity#burn()` MUST be called only by `SuperchainWETH`.                                                                                                                      |
| 30  | `ETHLiquidity#burn()` MUST Accept ETH value.                                                                                                                                        |
| 31  | `isInDependencySet()` MUST return true for all the chain IDs of the chains that integrate the cluster, and false otherwise.                                                         |
| 32  | It MUST not be possible to validate or execute deposit transactions as messages                                                                                                     |
| 33  | `SuperchainWETH#withdraw()` MUST revert if triggered on a chain that does not use ETH as a native token.                                                                            |
| 34  | `SuperchainWETH#deposit()` MUST Revert if triggered on a chain that does not use ETH as a native token                                                                              |
| 35  | `ETHLiquidity#burn()` MUST Revert if called on a chain that does not use ETH as a native token.                                                                                     |
| 36  | `ETHLiquidity#mint()` MUST Revert if called on a chain that does not use ETH as a native token.                                                                                     |
| 37  | calls to `relayERC20` always succeed as long as the sender and cross-domain caller are valid.                                                                                       |
| 38  | The `SharedLockbox` MUST NOT trigger a new deposit transaction when unlocking ETH from the `OptimismPortal`                                                                         |
| 39  | No Ether MUST flow out of from the `Sharedlockbox` contract when in a paused state                                                                                                  |
| 40  | The `SuperchainTokenBrdige#sendERC20()` function MUST exclusively use the `L2toL2CrossDomainMessenger` for messaging.                                                               |
| 41  | The `SuperchainTokenBridge#relayERC20()` function MUST only process messages originating from the `L2toL2CrossDomainMessenger`                                                      |
| 42  | Once `SuperchainConfig#addDependency` is successfully called, the chain MUST be added to the dependency set and the `OptimismPortal` of it set as authorized on the `SharedLockbox` |

---
