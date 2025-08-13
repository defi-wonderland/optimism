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
    /// @notice Thrown when the fee recipient address is zero.
    error FeeSplitter_ConfiguredShareRecipientCannotBeZero();

    /// @notice Thrown when the fee recipient address is zero.
    error FeeSplitter_RemainderRecipientCannotBeZero();

    /// @notice Thrown when the fee disbursement interval is less than 24 hours.
    error FeeSplitter_FeeDisbursementIntervalTooShort();

    /// @notice Thrown when the fee share exceeds 100%.
    error FeeSplitter_FeeShareBPExceeds100Percent();

    /// @notice Thrown when the gross fee share exceeds 100%.
    error FeeSplitter_GrossFeeShareBPExceeds100Percent();

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

    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice The basis point scale which revenue share splits are denominated in.
    uint32 public constant BASIS_POINT_SCALE = 10_000;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint256 public constant MIN_FEE_DISBURSEMENT_INTERVAL = 24 hours;

    /// @notice An address that receives the fee split of the total fees disbursed
    address payable public configuredShareRecipient;

    /// @notice An address that receives the remainder of the total fees disbursed.
    address payable public remainderRecipient;

    /// @notice Tracks aggregate net fee revenue which is the sum of sequencer, base, and operator fees received by this
    /// contract.
    uint128 public netFeeRevenue;

    /// @notice The timestamp of the last disbursal.
    uint32 public lastDisbursementTime;

    /// @notice The net revenue share percentage denominated in basis points.
    uint32 public netFeeShareBP;

    /// @notice The gross revenue share percentage denominated in basis points.
    uint32 public grossFeeShareBP;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint32 public feeDisbursementInterval;

    /// @notice Emitted when fees are disbursed.
    /// @param disbursementTime                 The time of the disbursement.
    /// @param paidConfiguredShareRecipient     The amount of fees disbursed to the fee share recipient.
    /// @param paidToRemainderRecipient         The amount of fees disbursed to the remainder recipient.
    /// @param totalFeesDisbursed               The total amount of fees disbursed.
    event FeesDisbursed(
        uint256 indexed disbursementTime,
        uint256 paidConfiguredShareRecipient,
        uint256 paidToRemainderRecipient,
        uint256 totalFeesDisbursed
    );

    /// @notice Emitted when fees are received from FeeVaults.
    /// @param sender The FeeVault that sent the fees.
    /// @param amount The amount of fees received.
    event FeesReceived(address indexed sender, uint256 amount);

    /// @notice Emitted when no fees are collected from FeeVaults at time of disbursement.
    event NoFeesCollected();

    /// @notice Emitted when the share recipient address is updated.
    /// @param oldConfiguredShareRecipient The previous recipient A address.
    /// @param newConfiguredShareRecipient The new recipient A address.
    event ConfiguredShareRecipientUpdated(
        address indexed oldConfiguredShareRecipient, address indexed newConfiguredShareRecipient
    );

    /// @notice Emitted when the remainder recipient address is updated.
    /// @param oldRemainderRecipient The previous recipient B address.
    /// @param newRemainderRecipient The new recipient B address.
    event RemainderRecipientUpdated(address indexed oldRemainderRecipient, address indexed newRemainderRecipient);

    /// @notice Emitted when the net fee share in basis points is updated.
    /// @param oldNetFeeShareBP The previous net fee share in basis points.
    /// @param newNetFeeShareBP The new net fee share in basis points.
    event NetFeeShareBPUpdated(uint32 oldNetFeeShareBP, uint32 newNetFeeShareBP);

    /// @notice Emitted when the gross fee share in basis points is updated.
    /// @param oldGrossFeeShareBP The previous gross fee share in basis points.
    /// @param newGrossFeeShareBP The new gross fee share in basis points.
    event GrossFeeShareBPUpdated(uint32 oldGrossFeeShareBP, uint32 newGrossFeeShareBP);

    /// @notice Emitted when the fee disbursement interval is updated.
    /// @param oldInterval The previous fee disbursement interval.
    /// @param newInterval The new fee disbursement interval.
    event FeeDisbursementIntervalUpdated(uint32 oldInterval, uint32 newInterval);

    /// @notice Emitted when the contract is initialized.
    /// @param configuredShareRecipient  The address which receives the fee share of the revenue.
    /// @param remainderRecipient        The address which receives the remainder of the revenue.
    /// @param feeDisbursementInterval   The minimum amount of time in seconds that must pass between fee disbursals.
    /// @param netFeeShareBP             The net revenue share percentage in basis points.
    /// @param grossFeeShareBP           The gross revenue share percentage in basis points.
    event Initialized(
        address payable configuredShareRecipient,
        address payable remainderRecipient,
        uint32 feeDisbursementInterval,
        uint32 netFeeShareBP,
        uint32 grossFeeShareBP
    );

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with all required addresses and parameters.
    /// @dev This function can only be called once and must be called by the ProxyAdmin owner.
    /// @param _configuredShareRecipient   The address which receives the fee share of the revenue.
    /// @param _remainderRecipient         The address which receives the remainder of the revenue.
    /// @param _feeDisbursementInterval    The minimum amount of time in seconds that must pass between fee disbursals.
    /// @param _netFeeShareBP              The net revenue share percentage in basis points.
    /// @param _grossFeeShareBP            The gross revenue share percentage in basis points.
    function initialize(
        address payable _configuredShareRecipient,
        address payable _remainderRecipient,
        uint32 _feeDisbursementInterval,
        uint32 _netFeeShareBP,
        uint32 _grossFeeShareBP
    )
        external
        initializer
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
        if (_netFeeShareBP > BASIS_POINT_SCALE) {
            revert FeeSplitter_FeeShareBPExceeds100Percent();
        }
        if (_grossFeeShareBP > BASIS_POINT_SCALE) {
            revert FeeSplitter_GrossFeeShareBPExceeds100Percent();
        }

        configuredShareRecipient = _configuredShareRecipient;
        remainderRecipient = _remainderRecipient;
        feeDisbursementInterval = _feeDisbursementInterval;
        netFeeShareBP = _netFeeShareBP;
        grossFeeShareBP = _grossFeeShareBP;

        emit Initialized(
            _configuredShareRecipient, _remainderRecipient, _feeDisbursementInterval, _netFeeShareBP, _grossFeeShareBP
        );
    }

    /// @notice Modifier that restricts access to the ProxyAdmin owner.
    modifier onlyProxyAdminOwner() {
        if (
            IProxyAdmin(Predeploys.PROXY_ADMIN).owner() == address(0)
                || msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()
        ) {
            revert FeeSplitter_OnlyProxyAdminOwner();
        }
        _;
    }

    /// @dev Receives ETH fees withdrawn from L2 FeeVaults.
    receive() external payable virtual {
        // Only count Sequencer, Base, and Operator fee vault deposits towards net fee revenue
        if (
            msg.sender == Predeploys.SEQUENCER_FEE_WALLET || msg.sender == Predeploys.BASE_FEE_VAULT
                || msg.sender == Predeploys.OPERATOR_FEE_VAULT
        ) {
            netFeeRevenue += uint128(msg.value);
        }
        emit FeesReceived({ sender: msg.sender, amount: msg.value });
    }

    /// @notice Withdraws funds from FeeVaults, sends the fee share to the fee share recipient, and sends the remainder
    /// to the remainder recipient.
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

        lastDisbursementTime = uint32(block.timestamp);

        // Calculate revenue shares
        uint256 netRevenueShare = (netFeeRevenue * netFeeShareBP) / BASIS_POINT_SCALE; //@note casting overflow issues??

        uint256 grossRevenueShare = (feeBalance * grossFeeShareBP) / BASIS_POINT_SCALE;

        // Configured share is the max of net and gross revenue shares
        uint256 feeShare = netRevenueShare > grossRevenueShare ? netRevenueShare : grossRevenueShare;

        if (!SafeCall.send({ _target: configuredShareRecipient, _gas: gasleft(), _value: feeShare })) {
            revert FeeSplitter_FailedToSendToConfiguredShareRecipient();
        }

        // Send the remainder to remainderRecipient
        if (!SafeCall.send({ _target: remainderRecipient, _gas: gasleft(), _value: feeBalance - feeShare })) {
            revert FeeSplitter_FailedToSendToRemainderRecipient();
        }

        // Reset net fee revenue
        netFeeRevenue = 0;

        emit FeesDisbursed({
            disbursementTime: lastDisbursementTime,
            paidConfiguredShareRecipient: feeShare,
            paidToRemainderRecipient: feeBalance - feeShare,
            totalFeesDisbursed: feeBalance
        });
    }

    /// @notice Updates the fee share recipient address.
    /// @param _newConfiguredShareRecipient The new fee share recipient address.
    function setConfiguredShareRecipient(address _newConfiguredShareRecipient) external onlyProxyAdminOwner {
        if (_newConfiguredShareRecipient == address(0)) {
            revert FeeSplitter_NewConfiguredShareRecipientCannotBeZero();
        }
        address oldConfiguredShareRecipient = configuredShareRecipient;
        configuredShareRecipient = payable(_newConfiguredShareRecipient);
        emit ConfiguredShareRecipientUpdated(oldConfiguredShareRecipient, _newConfiguredShareRecipient);
    }

    /// @notice Updates the remainder recipient address.
    /// @param _newRemainderRecipient The new remainder recipient address.
    function setRemainderRecipient(address payable _newRemainderRecipient) external onlyProxyAdminOwner {
        if (_newRemainderRecipient == address(0)) {
            revert FeeSplitter_NewRemainderRecipientCannotBeZero();
        }
        address oldRemainderRecipient = remainderRecipient;
        remainderRecipient = _newRemainderRecipient;
        emit RemainderRecipientUpdated(oldRemainderRecipient, _newRemainderRecipient);
    }

    /// @notice Updates the net fee share percentage in basis points.
    /// @param _newNetFeeShareBP The new net fee share percentage in basis points.
    function setNetFeeShareBP(uint32 _newNetFeeShareBP) external onlyProxyAdminOwner {
        if (_newNetFeeShareBP > BASIS_POINT_SCALE) {
            revert FeeSplitter_FeeShareBPExceeds100Percent();
        }
        uint32 oldShare = netFeeShareBP;
        netFeeShareBP = _newNetFeeShareBP;
        emit NetFeeShareBPUpdated(oldShare, _newNetFeeShareBP);
    }

    /// @notice Updates the gross fee share percentage in basis points.
    /// @param _newGrossFeeShareBP The new gross fee share percentage in basis points.
    function setGrossFeeShareBP(uint32 _newGrossFeeShareBP) external onlyProxyAdminOwner {
        if (_newGrossFeeShareBP > BASIS_POINT_SCALE) {
            revert FeeSplitter_GrossFeeShareBPExceeds100Percent();
        }
        uint32 oldGrossShare = grossFeeShareBP;
        grossFeeShareBP = _newGrossFeeShareBP;
        emit GrossFeeShareBPUpdated(oldGrossShare, _newGrossFeeShareBP);
    }

    /// @notice Updates the fee disbursement interval.
    /// @param _newFeeDisbursementInterval The new fee disbursement interval in seconds.
    function setFeeDisbursementInterval(uint32 _newFeeDisbursementInterval) external onlyProxyAdminOwner {
        if (_newFeeDisbursementInterval < MIN_FEE_DISBURSEMENT_INTERVAL) {
            revert FeeSplitter_NewFeeDisbursementIntervalTooShort();
        }
        uint32 oldInterval = feeDisbursementInterval;
        feeDisbursementInterval = _newFeeDisbursementInterval;
        emit FeeDisbursementIntervalUpdated(oldInterval, _newFeeDisbursementInterval);
    }

    /// @notice Checks & Withdraws fees from a FeeVault.
    /// @dev Withdrawal will only occur if the vault are properly configured and if the FeeVault's balance is greater
    /// than or equal to the minimum
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
