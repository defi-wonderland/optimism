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

    /// @notice Thrown when the fee recipient A address is zero.
    error FeeSplitter_FeeRecipientACannotBeZero();

    /// @notice Thrown when the fee recipient B address is zero.
    error FeeSplitter_FeeRecipientBCannotBeZero();

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

    /// @notice Thrown when the new fee recipient A address is zero.
    error FeeSplitter_NewFeeRecipientACannotBeZero();

    /// @notice Thrown when the new fee recipient B address is zero.
    error FeeSplitter_NewFeeRecipientBCannotBeZero();

    /// @notice Thrown when the new fee disbursement interval is less than 24 hours.
    error FeeSplitter_NewFeeDisbursementIntervalTooShort();

    /// @notice Thrown when the caller is not the ProxyAdmin owner.
    error FeeSplitter_OnlyProxyAdminOwner();

    /// @notice Thrown when sending funds to the fee recipient A fails.
    error FeeSplitter_FailedToSendToFeeRecipientA();

    /// @notice Thrown when sending funds to the fee recipient B fails.
    error FeeSplitter_FailedToSendToFeeRecipientB();

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

    /// @notice An address that recieves the fee split of the total fees dispursed
    address payable public feeRecipientA;

    /// @notice An address that recieves the remainder of the total fees disbursed.
    address payable public feeRecipientB;

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
    ///                                  Constructor                                   ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Constructor for the FeeSplitter contract which validates and sets immutable variables.
    constructor() {
        _disableInitializers();
    }

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
        external
        initializer
        onlyOwner
    {
        if (_feeRecipientA == address(0)) revert FeeSplitter_FeeRecipientACannotBeZero();
        if (_feeRecipientB == address(0)) revert FeeSplitter_FeeRecipientBCannotBeZero();
        if (_feeDisbursementInterval < MIN_FEE_DISBURSEMENT_INTERVAL) {
            revert FeeSplitter_FeeDisbursementIntervalTooShort();
        }
        if (_feeShareBP > BASIS_POINT_SCALE) revert FeeSplitter_FeeShareBPExceeds100Percent();

        feeRecipientA = _feeRecipientA;
        feeRecipientB = _feeRecipientB;
        feeDisbursementInterval = _feeDisbursementInterval;
        feeShareBP = _feeShareBP;

        emit Initialized(_feeRecipientA, _feeRecipientB, _feeDisbursementInterval, _feeShareBP);
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

    /// @notice Withdraws funds from FeeVaults, sends the fee share to the fee recipient A, and sends the remainder to the
    /// fee recipient B.
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
        uint256 feeShare = feeBalance * feeShareBP / BASIS_POINT_SCALE;

        if (!SafeCall.send({ _target: feeRecipientA, _gas: gasleft(), _value: feeShare })) {
            revert FeeSplitter_FailedToSendToFeeRecipientA();
        }

        // Send the remainder to feeRecipientB
        if (!SafeCall.send({ _target: feeRecipientB, _gas: gasleft(), _value: feeBalance - feeShare })) {
            revert FeeSplitter_FailedToSendToFeeRecipientB();
        }

        emit FeesDisbursed({
            disbursementTime: lastDisbursementTime,
            paidToRecipientA: feeShare,
            paidToRecipientB: feeBalance - feeShare,
            totalFeesDisbursed: feeBalance
        });
    }

    /// @notice Updates the fee recipient A address.
    ///
    /// @param _newFeeRecipientA The new fee recipient A address.
    function setFeeRecipientA(address _newFeeRecipientA) external onlyOwner {
        if (_newFeeRecipientA == address(0)) revert FeeSplitter_NewFeeRecipientACannotBeZero();
        address oldFeeRecipientA = feeRecipientA;
        feeRecipientA = payable(_newFeeRecipientA);
        emit FeeRecipientAUpdated(oldFeeRecipientA, _newFeeRecipientA);
    }

    /// @notice Updates the fee recipient B address.
    ///
    /// @param _newFeeRecipientB The new fee recipient B address.
    function setFeeRecipientB(address payable _newFeeRecipientB) external onlyOwner {
        if (_newFeeRecipientB == address(0)) revert FeeSplitter_NewFeeRecipientBCannotBeZero();
        address oldFeeRecipientB = feeRecipientB;
        feeRecipientB = _newFeeRecipientB;
        emit FeeRecipientBUpdated(oldFeeRecipientB, _newFeeRecipientB);
    }

    /// @notice Updates the fee share percentage in basis points.
    ///
    /// @param _newFeeShareBP The new fee share percentage in basis points.
    function setFeeShareBP(uint256 _newFeeShareBP) external onlyOwner {
        if (_newFeeShareBP > BASIS_POINT_SCALE) revert FeeSplitter_FeeShareBPExceeds100Percent();
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
        if (FeeVault(_feeVault).WITHDRAWAL_NETWORK() != Types.WithdrawalNetwork.L2) {
            revert FeeSplitter_FeeVaultMustWithdrawToL2();
        }
        if (FeeVault(_feeVault).RECIPIENT() != address(this)) {
            revert FeeSplitter_FeeVaultMustWithdrawToFeeSplitter();
        }
        if (_feeVault.balance >= FeeVault(_feeVault).MIN_WITHDRAWAL_AMOUNT()) {
            FeeVault(_feeVault).withdraw();
        }
    }
}
