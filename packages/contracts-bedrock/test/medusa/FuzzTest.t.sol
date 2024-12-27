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
    ISharedLockbox immutable sharedLockbox;
    ILiquidityMigrator immutable liquidityMigrator;
    ISuperchainConfig immutable superchainConfig;
    ISystemConfigInterop immutable systemConfigInterop;
    IOptimismPortal2 immutable optimismPortal2;
    IOptimismPortalInterop immutable optimismPortalInterop;
    ISuperchainWETH constant superWeth = ISuperchainWETH(payable(Predeploys.SUPERCHAIN_WETH));

    constructor() {
        //  Deploy CrossL2Inbox
        _setCode(Predeploys.CROSS_L2_INBOX, deployer825.deployCrossL2Inbox());

        // Deploy L1BlockAtributes
        _setCode(Predeploys.L1_BLOCK_ATTRIBUTES, deployer815.deployL1BlockInterop());

        // Deploy L2ToL2CrossDomainMessenger
        _setCode(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, deployer825.deployL2ToL2CrossDomainMessenger());

        // Deploy SuperchainTokenBridge
        _setCode(Predeploys.SUPERCHAIN_TOKEN_BRIDGE, deployer825.deploySuperchainTokenBridge());

        // Deploy SuperchainWETH
        _setCode(Predeploys.SUPERCHAIN_WETH, deployer815.deploySuperchainWETH());
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

    /// @dev Set the code of a contract if it is not a proxy, otherwise set the code of the proxy and upgrade it.
    function _setCode(address _target, address _implementation) internal {
        if (Predeploys.notProxied(_target)) {
            vm.etch(_target, _implementation.code);
        } else {
            vm.etch(_target, type(UpgradeableProxy).runtimeCode);
            UpgradeableProxy(payable(_target)).upgradeTo(_implementation);
        }
    }
}
