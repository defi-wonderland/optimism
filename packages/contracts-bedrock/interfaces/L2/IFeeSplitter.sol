// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeSplitter {

    error FeeSplitter_ConfiguredShareRecipientCannotBeZero();
    error FeeSplitter_RemainderRecipientCannotBeZero();
    error FeeSplitter_FeeDisbursementIntervalTooShort();
    error FeeSplitter_FeeShareBPExceeds100Percent();
    error FeeSplitter_GrossFeeShareBPExceeds100Percent();
    error FeeSplitter_DisbursementIntervalNotReached();
    error FeeSplitter_FeeVaultMustWithdrawToL2();
    error FeeSplitter_FeeVaultMustWithdrawToFeeSplitter();
    error FeeSplitter_NewConfiguredShareRecipientCannotBeZero();
    error FeeSplitter_NewRemainderRecipientCannotBeZero();
    error FeeSplitter_NewFeeDisbursementIntervalTooShort();
    error FeeSplitter_OnlyProxyAdminOwner();
    error FeeSplitter_FailedToSendToConfiguredShareRecipient();
    error FeeSplitter_FailedToSendToRemainderRecipient();

    event FeesDisbursed(
        uint256 indexed disbursementTime,
        uint256 paidConfiguredShareRecipient,
        uint256 paidToRemainderRecipient,
        uint256 totalFeesDisbursed
    );
    event FeesReceived(address indexed sender, uint256 amount);
    event NoFeesCollected();
    event ConfiguredShareRecipientUpdated(
        address indexed oldConfiguredShareRecipient,
        address indexed newConfiguredShareRecipient
    );
    event RemainderRecipientUpdated(
        address indexed oldRemainderRecipient,
        address indexed newRemainderRecipient
    );
    event NetFeeShareBPUpdated(uint256 oldNetFeeShareBP, uint256 newNetFeeShareBP);
    event GrossFeeShareBPUpdated(uint256 oldGrossFeeShareBP, uint256 newGrossFeeShareBP);
    event FeeDisbursementIntervalUpdated(
        uint256 oldInterval,
        uint256 newInterval
    );
    event Initialized(
        address payable configuredShareRecipient,
        address payable remainderRecipient,
        uint32 feeDisbursementInterval,
        uint32 netFeeShareBP,
        uint32 grossFeeShareBP
    );

    function version() external view returns (string memory);
    function BASIS_POINT_SCALE() external view returns (uint32);
    function MIN_FEE_DISBURSEMENT_INTERVAL() external view returns (uint256);
    function configuredShareRecipient() external view returns (address payable);
    function remainderRecipient() external view returns (address payable);
    function lastDisbursementTime() external view returns (uint256);
    function netFeeRevenue() external view returns (uint128);
    function netFeeShareBP() external view returns (uint32);
    function grossFeeShareBP() external view returns (uint32);
    function feeDisbursementInterval() external view returns (uint32);
    function initialize(
        address payable _configuredShareRecipient,
        address payable _remainderRecipient,
        uint32 _feeDisbursementInterval,
        uint32 _netFeeShareBP,
        uint32 _grossFeeShareBP
    ) external;
    function disburseFees() external;
    function setConfiguredShareRecipient(
        address _newConfiguredShareRecipient
    ) external;
    function setRemainderRecipient(
        address payable _oldRemainderRecipient
    ) external;
    function setNetFeeShareBP(uint32 _newNetFeeShareBP) external;
    function setGrossFeeShareBP(uint32 _newGrossFeeShareBP) external;
    function setFeeDisbursementInterval(
        uint32 _newFeeDisbursementInterval
    ) external;

    receive() external payable;
}
