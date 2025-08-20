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
    error FeeSplitter_RevenueShareRecipientCannotBeZero();

    /// @notice Thrown when the fee recipient address is zero.
    error FeeSplitter_RevenueRemainderRecipientCannotBeZero();

    /// @notice Thrown when the fee disbursement interval is less than 24 hours.
    error FeeSplitter_FeeDisbursementIntervalTooShort();

    /// @notice Thrown when the disbursement interval has not been reached.
    error FeeSplitter_DisbursementIntervalNotReached();

    /// @notice Thrown when the FeeVault does not withdraw to L2.
    error FeeSplitter_FeeVaultMustWithdrawToL2();

    /// @notice Thrown when the FeeVault does not withdraw to FeeSplitter contract.
    error FeeSplitter_FeeVaultMustWithdrawToFeeSplitter();

    /// @notice Thrown when the new fee recipient address is zero.
    error FeeSplitter_NewRevenueShareRecipientCannotBeZero();

    /// @notice Thrown when the new fee recipient address is zero.
    error FeeSplitter_NewRevenueRemainderRecipientCannotBeZero();

    /// @notice Thrown when the new fee disbursement interval is less than 24 hours.
    error FeeSplitter_NewFeeDisbursementIntervalTooShort();

    /// @notice Thrown when the caller is not the ProxyAdmin owner.
    error FeeSplitter_OnlyProxyAdminOwner();

    /// @notice Thrown when sending funds to the fee recipient fails.
    error FeeSplitter_FailedToSendToRevenueShareRecipient();

    /// @notice Thrown when sending funds to the fee recipient fails.
    error FeeSplitter_FailedToSendToRevenueRemainderRecipient();

    /// @notice Thrown when receiving funds is disabled during payout.
    error FeeSplitter_ReceiveDisabledDuringPayout();

    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice The basis point scale which revenue share splits are denominated in.
    uint32 public constant BASIS_POINT_SCALE = 10_000;

    /// @notice The net revenue share percentage denominated in basis points.
    uint16 public constant NET_FEE_SHARE_BP = 1500;

    /// @notice The gross revenue share percentage denominated in basis points.
    uint16 public constant GROSS_FEE_SHARE_BP = 250;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint256 public constant MIN_FEE_DISBURSEMENT_INTERVAL = 24 hours;

    /// @notice The payout gate is open. This is the default state and allows for receiving funds.
    uint256 public constant _PAYOUT_OPEN = 1;

    /// @notice The payout gate is closed. This is the state when paying the recipients and disallows receiving funds.
    uint256 public constant _PAYOUT_CLOSED = 2;

    /// @notice Tracks whether the payout gate is currently closed (2) or open (1).
    ///         When closed, the receive() function is disabled to prevent reentrancy during payouts.
    uint256 public payoutGateState = _PAYOUT_OPEN;

    /// @notice An address that receives the fee split of the total fees disbursed. This share is the greater of net or
    /// gross revenue.
    address payable public revenueShareRecipient;

    /// @notice An address that receives the remainder of the total fees disbursed.
    address payable public revenueRemainderRecipient;

    /// @notice Tracks aggregate net fee revenue which is the sum of sequencer, base, and operator fees received by this
    /// contract.
    uint144 public netFeeRevenue;

    /// @notice The timestamp of the last disbursal.
    uint40 public lastDisbursementTime;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint40 public feeDisbursementInterval;

    /// @notice Emitted when fees are disbursed.
    /// @param revenueShareRecipient           The address which receives the fee share of the revenue.
    /// @param remainderRecipient              The address which receives the remainder of the revenue.
    /// @param revenueShareRecipientAmount      The amount of fees disbursed to the fee share recipient.
    /// @param revenueRemainderRecipientAmount  The amount of fees disbursed to the remainder recipient.
    event FeesDisbursed(
        address indexed revenueShareRecipient,
        address indexed remainderRecipient,
        uint256 revenueShareRecipientAmount,
        uint256 revenueRemainderRecipientAmount
    );

    /// @notice Emitted when fees are received from FeeVaults.
    /// @param sender The FeeVault that sent the fees.
    /// @param amount The amount of fees received.
    event FeesReceived(address indexed sender, uint256 amount);

    /// @notice Emitted when no fees are collected from FeeVaults at time of disbursement.
    event NoFeesCollected();

    /// @notice Emitted when the share recipient address is updated.
    /// @param oldRevenueShareRecipient The previous recipient A address.
    /// @param newRevenueShareRecipient The new recipient A address.
    event RevenueShareRecipientUpdated(
        address indexed oldRevenueShareRecipient, address indexed newRevenueShareRecipient
    );

    /// @notice Emitted when the remainder recipient address is updated.
    /// @param oldRevenueRemainderRecipient The previous recipient B address.
    /// @param newRevenueRemainderRecipient The new recipient B address.
    event RevenueRemainderRecipientUpdated(
        address indexed oldRevenueRemainderRecipient, address indexed newRevenueRemainderRecipient
    );

    /// @notice Emitted when the fee disbursement interval is updated.
    /// @param oldFeeDisbursementInterval The previous fee disbursement interval.
    /// @param newFeeDisbursementInterval The new fee disbursement interval.
    event FeeDisbursementIntervalUpdated(uint40 oldFeeDisbursementInterval, uint40 newFeeDisbursementInterval);

    /// @notice Emitted when the contract is initialized with its initial configuration.
    /// @param revenueShareRecipient     The address which receives the fee share of the revenue.
    /// @param revenueRemainderRecipient The address which receives the remainder of the revenue.
    /// @param feeDisbursementInterval   The minimum amount of time in seconds that must pass between fee disbursals.
    event Initialized(
        address payable revenueShareRecipient,
        address payable revenueRemainderRecipient,
        uint40 feeDisbursementInterval
    );

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with all required addresses and parameters.
    /// @dev This function can only be called once and must be called by the ProxyAdmin owner.
    /// @param _revenueShareRecipient      The address which receives the fee share of the revenue.
    /// @param _revenueRemainderRecipient  The address which receives the remainder of the revenue.
    /// @param _feeDisbursementInterval    The minimum amount of time in seconds that must pass between fee disbursals.
    function initialize(
        address payable _revenueShareRecipient,
        address payable _revenueRemainderRecipient,
        uint40 _feeDisbursementInterval
    )
        external
        onlyProxyAdminOwner
        initializer
    {
        if (_revenueShareRecipient == address(0)) {
            revert FeeSplitter_RevenueShareRecipientCannotBeZero();
        }
        if (_revenueRemainderRecipient == address(0)) {
            revert FeeSplitter_RevenueRemainderRecipientCannotBeZero();
        }
        if (_feeDisbursementInterval < MIN_FEE_DISBURSEMENT_INTERVAL) {
            revert FeeSplitter_FeeDisbursementIntervalTooShort();
        }

        revenueShareRecipient = _revenueShareRecipient;
        revenueRemainderRecipient = _revenueRemainderRecipient;
        feeDisbursementInterval = _feeDisbursementInterval;

        emit Initialized(
            _revenueShareRecipient,
            _revenueRemainderRecipient,
            _feeDisbursementInterval
        );
    }

    /// @notice Modifier that restricts access to the ProxyAdmin owner.
    modifier onlyProxyAdminOwner() {
        if (
            msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()
        ) {
            revert FeeSplitter_OnlyProxyAdminOwner();
        }
        _;
    }

    /// @dev Receives ETH fees withdrawn from L2 FeeVaults.
    receive() external payable virtual {
        if (payoutGateState == _PAYOUT_CLOSED) revert FeeSplitter_ReceiveDisabledDuringPayout();

        // Only count Sequencer, Base, and Operator fee vault deposits towards net fee revenue
        if (
            msg.sender == Predeploys.SEQUENCER_FEE_WALLET || msg.sender == Predeploys.BASE_FEE_VAULT
                || msg.sender == Predeploys.OPERATOR_FEE_VAULT
        ) {
            netFeeRevenue += uint144(msg.value);
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
        uint256 grossRevenue = address(this).balance;

        // Stop execution if no fees were collected
        if (grossRevenue == 0) {
            emit NoFeesCollected();
            return;
        }

        lastDisbursementTime = uint40(block.timestamp);

        // Calculate revenue shares
        uint256 netRevenueShare = (netFeeRevenue * NET_FEE_SHARE_BP) / BASIS_POINT_SCALE;

        uint256 grossRevenueShare = (grossRevenue * GROSS_FEE_SHARE_BP) / BASIS_POINT_SCALE;

        // Configured share is the max of net and gross revenue shares
        uint256 feeShare = netRevenueShare > grossRevenueShare ? netRevenueShare : grossRevenueShare;

        // close receive() for the payout window
        payoutGateState = _PAYOUT_CLOSED;

        if (!SafeCall.send({ _target: revenueShareRecipient, _gas: gasleft(), _value: feeShare })) {
            revert FeeSplitter_FailedToSendToRevenueShareRecipient();
        }

        uint256 remainder = address(this).balance;

        // Send the remainder to revenueRemainderRecipient
        if (!SafeCall.send({ _target: revenueRemainderRecipient, _gas: gasleft(), _value: remainder })) {
            revert FeeSplitter_FailedToSendToRevenueRemainderRecipient();
        }

        // Reset net fee revenue
        netFeeRevenue = 0;

        // reopen receive() after the payout window
        payoutGateState = _PAYOUT_OPEN;

        emit FeesDisbursed({
            revenueShareRecipient: revenueShareRecipient,
            remainderRecipient: revenueRemainderRecipient,
            revenueShareRecipientAmount: feeShare,
            revenueRemainderRecipientAmount: remainder
        });
    }

    /// @notice Updates the fee share recipient address.
    /// @param _newRevenueShareRecipient The new fee share recipient address.
    function setRevenueShareRecipient(address _newRevenueShareRecipient) external onlyProxyAdminOwner {
        if (_newRevenueShareRecipient == address(0)) {
            revert FeeSplitter_NewRevenueShareRecipientCannotBeZero();
        }
        address oldRevenueShareRecipient = revenueShareRecipient;
        revenueShareRecipient = payable(_newRevenueShareRecipient);
        emit RevenueShareRecipientUpdated(oldRevenueShareRecipient, _newRevenueShareRecipient);
    }

    /// @notice Updates the remainder recipient address.
    /// @param _newRevenueRemainderRecipient The new remainder recipient address.
    function setRevenueRemainderRecipient(address payable _newRevenueRemainderRecipient) external onlyProxyAdminOwner {
        if (_newRevenueRemainderRecipient == address(0)) {
            revert FeeSplitter_NewRevenueRemainderRecipientCannotBeZero();
        }
        address oldRevenueRemainderRecipient = revenueRemainderRecipient;
        revenueRemainderRecipient = _newRevenueRemainderRecipient;
        emit RevenueRemainderRecipientUpdated(oldRevenueRemainderRecipient, _newRevenueRemainderRecipient);
    }

    /// @notice Updates the fee disbursement interval.
    /// @param _newFeeDisbursementInterval The new fee disbursement interval in seconds.
    function setFeeDisbursementInterval(uint40 _newFeeDisbursementInterval) external onlyProxyAdminOwner {
        if (_newFeeDisbursementInterval < MIN_FEE_DISBURSEMENT_INTERVAL) {
            revert FeeSplitter_NewFeeDisbursementIntervalTooShort();
        }
        uint40 oldFeeDisbursementInterval = feeDisbursementInterval;
        feeDisbursementInterval = _newFeeDisbursementInterval;
        emit FeeDisbursementIntervalUpdated(oldFeeDisbursementInterval, _newFeeDisbursementInterval);
    }

    /// @notice Checks & Withdraws fees from a FeeVault.
    /// @dev Withdrawal will only occur if the vault is properly configured and if the FeeVault's balance is greater
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
