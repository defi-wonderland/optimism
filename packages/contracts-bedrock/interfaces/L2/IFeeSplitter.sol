// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeSplitter {

    error FeeSplitter_RevenueShareRecipientCannotBeZero();
    error FeeSplitter_RevenueRemainderRecipientCannotBeZero();
    error FeeSplitter_FeeDisbursementIntervalTooShort();
    error FeeSplitter_FeeShareBPExceeds100Percent();
    error FeeSplitter_GrossFeeShareBPExceeds100Percent();
    error FeeSplitter_DisbursementIntervalNotReached();
    error FeeSplitter_FeeVaultMustWithdrawToL2();
    error FeeSplitter_FeeVaultMustWithdrawToFeeSplitter();
    error FeeSplitter_NewRevenueShareRecipientCannotBeZero();
    error FeeSplitter_NewRevenueRemainderRecipientCannotBeZero();
    error FeeSplitter_NewFeeDisbursementIntervalTooShort();
    error FeeSplitter_OnlyProxyAdminOwner();
    error FeeSplitter_FailedToSendToRevenueShareRecipient();
    error FeeSplitter_FailedToSendToRevenueRemainderRecipient();

    event FeesDisbursed(
        uint256 indexed disbursementTime,
        uint256 paidToRevenueShareRecipient,
        uint256 paidToRevenueRemainderRecipient,
        uint256 totalFeesDisbursed
    );
    event FeesReceived(address indexed sender, uint256 amount);
    event NoFeesCollected();
    event RevenueShareRecipientUpdated(
        address indexed oldRevenueShareRecipient,
        address indexed newRevenueShareRecipient
    );
    event RevenueRemainderRecipientUpdated(
        address indexed oldRevenueRemainderRecipient,
        address indexed newRevenueRemainderRecipient
    );
    event NetFeeShareBPUpdated(uint256 oldNetFeeShareBP, uint256 newNetFeeShareBP);
    event GrossFeeShareBPUpdated(uint256 oldGrossFeeShareBP, uint256 newGrossFeeShareBP);
    event FeeDisbursementIntervalUpdated(
        uint256 oldInterval,
        uint256 newInterval
    );
    event Initialized(
        address payable revenueShareRecipient,
        address payable revenueRemainderRecipient,
        uint32 feeDisbursementInterval,
        uint32 netFeeShareBP,
        uint32 grossFeeShareBP
    );

    function version() external view returns (string memory);
    function BASIS_POINT_SCALE() external view returns (uint32);
    function MIN_FEE_DISBURSEMENT_INTERVAL() external view returns (uint256);
    function revenueShareRecipient() external view returns (address payable);
    function revenueRemainderRecipient() external view returns (address payable);
    function lastDisbursementTime() external view returns (uint256);
    function netFeeRevenue() external view returns (uint128);
    function netFeeShareBP() external view returns (uint32);
    function grossFeeShareBP() external view returns (uint32);
    function feeDisbursementInterval() external view returns (uint32);
    function initialize(
        address payable _revenueShareRecipient,
        address payable _revenueRemainderRecipient,
        uint32 _feeDisbursementInterval,
        uint32 _netFeeShareBP,
        uint32 _grossFeeShareBP
    ) external;
    function disburseFees() external;
    function setRevenueShareRecipient(
        address _newRevenueShareRecipient
    ) external;
    function setRevenueRemainderRecipient(
        address payable _newRevenueRemainderRecipient
    ) external;
    function setNetFeeShareBP(uint32 _newNetFeeShareBP) external;
    function setGrossFeeShareBP(uint32 _newGrossFeeShareBP) external;
    function setFeeDisbursementInterval(
        uint32 _newFeeDisbursementInterval
    ) external;

    receive() external payable;
}
