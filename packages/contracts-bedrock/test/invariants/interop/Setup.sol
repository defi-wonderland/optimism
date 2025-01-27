// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Testing
import { vm } from "./utils/VM.sol";
import { IDeployer815 } from "./interfaces/IDeployer815.sol";
import { IDeployer825 } from "./interfaces/IDeployer825.sol";
import { PropertiesAsserts } from "./utils/PropertiesAsserts.sol";
import { Utils } from "./utils/Utils.sol";

// Interfaces 0.8.15
import { IETHLiquidity } from "interfaces/L2/IETHLiquidity.sol";
import { IL1BlockInterop } from "interfaces/L2/IL1BlockInterop.sol";
import { IOptimismPortalInterop } from "interfaces/L1/IOptimismPortalInterop.sol";
import { ISharedLockbox } from "interfaces/L1/ISharedLockbox.sol";
import { ISuperchainConfigInterop } from "interfaces/L1/ISuperchainConfigInterop.sol";
import { ISuperchainWETH } from "interfaces/L2/ISuperchainWETH.sol";

// Interfaces 0.8.25
import { ICrossL2Inbox } from "interfaces/L2/ICrossL2Inbox.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { ISuperToken } from "./interfaces/ISuperToken.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";

// Libraries and Constants
import { GameType } from "src/dispute/lib/Types.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { IResourceMetering } from "interfaces/L1/IResourceMetering.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";
import { Constants } from "src/libraries/Constants.sol";
import { HandlerActors, Actors } from "./helpers/Actors.sol";
import { IDependencyManager } from "interfaces/L2/IDependencyManager.sol";

contract Setup is PropertiesAsserts, HandlerActors {
    using Utils for *;

    // Constants
    uint256 public constant INITIAL_PORTAL_ETHER = 700_000 ether;
    uint256 public constant DESTINATION_CHAIN_ID = 130;

    IDeployer815 public constant DEPLOYER_8_15 = IDeployer815(0x4200000000000000000000000000000000000815);
    IDeployer825 public constant DEPLOYER_8_25 = IDeployer825(0x4200000000000000000000000000000000000825);

    address internal constant _DEPOSITOR_ACCOUNT = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // Solidity 0.8.15 Contracts
    IETHLiquidity public immutable ETH_LIQUIDITY = IETHLiquidity(Predeploys.ETH_LIQUIDITY);
    IL1BlockInterop public immutable L1_BLOCK = IL1BlockInterop(Predeploys.L1_BLOCK_ATTRIBUTES);
    ISuperchainWETH public immutable SUPER_WETH = ISuperchainWETH(payable(Predeploys.SUPERCHAIN_WETH));
    ISharedLockbox public immutable SHARED_LOCKBOX;
    ISuperchainConfigInterop public immutable SUPERCHAIN_CONFIG;
    IDependencyManager public immutable DEPENDENCY_MANAGER = IDependencyManager(Predeploys.DEPENDENCY_MANAGER);
    IOptimismPortalInterop public immutable PORTAL;
    ISystemConfig public immutable SYSTEM_CONFIG;

    // Soldity 0.8.25 Contracts
    ICrossL2Inbox public immutable CROSS_L2_INBOX = ICrossL2Inbox(Predeploys.CROSS_L2_INBOX);
    IL2ToL2CrossDomainMessenger public immutable L2_TO_L2_MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    ISuperchainTokenBridge public immutable SUPERCHAIN_TOKEN_BRIDGE =
        ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE);
    ISuperToken public immutable SUPER_TOKEN;

    // System addresses
    address public immutable guardian = vm.addr(uint256(keccak256("Guardian")));
    address public immutable proxyOwner = vm.addr(uint256(keccak256("ProxyOwner")));
    ProxyAdmin public immutable proxyAdmin;
    address public immutable clusterManager = vm.addr(uint256(keccak256("ClusterManager")));
    // Predefined addresses
    address public sharedLockboxAddress = vm.addr(uint256(keccak256("SharedLockbox")));
    address public superchainConfigAddress = vm.addr(uint256(keccak256("SuperchainConfig")));
    address public systemConfigAddress = vm.addr(uint256(keccak256("SystemConfig")));
    address public optimismPortalAddress = vm.addr(uint256(keccak256("OptimismPortal")));
    // Internals
    address internal _disputeGameFactory = vm.addr(uint256(keccak256("DisputeGameFactory")));
    bytes internal _proxyCode;

    constructor() {
        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(proxyOwner);

        // Deploy Proxy
        _proxyCode = DEPLOYER_8_15.deployProxy(address(proxyAdmin)).code;

        // Deploy ETHLiquidity
        _setCode(
            Predeploys.ETH_LIQUIDITY,
            DEPLOYER_8_15.deployETHLiquidity(),
            !Predeploys.notProxied(Predeploys.ETH_LIQUIDITY)
        );
        // Give the initial ether balance to ETHLiquidity
        vm.deal(Predeploys.ETH_LIQUIDITY, type(uint248).max);

        // Deploy L1BlockInterop
        _setCode(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            DEPLOYER_8_15.deployL1Block(),
            !Predeploys.notProxied(Predeploys.L1_BLOCK_ATTRIBUTES)
        );

        //  Deploy CrossL2Inbox
        _setCode(
            Predeploys.CROSS_L2_INBOX,
            DEPLOYER_8_25.deployCrossL2Inbox(),
            !Predeploys.notProxied(Predeploys.CROSS_L2_INBOX)
        );

        // Deploy L2ToL2CrossDomainMessenger
        _setCode(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            DEPLOYER_8_25.deployL2ToL2CrossDomainMessenger(),
            !Predeploys.notProxied(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER)
        );

        // Deploy SuperchainTokenBridge
        _setCode(
            Predeploys.SUPERCHAIN_TOKEN_BRIDGE,
            DEPLOYER_8_25.deploySuperchainTokenBridge(),
            !Predeploys.notProxied(Predeploys.SUPERCHAIN_TOKEN_BRIDGE)
        );

        // Deploy L2ToL1MessagePasser
        _setCode(
            Predeploys.L2_TO_L1_MESSAGE_PASSER,
            DEPLOYER_8_15.deployL2ToL1MessagePasser(),
            !Predeploys.notProxied(Predeploys.L2_TO_L1_MESSAGE_PASSER)
        );

        // Deploy DependencyManager
        _setCode(
            Predeploys.DEPENDENCY_MANAGER,
            DEPLOYER_8_25.deployDependencyManager(),
            !Predeploys.notProxied(Predeploys.DEPENDENCY_MANAGER)
        );

        // Deploy SuperchainWETH
        _setCode(
            Predeploys.SUPERCHAIN_WETH,
            DEPLOYER_8_15.deploySuperchainWETH(),
            !Predeploys.notProxied(Predeploys.SUPERCHAIN_WETH)
        );

        // Deploy SuperchainToken
        SUPER_TOKEN = ISuperToken(DEPLOYER_8_25.deploySuperchainERC20());

        // Deploy SuperchainConfig
        _setCode(superchainConfigAddress, DEPLOYER_8_15.deploySuperchainConfigInterop(), true);
        SUPERCHAIN_CONFIG = ISuperchainConfigInterop(superchainConfigAddress);

        // Deploy SharedLockbox
        _setCode(sharedLockboxAddress, DEPLOYER_8_25.deploySharedLockbox(), true);
        SHARED_LOCKBOX = ISharedLockbox(sharedLockboxAddress);

        // Deploy SystemConfig
        _setCode(systemConfigAddress, DEPLOYER_8_15.deploySystemConfig(), true);
        SYSTEM_CONFIG = ISystemConfig(systemConfigAddress);

        // Deal the initial ether to the portal address
        vm.deal(optimismPortalAddress, INITIAL_PORTAL_ETHER);

        // These values are not important for the scope of this testing campaign
        (uint256 proofMaturityDelaySeconds, uint256 disputeGameFinalityDelaySeconds) = (1 weeks, 3.5 days);

        // Deploy OptimismPortal
        _setCode(
            optimismPortalAddress,
            DEPLOYER_8_15.deployOptimismPortal(proofMaturityDelaySeconds, disputeGameFinalityDelaySeconds),
            true
        );
        PORTAL = IOptimismPortalInterop(payable(optimismPortalAddress));

        // Set the cluster manager as an actor
        bytes memory actorCode = address(new Actors()).code;
        vm.etch(clusterManager, actorCode);

        // Set the depositor account as an actor
        vm.etch(Constants.DEPOSITOR_ACCOUNT, actorCode);

        _addActors();
    }

    /// @dev Set the code of a contract if it is not a proxy, otherwise set the code of the proxy and upgrade it.
    function _setCode(address _target, address _implementation, bool _isProxied) internal {
        assert(_implementation.code.length > 0);

        if (_isProxied) {
            vm.etch(_target, _proxyCode);
            vm.store(_target, _IMPLEMENTATION_SLOT, bytes32(uint256(uint160(_implementation))));
            vm.store(_target, _ADMIN_SLOT, bytes32(uint256(uint160(address(proxyAdmin)))));

            assert(address(uint160(uint256(vm.load(_target, _IMPLEMENTATION_SLOT)))) == _implementation);
            assert(address(uint160(uint256(vm.load(_target, _ADMIN_SLOT)))) == address(proxyAdmin));
        } else {
            vm.etch(_target, _implementation.code);
        }
    }

    function _initializeProxies() internal {
        // Initialize SuperchainConfig
        SUPERCHAIN_CONFIG.initialize(guardian, false, clusterManager, sharedLockboxAddress);

        // Initialize SystemConfig
        ISystemConfig.Addresses memory addresses = ISystemConfig.Addresses({
            l1CrossDomainMessenger: address(0), // Setting 0 to those values that are not needed for this campaign
            l1ERC721Bridge: address(0),
            l1StandardBridge: address(0),
            disputeGameFactory: _disputeGameFactory,
            optimismPortal: optimismPortalAddress,
            optimismMintableERC20Factory: address(0)
        });
        IResourceMetering.ResourceConfig memory config = Constants.DEFAULT_RESOURCE_CONFIG();
        SYSTEM_CONFIG.initialize(
            address(proxyAdmin),
            0,
            0,
            0x0000000000000000000000006887246668a3b87f54deb3b94ba47a6f63f32985,
            60000000,
            0xAAAA45d9549EDA09E70937013520214382Ffc4A2,
            config,
            0xFF00000000000000000000000000000000000010,
            addresses
        );

        // Initialize Portal
        PORTAL.initialize(
            IDisputeGameFactory(_disputeGameFactory),
            ISystemConfig(systemConfigAddress),
            ISuperchainConfigInterop(superchainConfigAddress),
            GameType.wrap(0)
        );

        // Initialize SharedLockbox
        SHARED_LOCKBOX.initialize(superchainConfigAddress);
    }

    function _addActors() internal {
        for (uint256 i; i < numberOfActors; i++) {
            Actors _newActor = new Actors();
            _ghost_actors.push(address(_newActor));

            // Mint SUPER_TOKEN only to the first 8 actors
            if (i > 8) continue;
            uint256 amount = uint256(keccak256(abi.encode(address(_newActor))));
            // Avoid minting too much on the setup
            amount = clampLte(amount, type(uint128).max);
            SUPER_TOKEN.mint(address(_newActor), amount);
        }
    }

    /// @dev Add destination chain on the L2 DependencySet, to enable L2 to L2 interoperability between this and the
    /// destination chain
    function _addChainOnDependencyManager() internal {
        // Add destination chain as dependency of origin chain on the L2 dependency manager, using the depositor account
        (bool success,) = Actors(payable(Constants.DEPOSITOR_ACCOUNT)).directCall(
            Predeploys.DEPENDENCY_MANAGER,
            0,
            abi.encodeCall(
                DEPENDENCY_MANAGER.addDependency, (superchainConfigAddress, DESTINATION_CHAIN_ID, systemConfigAddress)
            )
        );

        assert(success);
    }

    /// Check setup proper deployment and initialization of the contracts
    function _setupSanityCheck() internal {
        /* Contracts with some storage intialization on setup */
        // Portal
        assert(PORTAL.proofMaturityDelaySeconds() == 1 weeks);
        assert(PORTAL.disputeGameFinalityDelaySeconds() == 3.5 days);
        assert(address(PORTAL.superchainConfig()) == superchainConfigAddress);
        assert(address(PORTAL.systemConfig()) == systemConfigAddress);
        assert(address(PORTAL.disputeGameFactory()) == _disputeGameFactory);

        // Shared Lockbox
        assert(address(SHARED_LOCKBOX.superchainConfig()) == superchainConfigAddress);

        // Superchain Config
        assert(address(SUPERCHAIN_CONFIG.sharedLockbox()) == sharedLockboxAddress);
        assert(SUPERCHAIN_CONFIG.guardian() == guardian);
        assert(SUPERCHAIN_CONFIG.paused() == false);

        // System Config
        uint256 systemConfigAStartBlock = SYSTEM_CONFIG.startBlock();
        assert(systemConfigAStartBlock > 0 && systemConfigAStartBlock <= block.number);
        assert(SYSTEM_CONFIG.basefeeScalar() == 0);
        assert(SYSTEM_CONFIG.blobbasefeeScalar() == 0);
        assert(SYSTEM_CONFIG.batcherHash() == 0x0000000000000000000000006887246668a3b87f54deb3b94ba47a6f63f32985);
        assert(SYSTEM_CONFIG.gasLimit() == 60000000);
        assert(SYSTEM_CONFIG.unsafeBlockSigner() == 0xAAAA45d9549EDA09E70937013520214382Ffc4A2);
        assert(SYSTEM_CONFIG.batchInbox() == 0xFF00000000000000000000000000000000000010);
        assert(SYSTEM_CONFIG.disputeGameFactory() == _disputeGameFactory);
        assert(SYSTEM_CONFIG.optimismPortal() == address(PORTAL));
        bytes memory resourceConfigA = abi.encode(SYSTEM_CONFIG.resourceConfig());
        bytes memory defaultResourceConfig = abi.encode(Constants.DEFAULT_RESOURCE_CONFIG());
        assert(resourceConfigA.hashBytes() == defaultResourceConfig.hashBytes());

        // SuperchainERC20
        string memory tokenName = "Super Token";
        string memory tokenSymbol = "SUP";
        assert(SUPER_TOKEN.name().hashString() == tokenName.hashString());
        assert(SUPER_TOKEN.symbol().hashString() == tokenSymbol.hashString());

        // Dependency Manager
        assert(DEPENDENCY_MANAGER.dependencySetSize() == 1);
        assert(DEPENDENCY_MANAGER.isInDependencySet(DESTINATION_CHAIN_ID));
        assert(DEPENDENCY_MANAGER.isInDependencySet(block.chainid));

        /* Contracts without any storage intialization on setup */
        // Check that it has a version, not checking which one to make the test more future proof
        string memory emptyString = "";
        bytes32 emptyStringHash = emptyString.hashString();
        assert(ETH_LIQUIDITY.version().hashString() != emptyStringHash);
        assert(L1_BLOCK.version().hashString() != emptyStringHash);
        assert(SUPER_WETH.version().hashString() != emptyStringHash);
        assert(L2_TO_L2_MESSENGER.version().hashString() != emptyStringHash);
        assert(SUPERCHAIN_TOKEN_BRIDGE.version().hashString() != emptyStringHash);
    }
}
