// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { SuperchainWETH } from "src/L2/SuperchainWETH.sol";
import { ETHLiquidity } from "src/L2/ETHLiquidity.sol";
import { SharedLockbox } from "src/L1/SharedLockbox.sol";
import { LiquidityMigrator } from "src/L1/LiquidityMigrator.sol";
import { SuperchainConfig } from "src/L1/SuperchainConfig.sol";
import { SystemConfigInterop } from "src/L1/SystemConfigInterop.sol";
import { OptimismPortal2 } from "src/L1/OptimismPortal2.sol";
import { OptimismPortalInterop } from "src/L1/OptimismPortalInterop.sol";
import { L1BlockInterop } from "src/L2/L1BlockInterop.sol";

contract Deployer815 {
    function deployL1BlockInterop() public returns (address l1BlockInterop) {
        l1BlockInterop = address(new L1BlockInterop());
    }

    function deploySuperchainWETH() public returns (address superchainWETH) {
        superchainWETH = address(new SuperchainWETH());
    }

    function deployETHLiquidity() public returns (address ethLiquidity) {
        ethLiquidity = address(new ETHLiquidity());
    }

    function deploySharedLockbox(address _superchainConfig) public returns (address sharedLockbox) {
        sharedLockbox = address(new SharedLockbox(_superchainConfig));
    }

    function deployLiquidityMigrator(address _sharedLockbox) public returns (address liquidityMigrator) {
        liquidityMigrator = address(new LiquidityMigrator(_sharedLockbox));
    }

    function deploySuperchainConfig(address _sharedLockbox) public returns (address superchainConfig) {
        superchainConfig = address(new SuperchainConfig(_sharedLockbox));
    }

    function deploySystemConfigInterop(address _superchainConfig) public returns (address systemConfigInterop) {
        systemConfigInterop = address(new SystemConfigInterop(_superchainConfig));
    }

    function deployOptimismPortal2(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        public
        returns (address optimismPortal2)
    {
        optimismPortal2 = address(new OptimismPortal2(_proofMaturityDelaySeconds, _disputeGameFinalityDelaySeconds));
    }

    function deployOptimismPortalInterop(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        public
        returns (address optimismPortalInterop)
    {
        optimismPortalInterop =
            address(new OptimismPortalInterop(_proofMaturityDelaySeconds, _disputeGameFinalityDelaySeconds));
    }
}
