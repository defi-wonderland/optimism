// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { FeeVault } from "src/L2/FeeVault.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";
import { Types } from "src/libraries/Types.sol";

// Interfaces
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

// OpenZeppelin
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:proxied
/// @custom:predeploy 0x4200000000000000000000000000000000000029
/// @title FeeSplitter
/// @notice Withdraws funds from system FeeVault contracts, sends Optimism their revenue share, and
///         sends the remaining funds to the fee router.
contract FeeSplitter is ISemver, Initializable {
    //////////////////////////////////////////////////////////////////////////////////////
    ///                                   Errors                                       ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when the fee recipient address is zero.
    error FeeSplitter_ConfiguredShareRecipientCannotBeZero();

    /// @notice Thrown when the fee recipient address is zero.
    error FeeSplitter_RemainderRecipientCannotBeZero();

    /// @notice Thrown when the fee disbursement interval is less than 24 hours.
    error FeeSplitter_FeeDisbursementIntervalTooShort();

    /// @notice Thrown when the fee share exceeds 100%.
    error FeeSplitter_FeeShareBPExceeds100Percent();

    /// @notice Thrown when the disbursement interval has not been reached.
    error FeeSplitter_DisbursementIntervalNotReached();

    /// @notice Thrown when the FeeVault does not withdraw to L2.
    error FeeSplitter_FeeVaultMustWithdrawToL2();

    /// @notice Thrown when the FeeVault does not withdraw to FeeSplitter contract.
    error FeeSplitter_FeeVaultMustWithdrawToFeeSplitter();

    /// @notice Thrown when the new fee recipient address is zero.
    error FeeSplitter_NewConfiguredShareRecipientCannotBeZero();

    /// @notice Thrown when the new fee recipient address is zero.
    error FeeSplitter_NewRemainderRecipientCannotBeZero();

    /// @notice Thrown when the new fee disbursement interval is less than 24 hours.
    error FeeSplitter_NewFeeDisbursementIntervalTooShort();

    /// @notice Thrown when the caller is not the ProxyAdmin owner.
    error FeeSplitter_OnlyProxyAdminOwner();

    /// @notice Thrown when sending funds to the fee recipient fails.
    error FeeSplitter_FailedToSendToConfiguredShareRecipient();

    /// @notice Thrown when sending funds to the fee recipient fails.
    error FeeSplitter_FailedToSendToRemainderRecipient();

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                   Constants                                    ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice The basis point scale which revenue share splits are denominated in.
    uint32 public constant BASIS_POINT_SCALE = 10_000;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint256 public constant MIN_FEE_DISBURSEMENT_INTERVAL = 24 hours;

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                    Storage                                     ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice An address that receives the fee split of the total fees disbursed
    address payable public configuredShareRecipient;

    /// @notice An address that receives the remainder of the total fees disbursed.
    address payable public remainderRecipient;

    /// @notice The timestamp of the last disbursal.
    uint256 public lastDisbursementTime;

    /// @notice Tracks aggregate net fee revenue which is the sum of all fees received by this contract.
    uint256 public netFeeRevenue;

    /// @notice The revenue share percentage denominated in basis points.
    uint256 public feeShareBP;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint256 public feeDisbursementInterval;

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                     Events                                     ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when fees are disbursed.
    ///
    /// @param disbursementTime   The time of the disbursement.
    /// @param paidConfiguredShareRecipient     The amount of fees disbursed to the fee share recipient.
    /// @param paidToRemainderRecipient    The amount of fees disbursed to the remainder recipient.
    /// @param totalFeesDisbursed The total amount of fees disbursed.
    event FeesDisbursed(
        uint256 indexed disbursementTime,
        uint256 paidConfiguredShareRecipient,
        uint256 paidToRemainderRecipient,
        uint256 totalFeesDisbursed
    );

    /// @notice Emitted when fees are received from FeeVaults.
    ///
    /// @param sender The FeeVault that sent the fees.
    /// @param amount The amount of fees received.
    event FeesReceived(address indexed sender, uint256 amount);

    /// @notice Emitted when no fees are collected from FeeVaults at time of disbursement.
    event NoFeesCollected();

    /// @notice Emitted when the share recipient address is updated.
    ///
    /// @param oldConfiguredShareRecipient The previous recipient A address.
    /// @param newConfiguredShareRecipient The new recipient A address.
    event ConfiguredShareRecipientUpdated(
        address indexed oldConfiguredShareRecipient, address indexed newConfiguredShareRecipient
    );

    /// @notice Emitted when the remainder recipient address is updated.
    ///
    /// @param oldRemainderRecipient The previous recipient B address.
    /// @param newRemainderRecipient The new recipient B address.
    event RemainderRecipientUpdated(address indexed oldRemainderRecipient, address indexed newRemainderRecipient);

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
    /// @param configuredShareRecipient           The address which receives the fee share of the revenue.
    /// @param remainderRecipient           The address which receives the remainder of the revenue.
    /// @param feeDisbursementInterval The minimum amount of time in seconds that must pass between fee disbursals.
    /// @param feeShareBP              The fee share percentage in basis points.
    event Initialized(
        address payable configuredShareRecipient,
        address payable remainderRecipient,
        uint256 feeDisbursementInterval,
        uint256 feeShareBP
    );

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                  Constructor                                   ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Constructor for the FeeSplitter contract which validates and sets immutable variables.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with all required addresses and parameters.
    /// @dev This function can only be called once and must be called by the ProxyAdmin owner.
    ///
    /// @param _configuredShareRecipient           The address which receives the fee share of the revenue.
    /// @param _remainderRecipient           The address which receives the remainder of the revenue.
    /// @param _feeDisbursementInterval The minimum amount of time in seconds that must pass between fee disbursals.
    /// @param _feeShareBP              The fee share percentage in basis points.
    function initialize(
        address payable _configuredShareRecipient,
        address payable _remainderRecipient,
        uint256 _feeDisbursementInterval,
        uint256 _feeShareBP
    )
        external
        initializer
        onlyOwner
    {
        if (_configuredShareRecipient == address(0)) {
            revert FeeSplitter_ConfiguredShareRecipientCannotBeZero();
        }
        if (_remainderRecipient == address(0)) {
            revert FeeSplitter_RemainderRecipientCannotBeZero();
        }
        if (_feeDisbursementInterval < MIN_FEE_DISBURSEMENT_INTERVAL) {
            revert FeeSplitter_FeeDisbursementIntervalTooShort();
        }
        if (_feeShareBP > BASIS_POINT_SCALE) {
            revert FeeSplitter_FeeShareBPExceeds100Percent();
        }

        configuredShareRecipient = _configuredShareRecipient;
        remainderRecipient = _remainderRecipient;
        feeDisbursementInterval = _feeDisbursementInterval;
        feeShareBP = _feeShareBP;

        emit Initialized(_configuredShareRecipient, _remainderRecipient, _feeDisbursementInterval, _feeShareBP);
    }

    //////////////////////////////////////////////////////////////////////////////////////
    ///                               Modifiers                                       ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Modifier that restricts access to the ProxyAdmin owner.
    modifier onlyOwner() {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert FeeSplitter_OnlyProxyAdminOwner();
        }
        _;
    }

    //////////////////////////////////////////////////////////////////////////////////////
    ///                               External Functions                               ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @dev Receives ETH fees withdrawn from L2 FeeVaults.
    /// @dev Will revert if ETH is not sent from L2 FeeVaults.
    receive() external payable virtual {
        if (
            msg.sender == Predeploys.SEQUENCER_FEE_WALLET || msg.sender == Predeploys.BASE_FEE_VAULT
                || msg.sender == Predeploys.L1_FEE_VAULT || msg.sender == Predeploys.OPERATOR_FEE_VAULT
        ) {
            // Adds value received to net fee revenue if the sender is the sequencer or base FeeVault
            netFeeRevenue += msg.value;
        }
        emit FeesReceived({ sender: msg.sender, amount: msg.value });
    }

    /// @notice Withdraws funds from FeeVaults, sends the fee share to the fee share recipient, and sends the remainder
    /// to the
    /// remainder recipient.
    function disburseFees() external {
        if (block.timestamp < lastDisbursementTime + feeDisbursementInterval) {
            revert FeeSplitter_DisbursementIntervalNotReached();
        }

        // Sequencer and base FeeVaults will withdraw fees to the FeeSplitter
        _feeVaultWithdrawal(payable(Predeploys.SEQUENCER_FEE_WALLET));
        _feeVaultWithdrawal(payable(Predeploys.BASE_FEE_VAULT));
        _feeVaultWithdrawal(payable(Predeploys.L1_FEE_VAULT));
        _feeVaultWithdrawal(payable(Predeploys.OPERATOR_FEE_VAULT));

        // Gross revenue is the sum of all fees
        uint256 feeBalance = address(this).balance;

        // Stop execution if no fees were collected
        if (feeBalance == 0) {
            emit NoFeesCollected();
            return;
        }

        lastDisbursementTime = block.timestamp;

        // Calculate fee share amount
        uint256 feeShare = (feeBalance * feeShareBP) / BASIS_POINT_SCALE;

        if (!SafeCall.send({ _target: configuredShareRecipient, _gas: gasleft(), _value: feeShare })) {
            revert FeeSplitter_FailedToSendToConfiguredShareRecipient();
        }

        // Send the remainder to remainderRecipient
        if (!SafeCall.send({ _target: remainderRecipient, _gas: gasleft(), _value: feeBalance - feeShare })) {
            revert FeeSplitter_FailedToSendToRemainderRecipient();
        }

        emit FeesDisbursed({
            disbursementTime: lastDisbursementTime,
            paidConfiguredShareRecipient: feeShare,
            paidToRemainderRecipient: feeBalance - feeShare,
            totalFeesDisbursed: feeBalance
        });
    }

    /// @notice Updates the fee share recipient address.
    ///
    /// @param _newConfiguredShareRecipient The new fee share recipient address.
    function setConfiguredShareRecipient(address _newConfiguredShareRecipient) external onlyOwner {
        if (_newConfiguredShareRecipient == address(0)) {
            revert FeeSplitter_NewConfiguredShareRecipientCannotBeZero();
        }
        address oldConfiguredShareRecipient = configuredShareRecipient;
        configuredShareRecipient = payable(_newConfiguredShareRecipient);
        emit ConfiguredShareRecipientUpdated(oldConfiguredShareRecipient, _newConfiguredShareRecipient);
    }

    /// @notice Updates the remainder recipient address.
    ///
    /// @param _oldRemainderRecipient The new remainder recipient address.
    function setRemainderRecipient(address payable _oldRemainderRecipient) external onlyOwner {
        if (_oldRemainderRecipient == address(0)) {
            revert FeeSplitter_NewRemainderRecipientCannotBeZero();
        }
        address oldRemainderRecipient = remainderRecipient;
        remainderRecipient = _oldRemainderRecipient;
        emit RemainderRecipientUpdated(oldRemainderRecipient, _oldRemainderRecipient);
    }

    /// @notice Updates the fee share percentage in basis points.
    ///
    /// @param _newFeeShareBP The new fee share percentage in basis points.
    function setFeeShareBP(uint256 _newFeeShareBP) external onlyOwner {
        if (_newFeeShareBP > BASIS_POINT_SCALE) {
            revert FeeSplitter_FeeShareBPExceeds100Percent();
        }
        uint256 oldShare = feeShareBP;
        feeShareBP = _newFeeShareBP;
        emit FeeShareBPUpdated(oldShare, _newFeeShareBP);
    }

    /// @notice Updates the fee disbursement interval.
    ///
    /// @param _newFeeDisbursementInterval The new fee disbursement interval in seconds.
    function setFeeDisbursementInterval(uint256 _newFeeDisbursementInterval) external onlyOwner {
        if (_newFeeDisbursementInterval < MIN_FEE_DISBURSEMENT_INTERVAL) {
            revert FeeSplitter_NewFeeDisbursementIntervalTooShort();
        }
        uint256 oldInterval = feeDisbursementInterval;
        feeDisbursementInterval = _newFeeDisbursementInterval;
        emit FeeDisbursementIntervalUpdated(oldInterval, _newFeeDisbursementInterval);
    }

    //////////////////////////////////////////////////////////////////////////////////////
    ///                               Internal Functions                               ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Withdraws fees from a FeeVault.
    ///
    /// @dev Withdrawal will only occur if the given FeeVault's balance is greater than or equal to the minimum
    ///      withdrawal amount.
    ///
    /// @param _feeVault The address of the FeeVault to withdraw from.
    function _feeVaultWithdrawal(address payable _feeVault) internal {
        if (FeeVault(_feeVault).withdrawalNetwork() != Types.WithdrawalNetwork.L2) {
            revert FeeSplitter_FeeVaultMustWithdrawToL2();
        }
        if (FeeVault(_feeVault).recipient() != address(this)) {
            revert FeeSplitter_FeeVaultMustWithdrawToFeeSplitter();
        }
        if (_feeVault.balance >= FeeVault(_feeVault).minWithdrawalAmount()) {
            FeeVault(_feeVault).withdraw();
        }
    }
}
