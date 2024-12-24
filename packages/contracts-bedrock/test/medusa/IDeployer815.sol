// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDeployer815 {
    function deploySuperchainWETH() external returns (address superchainWETH);

    function deployETHLiquidity() external returns (address ethLiquidity);

    function deploySharedLockbox(address _superchainConfig) external returns (address sharedLockbox);

    function deployLiquidityMigrator(address _sharedLockbox) external returns (address liquidityMigrator);

    function deploySuperchainConfig(address _sharedLockbox) external returns (address superchainConfig);

    function deploySystemConfigInterop(address _superchainConfig) external returns (address systemConfigInterop);

    function deployOptimismPortal2(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        external
        returns (address optimismPortal2);
}
