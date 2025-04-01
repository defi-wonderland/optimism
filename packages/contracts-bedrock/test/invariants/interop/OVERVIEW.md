# Interop Advanced Testing Campaign Overview

This campaign involves deploying the following contracts:

### Architecture

**Testing Contracts**

- Setup: Contains the setup of the test.
- Handler: Contains the handlers of the test.
- FuzzTest: Where the properties are tested.
- SuperchainERC20ForToBProperties: Tests the `SuperchainERC20` ERC20 compliance using the ToB properties depdency. It is used as the `SuperchainERC20` implementation on the campaign.
- SuperchainWETHForToBProperties: Tests the `SuperchainWETH` ERC20 compliance using the ToB properties depdency. Only used for this specific case. On the rest of the campaign, the `SuperchainWETH` implementation is not modify to test the other properties.

**L1 Contracts**

- SuperchainConfig
- ETHLockbox
- SystemConfig
- OptimismPortal

**L2 Contracts (Predeploys)**

- ETHLiquidity
- L1BlockInterop
- CrossL2Inbox
- L2ToL2CrossDomainMessenger
- SuperchainTokenBridge
- L2ToL1MessagePasser
- SuperchainWETH
- SuperchainERC20

**Additional Infrastructure Contracts**

- ProxyAdmin
- ProxyAdmin Owner
- Actors
- Deployer_8_15\*
- Deployer_8_25\*
- WeirdTarget \*\*

\*The deployers are used to deploy contracts having dependencies with different compiler versions -- 0.8.15 and 0.8.25.
In this way, both contracts versions are compatible with each other.
\*\*The `WeirdTarget` is a target of a withdrawal transaction that tries to bypass safety checks on the system and tries to perform malicious or unexpected actions. It is used on the unguided test inside the `UnguidedCalls` contract.

---

### Overview

We deployed contracts within the constructor but initialized them using an `initialize()` modifier present in every test and handler. This approach was necessary because interacting with contracts directly in the constructor caused Medusa to crash. The same is true for the contracts deployed per chain that are then being used on the `handler_addFreshChain` and `handler_addExistingChain` handlers.

In the constructor, we managed the deployment of both proxy and non-proxy contracts. For proxies, we deployed `src/universal/Proxy.sol`, setting `ProxyAdmin` as the owner and the target contract as the implementation. To avoid using the `prank` cheatcode—which can lead to issues in Medusa—we deployed `ProxyAdmin` as another actor.

In `_initializeProxies()`, we called `initialize()` on all proxies requiring initialization.

The `initialize()` modifier handled contract initialization and performed a `_setupSanityCheck()` to ensure the setup was correct.

---

**Additional Notes**

- `prank` usage fails when sending value on the next call - that's why we had to maintain the actors system for those cases.
- Although portal mocks don't appear covered in the coverage report, we manually verified their coverage.
- A refactor on the organization of the tests was attempted, but it unexpectedly failed with `[vm error ('stack underflow (0 <=> 1)')]` error, for which the unique solution was to keep the storage layout of the contract as is to avoid the Medusa crash.
