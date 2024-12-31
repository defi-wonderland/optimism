// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Testing
import { IStdCheats } from "./interfaces/IStdCheats.sol";
import { IDeployer815 } from "./interfaces/IDeployer815.sol";
import { IDeployer825 } from "./interfaces/IDeployer825.sol";

// Interfaces 0.8.15
import { IETHLiquidity } from "interfaces/L2/IETHLiquidity.sol";
import { IL1BlockInterop, ConfigType } from "interfaces/L2/IL1BlockInterop.sol";
import { ILiquidityMigrator } from "interfaces/L1/ILiquidityMigrator.sol";
import { IOptimismPortalInterop } from "interfaces/L1/IOptimismPortalInterop.sol";
import { ISharedLockbox } from "interfaces/L1/ISharedLockbox.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { ISuperchainWETH } from "interfaces/L2/ISuperchainWETH.sol";
import { ISystemConfigInterop } from "interfaces/L1/ISystemConfigInterop.sol";

// Interfaces 0.8.25
import { ICrossL2Inbox } from "interfaces/L2/ICrossL2Inbox.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { ISuperchainERC20 } from "interfaces/L2/ISuperchainERC20.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";

// Libraries and Constants
import { Constants } from "src/libraries/Constants.sol";
import { GameType } from "src/dispute/lib/Types.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

import "forge-std/Test.sol";

contract Setup is Test {
    uint256 public constant INITIAL_PORTAL_ETHER = 700_000 ether;
    IDeployer815 public DEPLOYER_8_15 = IDeployer815(0x4200000000000000000000000000000000000815); // TODO: CONSTANT
    IDeployer825 public DEPLOYER_8_25 = IDeployer825(0x4200000000000000000000000000000000000825); // TODO: CONSTANT

    // Solidity 0.8.15 Contracts
    IETHLiquidity public constant ETH_LIQUIDITY = IETHLiquidity(Predeploys.ETH_LIQUIDITY);
    IL1BlockInterop public constant L1_BLOCK = IL1BlockInterop(Predeploys.L1_BLOCK_ATTRIBUTES);
    ISuperchainWETH public constant SUPER_WETH = ISuperchainWETH(payable(Predeploys.SUPERCHAIN_WETH));
    IOptimismPortalInterop public immutable PORTAL;
    ISharedLockbox public immutable SHARED_LOCKBOX;
    ISuperchainConfig public immutable SUPERCHAIN_CONFIG;
    ISystemConfigInterop public immutable SYSTEM_CONFIG;

    // Soldity 0.8.25 Contracts
    ICrossL2Inbox public constant CROSS_L2_INBOX = ICrossL2Inbox(Predeploys.CROSS_L2_INBOX);
    IL2ToL2CrossDomainMessenger public constant L2_TO_L2_MESSENGER =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    ISuperchainTokenBridge public constant SUPERCHAIN_TOKEN_BRIDGE =
        ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE);
    ISuperchainERC20 public immutable SUPER_TOKEN;

    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // Actors
    address public immutable guardian = vm.addr(uint256(keccak256("Guardian")));
    address public immutable dependencyManager = vm.addr(uint256(keccak256("DependencyManager")));
    // TODO: Deploy ProxyAdmin
    address public immutable admin = vm.addr(uint256(keccak256("Admin")));

    // Predefined addresses
    address public sharedLockboxAddress = vm.addr(uint256(keccak256("SuperchainConfig")));
    address public superchainConfigAddress = vm.addr(uint256(keccak256("SharedLockbox")));
    address public systemConfigAddress = vm.addr(uint256(keccak256("SystemConfig")));
    address public optimismPortalAddress = vm.addr(uint256(keccak256("OptimismPortal")));
    address public liquidityMigrator = vm.addr(uint256(keccak256("LiquidityMigrator")));

    // IStdCheats public vm = IStdCheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D); // TODO: Uncomment
    address internal _disputeGameFactory = vm.addr(uint256(keccak256("DisputeGameFactory")));
    bytes internal _proxyCode;

    constructor() {
        vm.etch(0x4200000000000000000000000000000000000815, vm.getDeployedCode("Deployer815"));
        vm.etch(0x4200000000000000000000000000000000000825, vm.getDeployedCode("Deployer825"));

        // Deploy Proxy
        _proxyCode = DEPLOYER_8_15.deployProxy(admin).code;

        // Deploy ETHLiquidity
        _setCode(
            Predeploys.ETH_LIQUIDITY,
            DEPLOYER_8_15.deployETHLiquidity(),
            !Predeploys.notProxied(Predeploys.ETH_LIQUIDITY)
        );

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

        // Deploy SuperchainWETH
        _setCode(
            Predeploys.SUPERCHAIN_WETH,
            DEPLOYER_8_15.deploySuperchainWETH(),
            !Predeploys.notProxied(Predeploys.SUPERCHAIN_WETH)
        );

        // Deploy SuperchainToken
        SUPER_TOKEN = ISuperchainERC20(DEPLOYER_8_25.deploySuperchainERC20());

        // Deploy SuperchainConfig
        _setCode(superchainConfigAddress, DEPLOYER_8_15.deploySuperchainConfig(sharedLockboxAddress), true);
        SUPERCHAIN_CONFIG = ISuperchainConfig(superchainConfigAddress);

        // Initialize SuperchainConfig
        SUPERCHAIN_CONFIG.initialize(guardian, dependencyManager, false);

        // Deploy SystemConfigInterop
        _setCode(systemConfigAddress, DEPLOYER_8_15.deploySystemConfig(), true);
        SYSTEM_CONFIG = ISystemConfigInterop(systemConfigAddress);

        // TODO: Initialize SystemConfigInterop

        // Deploy SharedLockbox
        _setCode(sharedLockboxAddress, DEPLOYER_8_15.deploySharedLockbox(superchainConfigAddress), true);
        SHARED_LOCKBOX = ISharedLockbox(sharedLockboxAddress);

        // Authorize the portal proxy address on the shared lockbox
        vm.prank(address(SUPERCHAIN_CONFIG));
        SHARED_LOCKBOX.authorizePortal(optimismPortalAddress);

        // Deploy LiquidityMigrator on the OptimismPortal proxy address
        _setCode(optimismPortalAddress, DEPLOYER_8_15.deployLiquidityMigrator(sharedLockboxAddress), true);

        // TODO: Deal the ether to the portal address

        // Migrate the liquidity
        ILiquidityMigrator(optimismPortalAddress).migrateETH();

        // These values are not important for the scope of this testing campaign
        (uint256 proofMaturityDelaySeconds, uint256 disputeGameFinalityDelaySeconds) = (1 weeks, 3.5 days);
        // Deploy OptimismPortal2
        _setCode(
            optimismPortalAddress,
            DEPLOYER_8_15.deployOptimismPortal(proofMaturityDelaySeconds, disputeGameFinalityDelaySeconds),
            true
        );
        PORTAL = IOptimismPortalInterop(payable(optimismPortalAddress));

        // Initialize OptimismPortal
        PORTAL.initialize(
            IDisputeGameFactory(_disputeGameFactory),
            ISystemConfig(address(SYSTEM_CONFIG)),
            SUPERCHAIN_CONFIG,
            GameType.wrap(0)
        );
    }

    /// @dev Set the code of a contract if it is not a proxy, otherwise set the code of the proxy and upgrade it.
    function _setCode(address _target, address _implementation, bool _isProxied) internal {
        if (_implementation.code.length == 0) revert("Setup: Invalid implementation address");

        if (_isProxied) {
            vm.etch(_target, _proxyCode);
            vm.store(_target, _IMPLEMENTATION_SLOT, bytes32(uint256(uint160(_implementation))));
            vm.store(_target, _ADMIN_SLOT, bytes32(uint256(uint160(admin))));

            assert(address(uint160(uint256(vm.load(_target, _IMPLEMENTATION_SLOT)))) != address(0));
            assert(address(uint160(uint256(vm.load(_target, _ADMIN_SLOT)))) == admin);
        } else {
            vm.etch(_target, _implementation.code);
        }
    }
}
