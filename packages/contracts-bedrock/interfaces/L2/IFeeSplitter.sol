// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeSplitter {
    //////////////////////////////////////////////////////////////////////////////////////
    ///                                     Events                                     ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when fees are disbursed.
    ///
    /// @param disbursementTime   The time of the disbursement.
    /// @param paidToRecipientA     The amount of fees disbursed to the recipient A.
    /// @param paidToRecipientB    The amount of fees disbursed to the recipient B.
    /// @param totalFeesDisbursed The total amount of fees disbursed.
    event FeesDisbursed(
        uint256 indexed disbursementTime, uint256 paidToRecipientA, uint256 paidToRecipientB, uint256 totalFeesDisbursed
    );

    /// @notice Emitted when fees are received from FeeVaults.
    ///
    /// @param sender The FeeVault that sent the fees.
    /// @param amount The amount of fees received.
    event FeesReceived(address indexed sender, uint256 amount);

    /// @notice Emitted when no fees are collected from FeeVaults at time of disbursement.
    event NoFeesCollected();

    /// @notice Emitted when the recipient A address is updated.
    ///
    /// @param oldRecipientA The previous recipient A address.
    /// @param newRecipientA The new recipient A address.
    event FeeRecipientAUpdated(address indexed oldRecipientA, address indexed newRecipientA);

    /// @notice Emitted when the recipient B address is updated.
    ///
    /// @param oldRecipientB The previous recipient B address.
    /// @param newRecipientB The new recipient B address.
    event FeeRecipientBUpdated(address indexed oldRecipientB, address indexed newRecipientB);

    /// @notice Emitted when the fee share in basis points is updated.
    ///
    /// @param oldFeeShareBP The previous fee share in basis points.
    /// @param newFeeShareBP The new fee share in basis points.
    event FeeShareBPUpdated(uint256 oldFeeShareBP, uint256 newFeeShareBP);

    /// @notice Emitted when the fee disbursement interval is updated.
    ///
    /// @param oldInterval The previous fee disbursement interval.
    /// @param newInterval The new fee disbursement interval.
    event FeeDisbursementIntervalUpdated(uint256 oldInterval, uint256 newInterval);

    /// @notice Emitted when the contract is initialized.
    ///
    /// @param feeRecipientA           The address which receives the fee share of the revenue.
    /// @param feeRecipientB           The address which receives the remainder of the revenue.
    /// @param feeDisbursementInterval The minimum amount of time in seconds that must pass between fee disbursals.
    /// @param feeShareBP              The fee share percentage in basis points.
    event Initialized(
        address payable feeRecipientA, address payable feeRecipientB, uint256 feeDisbursementInterval, uint256 feeShareBP
    );

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                   Constants                                    ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @custom:semver 1.0.0
    function version() external view returns (string memory);

    /// @notice The basis point scale which revenue share splits are denominated in.
    function BASIS_POINT_SCALE() external view returns (uint32);

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    function MIN_FEE_DISBURSEMENT_INTERVAL() external view returns (uint256);

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                    Storage                                     ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice An address that recieves the fee split of the total fees dispursed
    function feeRecipientA() external view returns (address payable);

    /// @notice An address that recieves the remainder of the total fees disbursed.
    function feeRecipientB() external view returns (address payable);

    /// @notice The timestamp of the last disbursal.
    function lastDisbursementTime() external view returns (uint256);

    /// @notice Tracks aggregate net fee revenue which is the sum of all fees received by this contract.
    function netFeeRevenue() external view returns (uint256);

    /// @notice The revenue share percentage denominated in basis points.
    function feeShareBP() external view returns (uint256);

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    function feeDisbursementInterval() external view returns (uint256);

    //////////////////////////////////////////////////////////////////////////////////////
    ///                               External Functions                               ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @dev Receives ETH fees withdrawn from L2 FeeVaults.
    /// @dev Will revert if ETH is not sent from L2 FeeVaults.
    receive() external payable;

    /// @notice Initializes the contract with all required addresses and parameters.
    /// @dev This function can only be called once and must be called by the ProxyAdmin owner.
    ///
    /// @param _feeRecipientA           The address which receives the fee share of the revenue.
    /// @param _feeRecipientB           The address which receives the remainder of the revenue.
    /// @param _feeDisbursementInterval The minimum amount of time in seconds that must pass between fee disbursals.
    /// @param _feeShareBP              The fee share percentage in basis points.
    function initialize(
        address payable _feeRecipientA,
        address payable _feeRecipientB,
        uint256 _feeDisbursementInterval,
        uint256 _feeShareBP
    )
        external;

    /// @notice Withdraws funds from FeeVaults, sends the fee share to the fee recipient A, and sends the remainder to the
    /// fee recipient B.
    function disburseFees() external;

    /// @notice Updates the fee recipient A address.
    ///
    /// @param _newFeeRecipientA The new fee recipient A address.
    function setFeeRecipientA(address _newFeeRecipientA) external;

    /// @notice Updates the fee recipient B address.
    ///
    /// @param _newFeeRecipientB The new fee recipient B address.
    function setFeeRecipientB(address payable _newFeeRecipientB) external;

    /// @notice Updates the fee share percentage in basis points.
    ///
    /// @param _newFeeShareBP The new fee share percentage in basis points.
    function setFeeShareBP(uint256 _newFeeShareBP) external;

    /// @notice Updates the fee disbursement interval.
    ///
    /// @param _newFeeDisbursementInterval The new fee disbursement interval in seconds.
    function setFeeDisbursementInterval(uint256 _newFeeDisbursementInterval) external;
}