# Interop Advanced Testing Campaign Overview

This campaign involves deploying the following contracts:

### Architecture

**L1 Contracts**

- SuperchainConfigInterop
- SharedLockbox
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
- Actors

---

### Overview

We deployed contracts within the constructor but initialized them using an `initialize()` modifier present in every test and handler. This approach was necessary because interacting with contracts directly in the constructor caused Medusa to crash.

In the constructor, we managed the deployment of both proxy and non-proxy contracts. For proxies, we deployed `src/universal/Proxy.sol`, setting `ProxyAdmin` as the owner and the target contract as the implementation. To avoid using the `prank` cheatcode—which can lead to issues in Medusa—we deployed `ProxyAdmin` as another actor.

In `_initializeProxies()`, we called `initialize()` on all proxies requiring initialization.

The `initialize()` modifier handled contract initialization and performed a `_setupSanityCheck()` to ensure the setup was correct.

---

### Migration Process

For the `SharedLockbox` properties, we managed two distinct states:

- Before enabling the Interop feature on L1
- After enabling the Interop feature on L1

We provided a `handler_migrateAndAddL1Dependency()` function, allowing the fuzzer to migrate the system across different states. This function migrated `SuperchainConfig` to `SuperchainConfigInterop`, `OptimismPortal` to `OptimismPortalInterop`, and called `addDependency()` to complete the migration process, including assertions to confirm success.

```mermaid
sequenceDiagram
    participant Handler
    participant ProxyAdmin
    participant SuperchainConfigProxy
    participant OptimismPortalProxy
    participant DEPLOYER_8_15

    %% Update SuperchainConfig to StorageSetter and reset `initialize` flag
    Handler->>+ProxyAdmin: upgrade(SuperchainConfigProxy, new StorageSetter())
    ProxyAdmin->>SuperchainConfigProxy: upgradeTo(StorageSetter)
    Handler->>SuperchainConfigProxy: reset `initialize` flag

    %% upgrade SuperchainConfigProxy to use SuperchainConfigInterop as implementation
    Handler->>DEPLOYER_8_15: deploySuperchainConfigInterop()
    DEPLOYER_8_15-->>Handler: superchainConfigInteropImplementation
    Handler->>+ProxyAdmin: upgrade(SuperchainConfigProxy, superchainConfigInteropImplementation)
    ProxyAdmin->>SuperchainConfigProxy: upgradeTo(superchainConfigInteropImplementation)

    %% Initialize SuperchainConfigInterop
    Handler->>SuperchainConfigProxy: initialize()


    %% Update OptimismPortal to StorageSetter and reset `initialize` flag
    Handler->>+ProxyAdmin: upgrade(OptimismPortalProxy, new StorageSetter())
    ProxyAdmin->>OptimismPortalProxy: upgradeTo(StorageSetter)
    Handler->>OptimismPortalProxy: reset `initialize` flag

    %% upgrade OptimismPortalProxy to use OptimismPortalInterop as implementaiton
    Handler->>DEPLOYER_8_15: deployOptimismPortalInterop()
    DEPLOYER_8_15-->>Handler: optimismPortalInteropImplementation
    Handler->>+ProxyAdmin: upgradeAndCall(OptimismPortalProxy, optimismPortalInteropImplementation, initializeCall)
    ProxyAdmin->>OptimismPortalProxy: upgradeToAndCall(optimismPortalInteropImplementation, initializeCall)

    Handler->>Handler: Set _ghost_isMigrated = true
```

Since the sequencer was outside the scope of this campaign, we didn't focus on sharing a single state between L1 and L2. This allowed us to utilize a broader range of fuzzing values, helping identify complex edge cases.

We excluded function signatures that were broken in the `ToB/properties` dependency used to ensure ERC20 compliance. All breaking tests were reported.

---

**Additional Notes**

- To avoid using the `prank` cheatcode, we deployed an actor to proxy necessary calls from specific addresses.
- Although portal mocks don't appear covered in the coverage report, we manually verified their coverage.
