// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDeployer815 {
    function deployETHLiquidity() external returns (address ethLiquidity);

    function deployL1BlockInterop() external returns (address l1BlockInterop);

    function deployLiquidityMigrator(address _sharedLockbox) external returns (address liquidityMigrator);

    function deployOptimismPortal2(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        external
        returns (address optimismPortal2);

    function deployOptimismPortalInterop(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        external
        returns (address optimismPortalInterop);

    function deploySharedLockbox(address _superchainConfig) external returns (address sharedLockbox);

    function deploySuperchainConfig(address _sharedLockbox) external returns (address superchainConfig);

    function deploySuperchainWETH() external returns (address superchainWETH);

    function deploySystemConfigInterop() external returns (address systemConfigInterop);
}
