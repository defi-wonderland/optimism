// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//Testing
import { IStdCheats } from "./IStdCheats.sol";

// Interfaces
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
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract FuzzTest {
    IStdCheats constant vm = IStdCheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    IDeployer815 constant deployer815 = IDeployer815(0x4200000000000000000000000000000000000815);
    IDeployer825 constant deployer825 = IDeployer825(0x4200000000000000000000000000000000000825);

    // Soldity 0.8.25 Contracts
    ICrossL2Inbox immutable inbox = ICrossL2Inbox(Predeploys.CROSS_L2_INBOX);
    IL2ToL2CrossDomainMessenger constant messenger =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    ISuperchainTokenBridge constant tokenBridge = ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE);
    ISuperchainERC20 immutable medusaToken;

    // Solidity 0.8.15 Contracts
    IL1BlockInterop constant l1BlockInterop = IL1BlockInterop(0x4200000000000000000000000000000000000015);
    IETHLiquidity constant ethLiquidity = IETHLiquidity(Predeploys.ETH_LIQUIDITY);
    ISharedLockbox immutable sharedLockbox;
    ILiquidityMigrator immutable liquidityMigrator;
    ISuperchainConfig immutable superchainConfig;
    ISystemConfigInterop immutable systemConfigInterop;
    IOptimismPortal2 immutable optimismPortal2;
    IOptimismPortalInterop immutable optimismPortalInterop;
    ISuperchainWETH constant superWeth = ISuperchainWETH(payable(Predeploys.SUPERCHAIN_WETH));

    constructor() {
        vm.etch(address(inbox), deployer825.deployCrossL2Inbox().code);
    }

    function test_setIntropStartBlock() external {
        vm.prank(0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001);
        try inbox.setInteropStart() {
            assert(inbox.interopStart() == 0);
        } catch {
            assert(false);
        }
    }
}
