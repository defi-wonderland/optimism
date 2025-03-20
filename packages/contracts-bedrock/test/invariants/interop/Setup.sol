// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Testing
import { vm } from "./utils/VM.sol";
import { IDeployer815 } from "./interfaces/IDeployer815.sol";
import { IDeployer825 } from "./interfaces/IDeployer825.sol";
import { PropertiesAsserts } from "./utils/PropertiesAsserts.sol";
import { Utils } from "./utils/Utils.sol";

// Interfaces 0.8.15
import { IL1Block } from "interfaces/L2/IL1Block.sol";
import { IETHLiquidity } from "interfaces/L2/IETHLiquidity.sol";
import { IOptimismPortal2 as IOptimismPortal } from "interfaces/L1/IOptimismPortal2.sol";
import { IETHLockbox } from "interfaces/L1/IETHLockbox.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { ISuperchainWETH } from "interfaces/L2/ISuperchainWETH.sol";
import { IAnchorStateRegistry } from "interfaces/dispute/IAnchorStateRegistry.sol";

// Interfaces 0.8.25
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { ISuperToken } from "./interfaces/ISuperToken.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";

// Libraries and Constants
import { GameType, Proposal, Hash } from "src/dispute/lib/Types.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { IResourceMetering } from "interfaces/L1/IResourceMetering.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";
import { Constants } from "src/libraries/Constants.sol";
import { HandlerActors, Actors, ICrossL2InboxWithSlotWarming } from "./helpers/Actors.sol";

contract Setup is PropertiesAsserts, HandlerActors {
    using Utils for *;

    // Constants
    uint256 public constant INITIAL_PORTAL_ETHER = 700_000 ether;
    uint256 public constant DESTINATION_CHAIN_ID = 130;

    IDeployer815 public constant DEPLOYER_8_15 = IDeployer815(0x4200000000000000000000000000000000000815);
    IDeployer825 public constant DEPLOYER_8_25 = IDeployer825(0x4200000000000000000000000000000000000825);

    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // Solidity 0.8.15 Contracts
    IL1Block public immutable L1_BLOCK = IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES);
    IETHLiquidity public immutable ETH_LIQUIDITY = IETHLiquidity(Predeploys.ETH_LIQUIDITY);
    ISuperchainWETH public immutable SUPER_WETH = ISuperchainWETH(payable(Predeploys.SUPERCHAIN_WETH));
    IETHLockbox public immutable ETH_LOCKBOX;
    ISuperchainConfig public immutable SUPERCHAIN_CONFIG;
    IOptimismPortal public immutable PORTAL;
    ISystemConfig public immutable SYSTEM_CONFIG;
    IAnchorStateRegistry public immutable ANCHOR_STATE_REGISTRY;

    // Soldity 0.8.25 Contracts
    ICrossL2InboxWithSlotWarming public immutable CROSS_L2_INBOX =
        ICrossL2InboxWithSlotWarming(Predeploys.CROSS_L2_INBOX);
    IL2ToL2CrossDomainMessenger public immutable L2_TO_L2_MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    ISuperchainTokenBridge public immutable SUPERCHAIN_TOKEN_BRIDGE =
        ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE);
    ISuperToken public immutable SUPER_TOKEN;

    // Portal Immutables - Values not important for the scope of this testing campaign
    uint256 public immutable PROOF_MATURITY_DELAY_SECONDS = 1 weeks;
    uint256 public immutable DISPUTE_GAME_FINALITY_DELAY_SECONDS = 3.5 days;

    // System addresses
    address public immutable GUARDIAN = vm.addr(uint256(keccak256("Guardian")));
    Actors public immutable PROXY_OWNER = Actors(payable(vm.addr(uint256(keccak256("ProxyOwner")))));
    ProxyAdmin public immutable PROXY_ADMIN;
    // Internals
    address internal _DISPUTE_GAME_FACTORY = vm.addr(uint256(keccak256("DisputeGameFactory")));
    bytes internal _proxyCode;

    constructor() {
        // Etch the proxy owner to be an actor
        bytes memory actorCode = address(new Actors()).code;
        vm.etch(address(PROXY_OWNER), actorCode);

        // Deploy ProxyAdmin
        PROXY_ADMIN = new ProxyAdmin(address(PROXY_OWNER));

        // Deploy Proxy
        _proxyCode = DEPLOYER_8_15.deployProxy(address(PROXY_ADMIN)).code;

        // Deploy ETHLiquidity
        _setCode(
            Predeploys.ETH_LIQUIDITY,
            DEPLOYER_8_15.deployETHLiquidity(),
            !Predeploys.notProxied(Predeploys.ETH_LIQUIDITY)
        );
        // Give the initial ether balance to ETHLiquidity
        vm.deal(Predeploys.ETH_LIQUIDITY, type(uint248).max);
        _ghost_isL2Contract[Predeploys.ETH_LIQUIDITY] = true;

        // Deploy L1BlockInterop
        _setCode(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            DEPLOYER_8_15.deployL1Block(),
            !Predeploys.notProxied(Predeploys.L1_BLOCK_ATTRIBUTES)
        );
        _ghost_isL2Contract[Predeploys.L1_BLOCK_ATTRIBUTES] = true;

        // Deploy CrossL2Inbox
        _setCode(
            Predeploys.CROSS_L2_INBOX,
            DEPLOYER_8_25.deployCrossL2Inbox(),
            !Predeploys.notProxied(Predeploys.CROSS_L2_INBOX)
        );
        _ghost_isL2Contract[Predeploys.CROSS_L2_INBOX] = true;

        // Deploy L2ToL2CrossDomainMessenger
        _setCode(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            DEPLOYER_8_25.deployL2ToL2CrossDomainMessenger(),
            !Predeploys.notProxied(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER)
        );
        _ghost_isL2Contract[Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER] = true;

        // Deploy SuperchainTokenBridge
        _setCode(
            Predeploys.SUPERCHAIN_TOKEN_BRIDGE,
            DEPLOYER_8_25.deploySuperchainTokenBridge(),
            !Predeploys.notProxied(Predeploys.SUPERCHAIN_TOKEN_BRIDGE)
        );
        _ghost_isL2Contract[Predeploys.SUPERCHAIN_TOKEN_BRIDGE] = true;

        // Deploy L2ToL1MessagePasser
        _setCode(
            Predeploys.L2_TO_L1_MESSAGE_PASSER,
            DEPLOYER_8_15.deployL2ToL1MessagePasser(),
            !Predeploys.notProxied(Predeploys.L2_TO_L1_MESSAGE_PASSER)
        );
        _ghost_isL2Contract[Predeploys.L2_TO_L1_MESSAGE_PASSER] = true;

        // Deploy SuperchainWETH
        _setCode(
            Predeploys.SUPERCHAIN_WETH,
            DEPLOYER_8_15.deploySuperchainWETH(),
            !Predeploys.notProxied(Predeploys.SUPERCHAIN_WETH)
        );
        _ghost_isL2Contract[Predeploys.SUPERCHAIN_WETH] = true;

        // Deploy SuperchainToken
        SUPER_TOKEN = ISuperToken(DEPLOYER_8_25.deploySuperchainERC20());
        _ghost_isL2Contract[address(SUPER_TOKEN)] = true;

        // Deploy AnchorStateRegistry
        address anchorStateRegistryAddress = vm.addr(uint256(keccak256("AnchorStateRegistry")));
        _setCode(
            anchorStateRegistryAddress,
            DEPLOYER_8_15.deployAnchorStateRegistry(DISPUTE_GAME_FINALITY_DELAY_SECONDS),
            true
        );
        ANCHOR_STATE_REGISTRY = IAnchorStateRegistry(anchorStateRegistryAddress);
        _ghost_isL1Contract[anchorStateRegistryAddress] = true;

        // Deploy SuperchainConfig
        address superchainConfigAddress = vm.addr(uint256(keccak256("SuperchainConfig")));
        _setCode(superchainConfigAddress, DEPLOYER_8_15.deploySuperchainConfig(), true);
        SUPERCHAIN_CONFIG = ISuperchainConfig(superchainConfigAddress);
        _ghost_isL1Contract[superchainConfigAddress] = true;

        // Deploy ETHLockbox
        address ethLockboxAddress = vm.addr(uint256(keccak256("ETHLockbox")));
        _setCode(ethLockboxAddress, DEPLOYER_8_25.deployETHLockbox(), true);
        ETH_LOCKBOX = IETHLockbox(ethLockboxAddress);
        _ghost_isL1Contract[ethLockboxAddress] = true;

        // Deploy SystemConfig
        address systemConfigAddress = vm.addr(uint256(keccak256("SystemConfig")));
        _setCode(systemConfigAddress, DEPLOYER_8_15.deploySystemConfig(), true);
        SYSTEM_CONFIG = ISystemConfig(systemConfigAddress);
        _ghost_isL1Contract[systemConfigAddress] = true;

        // Deal the initial ether to the portal address
        address optimismPortalAddress = vm.addr(uint256(keccak256("OptimismPortal")));
        vm.deal(optimismPortalAddress, INITIAL_PORTAL_ETHER);

        // Deploy OptimismPortal
        _setCode(optimismPortalAddress, DEPLOYER_8_15.deployOptimismPortal(PROOF_MATURITY_DELAY_SECONDS), true);
        PORTAL = IOptimismPortal(payable(optimismPortalAddress));
        _ghost_isL1Contract[optimismPortalAddress] = true;

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
            vm.store(_target, _ADMIN_SLOT, bytes32(uint256(uint160(address(PROXY_ADMIN)))));

            assert(address(uint160(uint256(vm.load(_target, _IMPLEMENTATION_SLOT)))) == _implementation);
            assert(address(uint160(uint256(vm.load(_target, _ADMIN_SLOT)))) == address(PROXY_ADMIN));
        } else {
            vm.etch(_target, _implementation.code);
        }
    }

    function _initializeProxies() internal {
        // Initialize SuperchainConfig
        SUPERCHAIN_CONFIG.initialize(GUARDIAN, false);

        // Initialize SystemConfig
        ISystemConfig.Addresses memory addresses = ISystemConfig.Addresses({
            l1CrossDomainMessenger: address(0), // Setting 0 to those values that are not needed for this campaign
            l1ERC721Bridge: address(0),
            l1StandardBridge: address(0),
            optimismPortal: address(PORTAL),
            optimismMintableERC20Factory: address(0)
        });
        IResourceMetering.ResourceConfig memory config = Constants.DEFAULT_RESOURCE_CONFIG();
        SYSTEM_CONFIG.initialize(
            address(PROXY_ADMIN),
            0,
            0,
            0x0000000000000000000000006887246668a3b87f54deb3b94ba47a6f63f32985,
            60000000,
            0xAAAA45d9549EDA09E70937013520214382Ffc4A2,
            config,
            0xFF00000000000000000000000000000000000010,
            addresses,
            DESTINATION_CHAIN_ID
        );

        // Initialize AnchorStateRegistry
        ANCHOR_STATE_REGISTRY.initialize(
            ISuperchainConfig(address(SUPERCHAIN_CONFIG)),
            IDisputeGameFactory(_DISPUTE_GAME_FACTORY),
            Proposal(Hash.wrap(bytes32(0)), 0),
            GameType.wrap(0)
        );

        // Initialize Portal
        PORTAL.initialize(
            ISystemConfig(address(SYSTEM_CONFIG)),
            ISuperchainConfig(address(SUPERCHAIN_CONFIG)),
            IAnchorStateRegistry(address(ANCHOR_STATE_REGISTRY)),
            IETHLockbox(address(ETH_LOCKBOX))
        );

        // Initialize ETHLockbox
        IOptimismPortal[] memory portals = new IOptimismPortal[](1);
        portals[0] = PORTAL;
        ETH_LOCKBOX.initialize(SUPERCHAIN_CONFIG, portals);

        // Migrate liquidity from portal to ETHLockbox
        PROXY_OWNER.directCall(address(PORTAL), 0, abi.encodeCall(PORTAL.migrateLiquidity, ()));
    }

    function _addActors() internal {
        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
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

    /// Check setup proper deployment and initialization of the contracts
    function _setupSanityCheck() internal view {
        /* Contracts with some storage intialization on setup */
        // Portal
        assert(PORTAL.proofMaturityDelaySeconds() == PROOF_MATURITY_DELAY_SECONDS);
        assert(PORTAL.disputeGameFinalityDelaySeconds() == DISPUTE_GAME_FINALITY_DELAY_SECONDS);
        assert(address(PORTAL.superchainConfig()) == address(SUPERCHAIN_CONFIG));
        assert(address(PORTAL.systemConfig()) == address(SYSTEM_CONFIG));
        assert(address(PORTAL.disputeGameFactory()) == _DISPUTE_GAME_FACTORY);
        assert(address(PORTAL.anchorStateRegistry()) == address(ANCHOR_STATE_REGISTRY));
        assert(address(PORTAL.ethLockbox()) == address(ETH_LOCKBOX));
        assert(PORTAL.superRootsActive() == false);
        assert(address(PORTAL).balance == 0);

        // ETHLockbox
        assert(address(ETH_LOCKBOX.superchainConfig()) == address(SUPERCHAIN_CONFIG));
        assert(ETH_LOCKBOX.authorizedPortals(PORTAL) == true);
        assert(address(ETH_LOCKBOX).balance == INITIAL_PORTAL_ETHER);

        // Superchain Config
        assert(SUPERCHAIN_CONFIG.guardian() == GUARDIAN);
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
        assert(SYSTEM_CONFIG.disputeGameFactory() == _DISPUTE_GAME_FACTORY);
        assert(SYSTEM_CONFIG.optimismPortal() == address(PORTAL));
        bytes memory resourceConfigA = abi.encode(SYSTEM_CONFIG.resourceConfig());
        bytes memory defaultResourceConfig = abi.encode(Constants.DEFAULT_RESOURCE_CONFIG());
        assert(resourceConfigA.hashBytes() == defaultResourceConfig.hashBytes());

        // AnchorStateRegistry
        assert(ANCHOR_STATE_REGISTRY.disputeGameFinalityDelaySeconds() == DISPUTE_GAME_FINALITY_DELAY_SECONDS);
        assert(ANCHOR_STATE_REGISTRY.superchainConfig() == SUPERCHAIN_CONFIG);
        assert(address(ANCHOR_STATE_REGISTRY.disputeGameFactory()) == _DISPUTE_GAME_FACTORY);

        // SuperchainERC20
        string memory tokenName = "Super Token";
        string memory tokenSymbol = "SUP";
        assert(SUPER_TOKEN.name().hashString() == tokenName.hashString());
        assert(SUPER_TOKEN.symbol().hashString() == tokenSymbol.hashString());

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

    /// @dev Check if a contract is a L1 contract - Useful to don't mix up Ether balances state between L1 and L2
    function _isL1Contract(address _contract) internal view returns (bool) {
        return _ghost_isL1Contract[_contract];
    }

    /// @dev Check if a contract is a L2 contract - Useful to don't mix up Ether balances state between L1 and L2
    function _isL2Contract(address _contract) internal view returns (bool) {
        return _ghost_isL2Contract[_contract];
    }
}
