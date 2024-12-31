// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ETHLiquidity } from "src/L2/ETHLiquidity.sol";
import { L1BlockInterop } from "src/L2/L1BlockInterop.sol";
import { LiquidityMigrator } from "src/L1/LiquidityMigrator.sol";
import { OptimismPortalMock } from "test/invariants/interop/mocks/OptimismPortalMock.sol";
import { OptimismPortalInterop } from "src/L1/OptimismPortalInterop.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { SharedLockbox } from "src/L1/SharedLockbox.sol";
import { SuperchainConfig } from "src/L1/SuperchainConfig.sol";
import { SuperchainWETH } from "src/L2/SuperchainWETH.sol";
import { SystemConfigInterop } from "src/L1/SystemConfigInterop.sol";

contract Deployer815 {
    function deployETHLiquidity() public returns (address _ethLiquidity) {
        _ethLiquidity = address(new ETHLiquidity());
    }

    function deployL1Block() public returns (address _l1Block) {
        _l1Block = address(new L1BlockInterop());
    }

    function deployLiquidityMigrator(address _sharedLockbox) public returns (address _liquidityMigrator) {
        _liquidityMigrator = address(new LiquidityMigrator(_sharedLockbox));
    }

    function deployOptimismPortal(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        public
        returns (address _optimismPortal)
    {
        _optimismPortal = address(new OptimismPortalMock(_proofMaturityDelaySeconds, _disputeGameFinalityDelaySeconds));
    }

    function deployProxy(address _admin) public returns (address proxy) {
        proxy = address(new Proxy(_admin));
    }

    function deploySharedLockbox(address _superchainConfig) public returns (address _sharedLockbox) {
        _sharedLockbox = address(new SharedLockbox(_superchainConfig));
    }

    function deploySuperchainConfig(address _sharedLockbox) public returns (address _superchainConfig) {
        _superchainConfig = address(new SuperchainConfig(_sharedLockbox));
    }

    function deploySuperchainWETH() public returns (address _superchainWETH) {
        _superchainWETH = address(new SuperchainWETH());
    }

    function deploySystemConfig() public returns (address _systemConfig) {
        _systemConfig = address(new SystemConfigInterop());
    }
}
