# Interop Advanced Testing Campaign

This campaign aims to develop a testing suite that fuzzes over the interop invariants introduced or modified by the Wonderland team. The main focus is on testing stateful properties and dismissing unit tests that are already covered by the existing test suite.

## Milestones

- SuperchainERC20: Mainly composed of invariants related to `SuperchainERC20` and `SuperchainWETH` contracts, as well as the `SuperchainTokenBridge` and other contracts that interact with them.
- SharedLockbox: Mainly composed of invariants related to the `SharedLockbox` and `OptimismPortal` contracts, as well as other contracts that interact with them.

# Properties

**Legend:**

- `[ ]`: property not yet tested
- `[X]`: tested/proven property
- `[~]`: partially tested/proven property
- `:(`: property won't be tested due to some limitation

| Id  | Milestone       | Description                                                                                                                                                                                                                                                                                      | Tested |
| --- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| 1   | SuperchainERC20 | Bridging `SuperchainERC20s` from the origin to the destination chain decreases the token's `totalSupply` and the sender's balance on the origin chain by exactly the input amount                                                                                                                | [X]    |
| 2   | SuperchainERC20 | Relaying `SuperchainERC20`s sent from the origin chain increases the token's `totalSupply` and the target's balance on the destination chain by exactly the input amount                                                                                                                         | [X]    |
| 3   | SuperchainERC20 | Bridging `SuperchainWETH` through `SuperchainTokenBridge` from origin to destination increases the `ETHLiquidity` Ether balance, and decreases the sender's `SuperchainWETH` balance on origin as well as `SuperchainWETH` total supply and Ether balance by exactly the input amount.           | [X]    |
| 4   | SuperchainERC20 | Relaying `SuperchainWETH` sent from origin through `SuperchainTokenBridge` on destination decreases the `ETHLiquidity` Ether balance, and increases the target's `SuperchainWETH` balance on destination as well as `SuperchainWETH` total supply and Ether balance by exactly the input amount. | [X]    |
| 5   | SuperchainERC20 | The `SuperchainERC20` token MUST be compliant with the ERC20 standard                                                                                                                                                                                                                            | [X]    |
| 6   | SuperchainERC20 | `ETHLiquidity#mint()` MUST never be callable such that balance would decrease below `0`                                                                                                                                                                                                          | [X]    |
| 7   | SuperchainERC20 | `ETHLiquidity#burn()` MUST never be callable such that balance would increase beyond `type(uint256).max`                                                                                                                                                                                         | [X]    |
| 8   | SuperchainERC20 | The total sum of `SuperchainWETH` user balances MUST be equal to the total supply.                                                                                                                                                                                                               | [X]    |
| 9   | SuperchainERC20 | The ERC20 logic of `SuperchainWETH` must be compliant with the ERC20 standard                                                                                                                                                                                                                    | [X]    |
| 10  | SharedLockbox   | Before migration, deposits with value greater than zero MUST keep the ETH in the `OptimismPortal`                                                                                                                                                                                                | [X]    |
| 11  | SharedLockbox   | Before migration, withdrawals MUST use the `OptimismPortal`'s own ETH balance if the amount being withdrawn is greater than zero                                                                                                                                                                 | [X]    |
| 12  | SharedLockbox   | After migration, the `OptimismPortal` MUST lock the ETH amount on the `SharedLockbox` when on a deposit transaction with value greater than zero, without holding any ETH balance from the depositing users                                                                                      | [X]    |
| 13  | SharedLockbox   | After migration, the `OptimismPortal` MUST unlock the ETH amount being withdrawn from the `SharedLockbox` if it is greater than zero                                                                                                                                                             | [X]    |
| 14  | SharedLockbox   | Once migrated, the total withdrawable ETH amount present on all the dependency set's chains MUST NEVER be more than the amount held by the `SharedLockbox` of the cluster                                                                                                                        | [~]    |
| 15  | SharedLockbox   | The `CLUSTER_MANAGER` role MUST only be modifiable during initialization                                                                                                                                                                                                                         | [X]    |

---

**Note on Property 14:** Property marked as partially tested due to testing environment constraints. Full verification would require L1-L2 integration testing including sequencer and proof verification components, which exceeds the scope of this Interop-contracts focused campaign. The testing framework presents a fundamental limitation in its ability to switch between different chain environments during test execution. Additionally, L2 predeploys sharing the same address prevents accurate multi-L2 simulation. Attempting to implement this test on the campaign would require introducing numerous trust assumptions, mocks, and clamped values, resulting in poor coverage quality and unreliable test scenarios. Property is considered partially tested as all other SharedLockbox invariants are thoroughly covered in the test suite, with only this cross-chain balance verification remaining limited.
Given the complexity of setting up the testing environment to cover this property, we recommend creating a dedicated monitoring script in a production environment to check the invariant is never broken.

<br><br>

# Unit Tested Properties

The following properties are considered to be easily testable by **Unit tests**, so they **won't be included in the fuzzing campaign**. Nonetheless, they will be reviewed and tested as necessary to ensure comprehensive coverage:

| Id  | Description                                                                                                                                         |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| 16  | Adding an `OptimismPortal` during a paused state MUST revert.                                                                                       |
| 17  | Only `authorizedPortals` MUST be able to call `lockETH` and `unlockETH`.                                                                            |
| 18  | The allowance of `Permit2` should always be the maximum one on `SuperchainWETH`.                                                                    |
| 19  | `isDeposit` MUST only be callable by the `CrossL2Inbox`.                                                                                            |
| 20  | `depositsComplete` and `setConfig` MUST be only callable by the `DEPOSITOR_ACCOUNT`.                                                                |
| 21  | `crosschainBurn()` MUST be called only by the `SuperchainTokenBridge`.                                                                              |
| 22  | `crosschainMint()` MUST be called only by the `SuperchainTokenBridge`.                                                                              |
| 23  | `SuperchainTokenBridge#sendERC20()` function MUST exclusively send a message to the same address on the target chain.                               |
| 24  | `SuperchainTokenBridge#relayERC20()` function should only process messages originating from the same address.                                       |
| 25  | `ETHLiquidity` initial balance MUST be set to `type(uint248).max`.                                                                                  |
| 26  | `ETHLiquidity#mint()` MUST be called only by `SuperchainWETH`.                                                                                      |
| 27  | `ETHLiquidity#mint()` MUST transfer requested ETH value to the sending address.                                                                     |
| 28  | `ETHLiquidity#burn()` MUST be called only by `SuperchainWETH`.                                                                                      |
| 29  | `ETHLiquidity#burn()` MUST accept ETH value.                                                                                                        |
| 30  | `isInDependencySet()` MUST return `true` for all the chain IDs of the chains that integrate the cluster, and `false` otherwise.                     |
| 31  | It MUST not be possible to validate or execute deposit transactions as messages.                                                                    |
| 32  | `SuperchainWETH#withdraw()` MUST revert if triggered on a chain that does not use ETH as a native token.                                            |
| 33  | `SuperchainWETH#deposit()` MUST revert if triggered on a chain that does not use ETH as a native token.                                             |
| 34  | Message to the same chain MUST be disallowed.                                                                                                       |
| 35  | Only the `SuperchainConfig` MUST be able to authorize an `OptimismPortal`.                                                                          |
| 36  | Calls to `relayERC20` always succeed as long as the sender and cross-domain caller are valid.                                                       |
| 37  | The `SharedLockbox` MUST NOT trigger a new deposit transaction when unlocking ETH from the `OptimismPortal`.                                        |
| 38  | No Ether MUST flow out of the `SharedLockbox` contract when in a paused state.                                                                      |
| 39  | The `SuperchainTokenBridge#sendERC20()` function MUST exclusively use the `L2toL2CrossDomainMessenger` for messaging.                               |
| 40  | The `SuperchainTokenBridge#relayERC20()` function MUST only process messages originating from the `L2toL2CrossDomainMessenger`.                     |
| 41  | The `ETHLiquidity#mint` call MUST always revert when the caller is not the `SuperchainWETH` contract.                                               |
| 42  | The `ETHLiquidity#burn` call MUST always revert when the caller is not the `SuperchainWETH` contract.                                               |
| 43  | Once migrated, the `OptimismPortal` MUST NOT allow withdrawals if the target is the `SharedLockbox` address.                                        |
| 44  | The `OptimismPortal` MUST only migrate liquidity once.                                                                                              |
| 45  | A chain cannot be added more than once.                                                                                                             |
| 46  | The dependency set cannot exceed 255 entries.                                                                                                       |
| 47  | If a dependency is not added through a withdrawal transaction on `SuperchainConfig`, the sender MUST be the `CLUSTER_MANAGER` address.              |
| 48  | A chain CANNOT be added to the `SuperchainConfig` dependency set if it has an invalid `SuperchainConfig` configuration set in its `OptimismPortal`. |
| 49  | When a chain is added to the `SuperchainConfig` dependency set, its `OptimismPortal` MUST be authorized in the `SharedLockbox`.                     |
| 50  | When a chain is added to the `SuperchainConfig` dependency set, its `OptimismPortal` ETH liquidity MUST be migrated to the `SharedLockbox`.         |

---
