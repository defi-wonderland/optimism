// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//Testing
import { IStdCheats } from "./IStdCheats.sol";
import { UpgradeableProxy } from "./UpgradeableProxy.sol";

// Interfaces
import { IL1BlockInterop, ConfigType } from "interfaces/L2/IL1BlockInterop.sol";
import { ISharedLockbox } from "interfaces/L1/ISharedLockbox.sol";
import { ILiquidityMigrator } from "interfaces/L1/ILiquidityMigrator.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { ISystemConfigInterop } from "interfaces/L1/ISystemConfigInterop.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IOptimismPortalInterop } from "interfaces/L1/IOptimismPortalInterop.sol";
import { ICrossL2Inbox } from "interfaces/L2/ICrossL2Inbox.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { ISuperchainWETH } from "interfaces/L2/ISuperchainWETH.sol";
import { IETHLiquidity } from "interfaces/L2/IETHLiquidity.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";
import { IL1BlockInterop } from "interfaces/L2/IL1BlockInterop.sol";
import { ISuperchainERC20 } from "interfaces/L2/ISuperchainERC20.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { GameType } from "src/dispute/lib/Types.sol";

import { IDeployer815 } from "./IDeployer815.sol";
import { IDeployer825 } from "./IDeployer825.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Constants } from "src/libraries/Constants.sol";

contract FuzzTest {
    IStdCheats constant vm = IStdCheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    IDeployer815 constant deployer815 = IDeployer815(0x4200000000000000000000000000000000000815);
    IDeployer825 constant deployer825 = IDeployer825(0x4200000000000000000000000000000000000825);

    // Soldity 0.8.25 Contracts
    ICrossL2Inbox constant inbox = ICrossL2Inbox(Predeploys.CROSS_L2_INBOX);
    IL2ToL2CrossDomainMessenger constant messenger =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    ISuperchainTokenBridge constant tokenBridge = ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE);
    ISuperchainERC20 immutable medusaToken;

    // Solidity 0.8.15 Contracts
    IL1BlockInterop constant l1BlockInterop = IL1BlockInterop(Predeploys.L1_BLOCK_ATTRIBUTES);
    IETHLiquidity constant ethLiquidity = IETHLiquidity(Predeploys.ETH_LIQUIDITY);
    ISuperchainWETH constant superWeth = ISuperchainWETH(payable(Predeploys.SUPERCHAIN_WETH));
    ISharedLockbox immutable sharedLockbox;
    ISuperchainConfig immutable superchainConfig;
    ILiquidityMigrator immutable liquidityMigrator;
    ISystemConfigInterop immutable systemConfigInterop;
    IOptimismPortal2 immutable optimismPortal2;
    IOptimismPortalInterop immutable optimismPortalInterop;

    // Actors
    address guardian = address(uint160(uint256(keccak256("Guardian"))));
    address upgrader = address(uint160(uint256(keccak256("Upgrader"))));

    constructor() {
        //  Deploy CrossL2Inbox
        _setCode(
            Predeploys.CROSS_L2_INBOX,
            deployer825.deployCrossL2Inbox(),
            !Predeploys.notProxied(Predeploys.CROSS_L2_INBOX)
        );

        // Deploy L1BlockAtributes
        _setCode(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            deployer815.deployL1BlockInterop(),
            !Predeploys.notProxied(Predeploys.L1_BLOCK_ATTRIBUTES)
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

        // Deploy ETHLiquidity
        _setCode(
            Predeploys.ETH_LIQUIDITY, deployer815.deployETHLiquidity(), !Predeploys.notProxied(Predeploys.ETH_LIQUIDITY)
        );

        // Deploy SuperchainToken
        medusaToken = ISuperchainERC20(deployer825.deploySuperchainERC20());

        // Deploy SharedLockbox and SuperchainConfig
        address sharedLockboxAddress = address(uint160(uint256(keccak256("SuperchainConfig"))));
        address superchainConfigAddress = address(uint160(uint256(keccak256("SharedLockbox"))));
        _setCode(sharedLockboxAddress, deployer815.deploySharedLockbox(superchainConfigAddress), true);
        _setCode(superchainConfigAddress, deployer815.deploySuperchainConfig(sharedLockboxAddress), true);
        sharedLockbox = ISharedLockbox(sharedLockboxAddress);
        superchainConfig = ISuperchainConfig(superchainConfigAddress);

        // Initialize SuperchainConfig
        superchainConfig.initialize(guardian, upgrader, false);

        // Deploy LiquidityMigrator
        address liquidityMigratorAddress = address(uint160(uint256(keccak256("LiquidityMigrator"))));
        _setCode(liquidityMigratorAddress, deployer815.deployLiquidityMigrator(sharedLockboxAddress), true);
        liquidityMigrator = ILiquidityMigrator(liquidityMigratorAddress);

        // Deploy SystemConfigInterop
        address systemConfigInteropAddress = address(uint160(uint256(keccak256("SystemConfigInterop"))));
        _setCode(systemConfigInteropAddress, deployer815.deploySystemConfigInterop(superchainConfigAddress), true);
        systemConfigInterop = ISystemConfigInterop(systemConfigInteropAddress);

        // Deploy OptimismPortal2
        address optimismPortal2Address = address(uint160(uint256(keccak256("OptimismPortal2"))));
        _setCode(optimismPortal2Address, deployer815.deployOptimismPortal2(0, 0), true); // TODO: Set the correct values
        optimismPortal2 = IOptimismPortal2(payable(optimismPortal2Address));

        // Initialize OptimismPortal2
        optimismPortal2.initialize(
            IDisputeGameFactory(address(0)), ISystemConfig(address(0)), superchainConfig, GameType.wrap(0)
        );

        // Deploy OptimismPortalInterop
        address optimismPortalInteropAddress = address(uint160(uint256(keccak256("OptimismPortalInterop"))));
        _setCode(optimismPortalInteropAddress, deployer815.deployOptimismPortalInterop(0, 0), true);
        optimismPortalInterop = IOptimismPortalInterop(payable(optimismPortalInteropAddress));
    }

    function test_inbox() external {
        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        try inbox.setInteropStart() {
            assert(inbox.interopStart() == 0); // Intended to fail to test the try-catch
        } catch {
            assert(false);
        }
    }

    function test_messenger(address _target, bytes calldata _message) external {
        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        l1BlockInterop.setConfig(ConfigType.ADD_DEPENDENCY, abi.encode("", 2));

        try messenger.sendMessage(2, _target, _message) {
            assert(false); // Intended to fail to test the try-catch
        } catch {
            assert(false);
        }
    }

    function test_superWeth() external {
        assert(superWeth.decimals() == 18);
    }

    function test_sharedLockbox() external {
        assert(address(sharedLockbox.SUPERCHAIN_CONFIG()) != address(superchainConfig));
    }

    /// @dev Set the code of a contract if it is not a proxy, otherwise set the code of the proxy and upgrade it.
    function _setCode(address _target, address _implementation, bool _isProxied) internal {
        if (_isProxied) {
            vm.etch(_target, type(UpgradeableProxy).runtimeCode);
            UpgradeableProxy(payable(_target)).upgradeTo(_implementation);
        } else {
            vm.etch(_target, _implementation.code);
        }
    }
}
