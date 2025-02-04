// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDeployer815 {
    function deployETHLiquidity() external returns (address ethLiquidity);

    function deployL1Block() external returns (address l1Block);

    function deployLiquidityMigrator(address _sharedLockbox) external returns (address liquidityMigrator);

    function deployOptimismPortalInterop(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        external
        returns (address optimismPortal);

    function deployOptimismPortal(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        external
        returns (address optimismPortal);

    function deployProxy(address _admin) external returns (address proxy);

    function deploySuperchainConfig() external returns (address superchainConfig);

    function deploySuperchainConfigInterop() external returns (address superchainConfigInterop);

    function deploySuperchainWETH() external returns (address superchainWETH);

    function deploySystemConfig() external returns (address systemConfig);

    function deployL2ToL1MessagePasser() external returns (address l2ToL1MessagePasser);
}
