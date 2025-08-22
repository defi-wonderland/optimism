// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Contracts
import { FeeVault } from "src/L2/FeeVault.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Types } from "src/libraries/Types.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";

// Interfaces
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ISharesCalculator } from "interfaces/L2/ISharesCalculator.sol";
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

    /// @notice The contract which determines the recipients and their weights for fee disbursement.
    ISharesCalculator public shareCalculator;

    /// @notice The timestamp of the last disbursal.
    uint128 public lastDisbursementTime;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint128 public feeDisbursementInterval;

    /// @notice Tracks the revenue received by each vault.
    mapping(address => uint256) internal _revenuePerVault;

    /// @notice Emitted when fees are received from FeeVaults.
    /// @param sender The FeeVault that sent the fees.
    /// @param amount The amount of fees received.
    event FeesReceived(address indexed sender, uint256 amount);

    /// @notice Emitted when no fees are collected from FeeVaults at time of disbursement.
    event NoFeesCollected();

    /// @notice Emitted when the fee disbursement interval is updated.
    /// @param oldFeeDisbursementInterval The previous fee disbursement interval.
    /// @param newFeeDisbursementInterval The new fee disbursement interval.
    event FeeDisbursementIntervalUpdated(uint128 oldFeeDisbursementInterval, uint128 newFeeDisbursementInterval);

    /// @notice Emitted when the contract is initialized with its initial configuration.
    /// @param shareCalculator           The share calculator contract.
    /// @param feeDisbursementInterval   The minimum amount of time in seconds that must pass between fee disbursals.
    event Initialized(ISharesCalculator shareCalculator, uint128 feeDisbursementInterval);

    /// @notice Emitted when fees are disbursed to the recipients.
    /// @param revenueShareRecipients The recipients of the fee share.
    /// @param feeShareValues The values of the fee share.
    /// @param grossRevenue The gross revenue before disbursement.
    event FeesDisbursed(address payable[] revenueShareRecipients, uint256[] feeShareValues, uint256 grossRevenue);

    /// @notice Emitted when the share calculator is updated.
    /// @param oldShareCalculator The old share calculator contract.
    /// @param newShareCalculator The new share calculator contract.
    event ShareCalculatorUpdated(address oldShareCalculator, address newShareCalculator);

    /// @notice Modifier that restricts access to the ProxyAdmin owner.
    modifier onlyProxyAdminOwner() {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert FeeSplitter_OnlyProxyAdminOwner();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with all required addresses and parameters.
    /// @dev This function can only be called once and must be called by the ProxyAdmin owner.
    /// @param _shareCalculator            The share calculator contract.
    /// @param _feeDisbursementInterval    The minimum amount of time in seconds that must pass between fee disbursals.
    function initialize(
        ISharesCalculator _shareCalculator,
        uint128 _feeDisbursementInterval
    )
        external
        onlyProxyAdminOwner
        initializer
    {
        if (address(_shareCalculator) == address(0)) revert FeeSplitter_ShareCalculatorCannotBeZero();

        shareCalculator = _shareCalculator;
        feeDisbursementInterval = _feeDisbursementInterval;

        emit Initialized(_shareCalculator, _feeDisbursementInterval);
    }

    /// @dev Receives ETH fees withdrawn from L2 FeeVaults.
    receive() external payable virtual {
        // TODO: Should we keep this function open, or enforce only allowed vaults to send fees?
        // TODO: Is there any edge case possible with this funciton allowing fees to be receied on a disbursement
        // context?
        _revenuePerVault[msg.sender] += msg.value;
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
        uint256 grossRevenue = address(this).balance;

        // Stop execution if no fees were collected
        if (grossRevenue == 0) {
            emit NoFeesCollected();
            return;
        }

        // Update the last disbursement time
        lastDisbursementTime = uint128(block.timestamp);

        // Call to the ShareCalculator to determine the fee share recipients, values, withdrawal networks, and data
        (address payable[] memory _revenueShareRecipients, uint256[] memory _feeShareValues) = shareCalculator
            .getRecipientsAndValues(
            _revenuePerVault[Predeploys.SEQUENCER_FEE_WALLET],
            _revenuePerVault[Predeploys.BASE_FEE_VAULT],
            _revenuePerVault[Predeploys.OPERATOR_FEE_VAULT],
            _revenuePerVault[Predeploys.L1_FEE_VAULT]
        );

        // Ensure the share calculator returned valid data
        if (_revenueShareRecipients.length == 0) revert FeeSplitter_FeeShareRecipientsEmpty();
        if (_revenueShareRecipients.length != _feeShareValues.length) {
            revert FeeSplitter_FeeShareRecipientsAndFeeShareValuesLengthMismatch();
        }

        // Reset individual fee revenue tracking
        _revenuePerVault[Predeploys.SEQUENCER_FEE_WALLET] = 0;
        _revenuePerVault[Predeploys.BASE_FEE_VAULT] = 0;
        _revenuePerVault[Predeploys.OPERATOR_FEE_VAULT] = 0;
        _revenuePerVault[Predeploys.L1_FEE_VAULT] = 0;

        // Loop through the recipients and their corresponding fee shares
        for (uint256 i; i < _revenueShareRecipients.length; i++) {
            address payable _recipient = _revenueShareRecipients[i];
            uint256 _feeShareValue = _feeShareValues[i];

            // Ensure the fee share is greater than zero
            if (_feeShareValue == 0) continue;

            /// NOTE: Contract can hold some balance after disbursement if the shares calculator is not perfect.
            SafeCall.send(address(_recipient), _feeShareValue);
        }

        emit FeesDisbursed({
            revenueShareRecipients: _revenueShareRecipients,
            feeShareValues: _feeShareValues,
            grossRevenue: grossRevenue
        });
    }

    /// @notice Updates the fee disbursement interval.
    /// @param _newFeeDisbursementInterval The new fee disbursement interval in seconds.
    function setFeeDisbursementInterval(uint128 _newFeeDisbursementInterval) external onlyProxyAdminOwner {
        uint128 oldFeeDisbursementInterval = feeDisbursementInterval;
        feeDisbursementInterval = _newFeeDisbursementInterval;
        emit FeeDisbursementIntervalUpdated(oldFeeDisbursementInterval, _newFeeDisbursementInterval);
    }

    /// @notice Updates the share calculator contract.
    /// @param _newShareCalculator The new share calculator contract.
    function setShareCalculator(ISharesCalculator _newShareCalculator) external onlyProxyAdminOwner {
        if (address(_newShareCalculator) == address(0)) revert FeeSplitter_ShareCalculatorCannotBeZero();
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
}
