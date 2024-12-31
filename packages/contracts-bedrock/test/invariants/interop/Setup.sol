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
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
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

contract Setup {
    IStdCheats constant vm = IStdCheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    IDeployer815 constant deployer815 = IDeployer815(0x4200000000000000000000000000000000000815);
    IDeployer825 constant deployer825 = IDeployer825(0x4200000000000000000000000000000000000825);

    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // Solidity 0.8.15 Contracts
    IETHLiquidity constant ethLiquidity = IETHLiquidity(Predeploys.ETH_LIQUIDITY);
    IL1BlockInterop constant l1BlockInterop = IL1BlockInterop(Predeploys.L1_BLOCK_ATTRIBUTES);
    ILiquidityMigrator immutable liquidityMigrator;
    IOptimismPortal2 immutable optimismPortal2;
    IOptimismPortalInterop immutable optimismPortalInterop;
    ISharedLockbox immutable sharedLockbox;
    ISuperchainConfig immutable superchainConfig;
    ISuperchainWETH constant superWeth = ISuperchainWETH(payable(Predeploys.SUPERCHAIN_WETH));
    ISystemConfigInterop immutable systemConfigInterop;

    // Soldity 0.8.25 Contracts
    ICrossL2Inbox constant inbox = ICrossL2Inbox(Predeploys.CROSS_L2_INBOX);
    IL2ToL2CrossDomainMessenger constant messenger =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    ISuperchainERC20 immutable superToken;
    ISuperchainTokenBridge constant tokenBridge = ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE);

    // Actors
    address immutable guardian = vm.addr(uint256(keccak256("Guardian")));
    address immutable upgrader = vm.addr(uint256(keccak256("Upgrader")));
    address immutable admin = vm.addr(uint256(keccak256("Admin")));

    // Predefined addresses
    address immutable sharedLockboxAddress = vm.addr(uint256(keccak256("SuperchainConfig")));
    address immutable superchainConfigAddress = vm.addr(uint256(keccak256("SharedLockbox")));
    address immutable liquidityMigratorAddress = vm.addr(uint256(keccak256("LiquidityMigrator")));
    address immutable systemConfigInteropAddress = vm.addr(uint256(keccak256("SystemConfigInterop")));
    address immutable optimismPortal2Address = vm.addr(uint256(keccak256("OptimismPortal2")));
    address immutable optimismPortalInteropAddress = vm.addr(uint256(keccak256("OptimismPortalInterop")));

    bytes internal proxyCode;

    constructor() {
        // Deploy Proxy
        proxyCode = deployer815.deployProxy(admin).code;

        // Deploy ETHLiquidity
        _setCode(
            Predeploys.ETH_LIQUIDITY, deployer815.deployETHLiquidity(), !Predeploys.notProxied(Predeploys.ETH_LIQUIDITY)
        );

        // Deploy L1BlockInterop
        _setCode(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            deployer815.deployL1BlockInterop(),
            !Predeploys.notProxied(Predeploys.L1_BLOCK_ATTRIBUTES)
        );

        // Deploy LiquidityMigrator
        _setCode(liquidityMigratorAddress, deployer815.deployLiquidityMigrator(sharedLockboxAddress), true);
        liquidityMigrator = ILiquidityMigrator(liquidityMigratorAddress);

        assert(address(liquidityMigrator.SHARED_LOCKBOX()) == sharedLockboxAddress);

        //  Deploy CrossL2Inbox
        _setCode(
            Predeploys.CROSS_L2_INBOX,
            deployer825.deployCrossL2Inbox(),
            !Predeploys.notProxied(Predeploys.CROSS_L2_INBOX)
        );

        // Deploy L2ToL2CrossDomainMessenger
        _setCode(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            deployer825.deployL2ToL2CrossDomainMessenger(),
            !Predeploys.notProxied(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER)
        );

        // Deploy SuperchainTokenBridge
        _setCode(
            Predeploys.SUPERCHAIN_TOKEN_BRIDGE,
            deployer825.deploySuperchainTokenBridge(),
            !Predeploys.notProxied(Predeploys.SUPERCHAIN_TOKEN_BRIDGE)
        );

        // Deploy SuperchainWETH
        _setCode(
            Predeploys.SUPERCHAIN_WETH,
            deployer815.deploySuperchainWETH(),
            !Predeploys.notProxied(Predeploys.SUPERCHAIN_WETH)
        );

        // Deploy SuperchainToken
        superToken = ISuperchainERC20(deployer825.deploySuperchainERC20());

        // Deploy SharedLockbox
        _setCode(sharedLockboxAddress, deployer815.deploySharedLockbox(superchainConfigAddress), true);
        sharedLockbox = ISharedLockbox(sharedLockboxAddress);

        // Deploy SuperchainConfig
        _setCode(superchainConfigAddress, deployer815.deploySuperchainConfig(sharedLockboxAddress), true);
        superchainConfig = ISuperchainConfig(superchainConfigAddress);

        // Initialize SuperchainConfig
        superchainConfig.initialize(guardian, upgrader, false);

        // Deploy SystemConfigInterop
        _setCode(systemConfigInteropAddress, deployer815.deploySystemConfigInterop(), true);
        systemConfigInterop = ISystemConfigInterop(systemConfigInteropAddress);

        // These values are not important for the scope of this testing campaign
        (uint256 proofMaturityDelaySeconds, uint256 disputeGameFinalityDelaySeconds) = (0, 0);
        // Deploy OptimismPortal2
        _setCode(
            optimismPortal2Address,
            deployer815.deployOptimismPortal2(proofMaturityDelaySeconds, disputeGameFinalityDelaySeconds),
            true
        );
        optimismPortal2 = IOptimismPortal2(payable(optimismPortal2Address));

        // Initialize OptimismPortal2
        optimismPortal2.initialize(
            IDisputeGameFactory(address(0)), ISystemConfig(address(0)), superchainConfig, GameType.wrap(0)
        );
    }

    /// @dev Set the code of a contract if it is not a proxy, otherwise set the code of the proxy and upgrade it.
    function _setCode(address _target, address _implementation, bool _isProxied) internal {
        if (_implementation.code.length == 0) revert("Setup: Invalid implementation address");

        if (_isProxied) {
            vm.etch(_target, proxyCode);
            vm.store(_target, _IMPLEMENTATION_SLOT, bytes32(uint256(uint160(_implementation))));
            vm.store(_target, _ADMIN_SLOT, bytes32(uint256(uint160(admin))));

            assert(address(uint160(uint256(vm.load(_target, _IMPLEMENTATION_SLOT)))) != address(0));
            assert(address(uint160(uint256(vm.load(_target, _ADMIN_SLOT)))) == admin);
        } else {
            vm.etch(_target, _implementation.code);
        }
    }
}
