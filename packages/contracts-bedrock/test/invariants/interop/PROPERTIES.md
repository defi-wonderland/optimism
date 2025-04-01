# Interop Advanced Testing Campaign

This campaign aims to develop a testing suite that fuzzes over the interop invariants introduced or modified by the Wonderland team. The main focus is on testing stateful properties and dismissing unit tests that are already covered by the existing test suite.

## Milestones

- **SuperchainERC20:** Mainly composed of invariants related to `SuperchainERC20` and `SuperchainWETH` contracts, as well as the `SuperchainTokenBridge` and other contracts that interact with them.
- **ETHLockbox:** Mainly composed of invariants related to the `ETHLockbox` and `OptimismPortal` contracts, as well as other contracts that interact with them.
- **DoS Interop:** Fixes on the offchain and on chain interaction to make the system DoS-proof, being txs access list the key component of the solution. Note that any invariant of this feature is in the scope of the testing campaign, but is covered with unit tests.

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
| 7   | SuperchainERC20 | The total sum of `SuperchainWETH` user balances MUST be equal to the total supply.                                                                                                                                                                                                               | [X]    |
| 8   | SuperchainERC20 | The ERC20 logic of `SuperchainWETH` must be compliant with the ERC20 standard                                                                                                                                                                                                                    | [X]    |
| 9   | ETHLockbox      | `OptimismPortal`s MUST lock the ETH amount on the `ETHLockbox` when on a deposit transaction with value greater than zero, without holding any ETH balance from the depositing users                                                                                                             | [X]    |
| 10  | ETHLockbox      | `OptimismPortal`s MUST unlock the ETH amount being withdrawn from the `ETHLockbox` if it is greater than zero                                                                                                                                                                                    | [X]    |
| 11  | ETHLockbox      | `OptimismPortal`s `unlockETH` MUST NOT be called on a finalized withdrawal transaction context                                                                                                                                                                                                   | [X]    |
| 12  | ETHLockbox      | The total withdrawable ETH amount present on all the dependency set's chains MUST NEVER be more than the amount held by the `ETHLockbox` of the cluster                                                                                                                                          | [~]    |

---

**Notes:**

- **Property 12:** Property marked as partially tested due to testing environment constraints. Full verification would require L1-L2 integration testing including sequencer and proof verification components, which exceeds the scope of this Interop-contracts focused campaign. The testing framework presents a fundamental limitation in its ability to switch between different chain environments during test execution. Additionally, L2 predeploys sharing the same address prevents accurate multi-L2 simulation. Attempting to implement this test on the campaign would require introducing numerous trust assumptions, mocks, and clamped values, resulting in poor coverage quality and unreliable test scenarios. Property is considered partially tested as all other ETHLockbox invariants are thoroughly covered in the test suite, with only this cross-chain balance verification remaining limited.
  Given the complexity of setting up the testing environment to cover this property, we recommend creating a dedicated monitoring script in a production environment to check the invariant is never broken.
- The previously `7` property:

  **"`ETHLiquidity#burn()` MUST never be callable such that balance would increase beyond `type(uint256)`"**

  Was removed since is not true unless handled on the client, and if that happens, it won't be able to be tested on the campaign.

<br><br>

# Unit Tested Properties

The following properties are considered to be easily testable by **Unit tests**, so they **won't be included in the fuzzing campaign**. Nonetheless, they will be reviewed and tested as necessary to ensure comprehensive coverage:

| Id  | Description                                                                                                                 | Tested                             |
| --- | --------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| 16  | Only authorizedPortals MUST be able to call lockETH and unlockETH.                                                          | YES                                |
| 17  | The allowance of Permit2 should always be the maximum one on SuperchainWETH.                                                | YES                                |
| 18  | crosschainBurn() MUST be called only by the SuperchainTokenBridge.                                                          | YES                                |
| 19  | crosschainMint() MUST be called only by the SuperchainTokenBridge.                                                          | YES                                |
| 20  | SuperchainTokenBridge#sendERC20() function MUST exclusively send a message to the same address on the target chain.         | YES                                |
| 21  | SuperchainTokenBridge#relayERC20() function should only process messages originating from the same address.                 | YES                                |
| 22  | ETHLiquidity initial balance MUST be set to type(uint248).max.                                                              | YES                                |
| 23  | ETHLiquidity#mint() MUST be called only by SuperchainWETH.                                                                  | YES                                |
| 24  | ETHLiquidity#mint() MUST transfer requested ETH value to the sending address.                                               | YES                                |
| 25  | ETHLiquidity#burn() MUST be called only by SuperchainWETH.                                                                  | YES                                |
| 26  | ETHLiquidity#burn() MUST accept ETH value.                                                                                  | YES                                |
| 27  | It MUST not be possible to validate or execute deposit transactions as messages.                                            | WONT BE COVERED DUE TO LIMITATIONS |
| 28  | Messages to the same chain MUST be disallowed.                                                                              | YES                                |
| 29  | Calls to relayERC20 always succeed as long as the sender and cross-domain caller are valid.                                 | YES                                |
| 30  | The ETHLockbox MUST NOT trigger a new deposit transaction when unlocking ETH from the OptimismPortal.                       | YES                                |
| 31  | No Ether MUST flow out from the ETHLockbox contract when in a paused state.                                                 | YES                                |
| 32  | The SuperchainTokenBridge#sendERC20() function MUST exclusively use the L2toL2CrossDomainMessenger for messaging.           | YES                                |
| 33  | The SuperchainTokenBridge#relayERC20() function MUST only process messages originating from the L2toL2CrossDomainMessenger. | YES                                |
| 34  | The ETHLiquidity#mint call MUST always revert when the caller is not the SuperchainWETH contract.                           | YES                                |
| 35  | The ETHLiquidity#burn call MUST always revert when the caller is not the SuperchainWETH contract.                           | YES                                |
| 36  | Once migrated, the OptimismPortal MUST NOT allow withdrawals to target the ETHLockbox or its own address.                   | YES                                |
| 37  | `authorizePortal` MUST only be callable by the `ProxyAdmin` owner, and the input proxy’s owner MUST match it.               | YES                                |
| 38  | `authorizeLockbox` MUST only be callable by the `ProxyAdmin` owner, and the input proxy’s owner MUST match it.              | YES                                |
| 39  | `migrateLiquidity` MUST only be callable by the `ProxyAdmin` owner, and the input proxy’s owner MUST match it.              | YES                                |
| 40  | Every successful message execution that involves SuperchainERC20 MUST emit an ExecutingMessage event.                       | YES                                |
| 41  | Every successful message execution that involves SuperchainWETH MUST emit an ExecutingMessage event.                        | YES                                |

---

**Note on property 27:** Currently, deposit txs don’t have any access list so they will fail. But this functionalitiy is not on-chain enforced, so can’t be tested.

<br><br>

# Deprecated Properties

Properties marked as deprecated are no longer relevant after the redesign, although they were previously either unit-tested or fuzz-tested:

| Id  | Scope            | Description                                                                                                                                              |
| --- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Unit             | The LiquidityMigrator MUST migrate the whole OptimismPortal ETH balance to the ETHLockbox.                                                               |
| 2   | Unit             | ETHLiquidity#burn() MUST revert if called on a chain that does not use ETH as a native token.                                                            |
| 3   | Unit             | ETHLiquidity#mint() MUST revert if called on a chain that does not use ETH as a native token.                                                            |
| 4   | Unit             | Only the DependencyManager MUST be able to add a new dependency.                                                                                         |
| 5   | Unit             | The CLUSTER_MANAGER role MUST only be modifiable during initialization.                                                                                  |
| 6   | Unit             | isDeposit MUST only be callable by the CrossL2Inbox.                                                                                                     |
| 7   | Unit             | depositsComplete and setConfig MUST be only callable by the DEPOSITOR_ACCOUNT.                                                                           |
| 8   | Unit             | isInDependencySet() MUST return true for all the chain IDs of the chains that integrate the cluster, and false otherwise.                                |
| 9   | Unit             | SuperchainWETH#deposit() MUST revert if triggered on a chain that does not use ETH as a native token.                                                    |
| 10  | Unit             | SuperchainWETH#withdraw() MUST revert if triggered on a chain that does not use ETH as a native token.                                                   |
| 11  | Unit             | Only the SuperchainConfig MUST be able to authorize an OptimismPortal.                                                                                   |
| 12  | Unit             | Only the DEPOSITOR_ACCOUNT can add dependencies on the DependencyManager.                                                                                |
| 13  | Unit             | A chain cannot be added to its own dependency set.                                                                                                       |
| 14  | Unit             | A chain cannot be added more than once.                                                                                                                  |
| 15  | Unit             | The dependency set cannot exceed 255 entries.                                                                                                            |
| 16  | Unit             | A chain's own chain ID is always implicitly part of its dependency set.                                                                                  |
| 17  | Unit             | The DependencyManager MUST initiate a withdrawal transaction to the L1 SuperchainConfigInterop when adding a new dependency.                             |
| 18  | Unit             | If a dependency is not added through a withdrawal transaction on SuperchainConfig, the sender MUST be the CLUSTER_MANAGER address.                       |
| 19  | Unit             | If adding a chain through a withdrawal transaction on SuperchainConfig, only authorized portals with the DependencyManager as L2 sender MUST be allowed. |
| 20  | Unit             | A chain CANNOT be added to the SuperchainConfig dependency set if it has an invalid SuperchainConfig configuration set in its OptimismPortal.            |
| 21  | Unit             | When a chain is added on the SuperchainConfig dependency set, its OptimismPortal MUST be authorized in the ETHLockbox.                                   |
| 22  | Unit             | When a chain is added on the SuperchainConfig dependency set, its OptimismPortal ETH liquidity MUST be migrated to the ETHLockbox.                       |
| 23  | Unit             | The OptimismPortal MUST only migrate liquidity once.                                                                                                     |
| 24  | Unit             | Adding an OptimismPortal during a paused state MUST revert.                                                                                              |
| 25  | Fuzzing Campaign | Before migration, deposits with value greater than zero MUST keep the ETH in the OptimismPortal.                                                         |
| 26  | Fuzzing Campaign | Before migration, withdrawals MUST use the OptimismPortal's own ETH balance.                                                                             |

---
