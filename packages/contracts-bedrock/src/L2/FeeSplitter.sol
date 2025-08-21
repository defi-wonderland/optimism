// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Contracts
import { FeeVault } from "src/L2/FeeVault.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Types } from "src/libraries/Types.sol";

// Interfaces
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IShareCalculator } from "interfaces/L2/IShareCalculator.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";

// OpenZeppelin
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:proxied
/// @custom:predeploy 0x4200000000000000000000000000000000000029
/// @title FeeSplitter
/// @notice Withdraws funds from system FeeVault contracts, sends Optimism their revenue share, and
///         sends the remaining funds to the fee router.
contract FeeSplitter is ISemver, Initializable {
    /// @notice Thrown when the share calculator address is zero.
    error FeeSplitter_ShareCalculatorCannotBeZero();

    /// @notice Thrown when the fee disbursement interval is less than 24 hours.
    error FeeSplitter_FeeDisbursementIntervalTooShort();

    /// @notice Thrown when the disbursement interval has not been reached.
    error FeeSplitter_DisbursementIntervalNotReached();

    /// @notice Thrown when the number of fee share recipients and fee share values do not match.
    error FeeSplitter_FeeShareRecipientsAndFeeShareValuesLengthMismatch();

    /// @notice Thrown when the number of fee share recipients and withdrawal networks do not match.
    error FeeSplitter_FeeShareRecipientsAndWithdrawalNetworksLengthMismatch();

    /// @notice Thrown when the number of fee share recipients and data do not match.
    error FeeSplitter_FeeShareRecipientsAndDataLengthMismatch();

    /// @notice Thrown when the fee share recipients are empty.
    error FeeSplitter_FeeShareRecipientsEmpty();

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

    /// @notice The minimum gas limit for the L1 withdrawal transaction.
    uint32 internal constant WITHDRAWAL_MIN_GAS = 400_000;

    /// @notice The basis point scale which revenue share splits are denominated in.
    uint32 public constant BASIS_POINT_SCALE = 10_000;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint256 public constant MIN_FEE_DISBURSEMENT_INTERVAL = 24 hours;

    /// @notice The payout gate is open. This is the default state and allows for receiving funds.
    uint256 public constant _PAYOUT_OPEN = 1;

    /// @notice The payout gate is closed. This is the state when paying the recipients and disallows receiving funds.
    uint256 public constant _PAYOUT_CLOSED = 2;

    /// @notice Tracks whether the payout gate is currently closed (2) or open (1).
    ///         When closed, the receive() function is disabled to prevent reentrancy during payouts.
    uint256 public payoutGateState = _PAYOUT_OPEN;

    /// @notice The contract which determines the recipients and their weights for fee disbursement.
    IShareCalculator public shareCalculator;

    /// @notice Tracks sequencer fee revenue received by this contract.
    uint256 public sequencerFeeRevenue;

    /// @notice Tracks base fee revenue received by this contract.
    uint256 public baseFeeRevenue;

    /// @notice Tracks operator fee revenue received by this contract.
    uint256 public operatorFeeRevenue;

    /// @notice Tracks L1 fee revenue received by this contract.
    uint256 public l1FeeRevenue;

    /// @notice The timestamp of the last disbursal.
    uint40 public lastDisbursementTime;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint40 public feeDisbursementInterval;

    /// @notice Emitted when fees are received from FeeVaults.
    /// @param sender The FeeVault that sent the fees.
    /// @param amount The amount of fees received.
    event FeesReceived(address indexed sender, uint256 amount);

    /// @notice Emitted when no fees are collected from FeeVaults at time of disbursement.
    event NoFeesCollected();

    /// @notice Emitted when the fee disbursement interval is updated.
    /// @param oldFeeDisbursementInterval The previous fee disbursement interval.
    /// @param newFeeDisbursementInterval The new fee disbursement interval.
    event FeeDisbursementIntervalUpdated(uint40 oldFeeDisbursementInterval, uint40 newFeeDisbursementInterval);

    /// @notice Emitted when the contract is initialized with its initial configuration.
    /// @param shareCalculator           The share calculator contract.
    /// @param feeDisbursementInterval   The minimum amount of time in seconds that must pass between fee disbursals.
    event Initialized(IShareCalculator shareCalculator, uint40 feeDisbursementInterval);

    /// @notice Emitted when fees are disbursed to the recipients.
    /// @param revenueShareRecipients The recipients of the fee share.
    /// @param feeShareValues The values of the fee share.
    /// @param totalRevenue The total revenue before disbursement.
    event FeesDisbursed(address payable[] revenueShareRecipients, uint256[] feeShareValues, uint256 totalRevenue);

    /// @notice Emitted when the share calculator is updated.
    /// @param oldShareCalculator The old share calculator contract.
    /// @param newShareCalculator The new share calculator contract.
    event ShareCalculatorUpdated(address oldShareCalculator, address newShareCalculator);

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with all required addresses and parameters.
    /// @dev This function can only be called once and must be called by the ProxyAdmin owner.
    /// @param _shareCalculator            The share calculator contract.
    /// @param _feeDisbursementInterval    The minimum amount of time in seconds that must pass between fee disbursals.
    function initialize(
        IShareCalculator _shareCalculator,
        uint40 _feeDisbursementInterval
    )
        external
        onlyProxyAdminOwner
        initializer
    {
        if (address(_shareCalculator) == address(0)) {
            revert FeeSplitter_ShareCalculatorCannotBeZero();
        }
        if (_feeDisbursementInterval < MIN_FEE_DISBURSEMENT_INTERVAL) {
            revert FeeSplitter_FeeDisbursementIntervalTooShort();
        }

        shareCalculator = _shareCalculator;
        feeDisbursementInterval = _feeDisbursementInterval;

        emit Initialized(_shareCalculator, _feeDisbursementInterval);
    }

    /// @notice Modifier that restricts access to the ProxyAdmin owner.
    modifier onlyProxyAdminOwner() {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert FeeSplitter_OnlyProxyAdminOwner();
        }
        _;
    }

    /// @dev Receives ETH fees withdrawn from L2 FeeVaults.
    receive() external payable virtual {
        if (payoutGateState == _PAYOUT_CLOSED) revert FeeSplitter_ReceiveDisabledDuringPayout();

        // Track fees from each vault individually
        if (msg.sender == Predeploys.SEQUENCER_FEE_WALLET) {
            sequencerFeeRevenue += msg.value;
        } else if (msg.sender == Predeploys.BASE_FEE_VAULT) {
            baseFeeRevenue += msg.value;
        } else if (msg.sender == Predeploys.OPERATOR_FEE_VAULT) {
            operatorFeeRevenue += msg.value;
        } else if (msg.sender == Predeploys.L1_FEE_VAULT) {
            l1FeeRevenue += msg.value;
        }
        emit FeesReceived({ sender: msg.sender, amount: msg.value });
    }

    /// @notice Withdraws funds from FeeVaults and disburses them to the recipients.
    function disburseFees() external {
        if (block.timestamp < lastDisbursementTime + feeDisbursementInterval) {
            revert FeeSplitter_DisbursementIntervalNotReached();
        }

        // Pull fees into the contract
        _feeVaultWithdrawal(payable(Predeploys.SEQUENCER_FEE_WALLET));
        _feeVaultWithdrawal(payable(Predeploys.BASE_FEE_VAULT));
        _feeVaultWithdrawal(payable(Predeploys.L1_FEE_VAULT));
        _feeVaultWithdrawal(payable(Predeploys.OPERATOR_FEE_VAULT));

        // Total revenue is the sum of all fees
        uint256 totalRevenue = address(this).balance;

        // Stop execution if no fees were collected
        if (totalRevenue == 0) {
            emit NoFeesCollected();
            return;
        }

        // Update the last disbursement time
        lastDisbursementTime = uint40(block.timestamp);

        // close receive() for the payout window
        payoutGateState = _PAYOUT_CLOSED;

        // Call to the ShareCalculator to determine the fee share recipients, values, withdrawal networks, and data
        (
            address payable[] memory _revenueShareRecipients,
            uint256[] memory _feeShareValues,
            Types.WithdrawalNetwork[] memory _withdrawalNetworks,
            bytes[] memory _data
        ) = shareCalculator.getRecipientsAndValues(
            sequencerFeeRevenue, baseFeeRevenue, operatorFeeRevenue, l1FeeRevenue
        );

        // Ensure the share calculator returned valid data
        if (_revenueShareRecipients.length == 0) {
            revert FeeSplitter_FeeShareRecipientsEmpty();
        }
        if (_revenueShareRecipients.length != _feeShareValues.length) {
            revert FeeSplitter_FeeShareRecipientsAndFeeShareValuesLengthMismatch();
        }
        if (_revenueShareRecipients.length != _withdrawalNetworks.length) {
            revert FeeSplitter_FeeShareRecipientsAndWithdrawalNetworksLengthMismatch();
        }
        if (_revenueShareRecipients.length != _data.length) {
            revert FeeSplitter_FeeShareRecipientsAndDataLengthMismatch();
        }

        // Loop through the recipients and their corresponding fee shares
        for (uint256 i = 0; i < _revenueShareRecipients.length; i++) {
            address payable _recipient = _revenueShareRecipients[i];
            uint256 _feeShareValue = _feeShareValues[i];

            // Ensure the recipient is not zero and the fee share is greater than zero
            if (_recipient == address(0) || _feeShareValue == 0) {
                continue;
            }

            // On the last recipient send the remainder of the balance so no funds are left in this contract
            if (i == _revenueShareRecipients.length - 1) {
                uint256 _remainder = address(this).balance;
                if (_withdrawalNetworks[i] == Types.WithdrawalNetwork.L2) {
                    _sendL2(_recipient, _remainder, _data[i]);
                } else {
                    _sendL1(_recipient, _remainder, _data[i]);
                }
            }

            // Send the fee share to the recipient
            if (_withdrawalNetworks[i] == Types.WithdrawalNetwork.L2) {
                _sendL2(_recipient, _feeShareValue, _data[i]);
            } else {
                _sendL1(_recipient, _feeShareValue, _data[i]);
            }
        }

        // Reset individual fee revenue tracking
        sequencerFeeRevenue = 0;
        baseFeeRevenue = 0;
        operatorFeeRevenue = 0;
        l1FeeRevenue = 0;

        // reopen receive() after the payout window
        payoutGateState = _PAYOUT_OPEN;

        emit FeesDisbursed({
            revenueShareRecipients: _revenueShareRecipients,
            feeShareValues: _feeShareValues,
            totalRevenue: totalRevenue
        });
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

    /// @notice Updates the share calculator contract.
    /// @param _newShareCalculator The new share calculator contract.
    function setShareCalculator(IShareCalculator _newShareCalculator) external onlyProxyAdminOwner {
        if (address(_newShareCalculator) == address(0)) {
            revert FeeSplitter_ShareCalculatorCannotBeZero();
        }
        address oldShareCalculator = address(shareCalculator);
        shareCalculator = _newShareCalculator;
        emit ShareCalculatorUpdated(oldShareCalculator, address(_newShareCalculator));
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

    /// @notice Sends funds to the recipient on L2.
    /// @param _recipient The address of the recipient on L2.
    /// @param _amount The amount of funds to send.
    /// @param _data The data to send to the recipient.
    function _sendL2(address payable _recipient, uint256 _amount, bytes memory _data) internal {
        (bool _success,) = _recipient.call{ value: _amount }(_data);
        if (!_success) {
            revert FeeSplitter_FailedToSendToRevenueShareRecipient();
        }
    }

    /// @notice Sends funds to the recipient on L1.
    /// @param _recipient The address of the recipient on L1.
    /// @param _amount The amount of funds to send.
    /// @param _data The data to send to the recipient.
    function _sendL1(address payable _recipient, uint256 _amount, bytes memory _data) internal {
        IL2ToL1MessagePasser(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER)).initiateWithdrawal{ value: _amount }({
            _target: _recipient,
            _gasLimit: WITHDRAWAL_MIN_GAS,
            _data: _data
        });
    }
}
