// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISemver } from "interfaces/universal/ISemver.sol";
import { ISharesCalculator, ShareInfo } from "interfaces/L2/ISharesCalculator.sol";

interface IFeeSplitter is ISemver {

    error FeeSplitter_ShareCalculatorCannotBeZero();
    error FeeSplitter_DisbursementIntervalNotReached();
    error FeeSplitter_FeeShareInfoEmpty();
    error FeeSplitter_NoFeesCollected();
    error FeeSplitter_FeeVaultMustWithdrawToL2();
    error FeeSplitter_FeeVaultMustWithdrawToFeeSplitter();
    error FeeSplitter_OnlyProxyAdminOwner();
    error FeeSplitter_FailedToSendToRevenueShareRecipient();
    error FeeSplitter_ShareCalculatorMalformedOutput();
    error FeeSplitter_ReceiveWindowClosed();
    error FeeSplitter_SenderNotApprovedVault();

    event FeesReceived(address indexed sender, uint256 amount);
    event FeeDisbursementIntervalUpdated(uint128 oldFeeDisbursementInterval, uint128 newFeeDisbursementInterval);
    event Initialized(ISharesCalculator shareCalculator, uint128 feeDisbursementInterval);
    event FeesDisbursed(ShareInfo[] shareInfo, uint256 grossRevenue);
    event ShareCalculatorUpdated(address oldShareCalculator, address newShareCalculator);

    function shareCalculator() external view returns (ISharesCalculator);
    function lastDisbursementTime() external view returns (uint128);
    function feeDisbursementInterval() external view returns (uint128);

    function initialize(
        ISharesCalculator _shareCalculator,
        uint128 _feeDisbursementInterval
    ) external;

    function disburseFees() external;

    function setFeeDisbursementInterval(uint128 _newFeeDisbursementInterval) external;

    function setShareCalculator(ISharesCalculator _newShareCalculator) external;

    receive() external payable;
}
