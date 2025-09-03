// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Types } from "src/libraries/Types.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";

// Interfaces
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ISharesCalculator } from "interfaces/L2/ISharesCalculator.sol";
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";

// OpenZeppelin
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:proxied
/// @custom:predeploy 0x4200000000000000000000000000000000000029
/// @title FeeSplitter
/// @notice Withdraws funds from system FeeVault contracts, sends Optimism their revenue share, and
///         sends the remaining funds to the fee router.
contract FeeSplitter is ISemver, Initializable {
    /// @notice Thrown when the share calculator address is zero.
    error FeeSplitter_SharesCalculatorCannotBeZero();

    /// @notice Thrown when the disbursement interval has not been reached.
    error FeeSplitter_DisbursementIntervalNotReached();

    /// @notice Thrown when the fee share recipients are empty.
    error FeeSplitter_FeeShareInfoEmpty();

    /// @notice Thrown when no fees are collected from vaults during disbursement.
    error FeeSplitter_NoFeesCollected();

    /// @notice Thrown when the FeeVault does not withdraw to L2.
    error FeeSplitter_FeeVaultMustWithdrawToL2();

    /// @notice Thrown when the FeeVault does not withdraw to FeeSplitter contract.
    error FeeSplitter_FeeVaultMustWithdrawToFeeSplitter();

    /// @notice Thrown when the caller is not the ProxyAdmin owner.
    error FeeSplitter_OnlyProxyAdminOwner();

    /// @notice Thrown when sending funds to the fee recipient fails.
    error FeeSplitter_FailedToSendToRevenueShareRecipient();

    /// @notice Thrown when the sharesCalculator returns malformed output.
    error FeeSplitter_SharesCalculatorMalformedOutput();

    /// @notice Thrown when receiving ETH is attempted outside of a disbursement window.
    error FeeSplitter_ReceiveWindowClosed();

    /// @notice Thrown when a sender other than an approved FeeVault attempts to send ETH.
    error FeeSplitter_SenderNotApprovedVault();

    /// @notice Transient storage slot key for disbursement-in-progress flag.
    ///         Equal to bytes32(uint256(keccak256("feesplitter.isDisbursing")) - 1)
    bytes32 internal constant _FEE_SPLITTER_IS_DISBURSING_SLOT =
        0xe3007e9730850b5618eacb0537bef0cf0f1600267ae8549e472449d77b731e45;

    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice The contract which determines the recipients and their weights for fee disbursement.
    ISharesCalculator public sharesCalculator;

    /// @notice The timestamp of the last disbursal.
    uint128 public lastDisbursementTime;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint128 public feeDisbursementInterval;

    /// @notice Emitted when fees are received from FeeVaults.
    /// @param sender The FeeVault that sent the fees.
    /// @param amount The amount of fees received.
    event FeesReceived(address indexed sender, uint256 amount);

    /// @notice Emitted when the fee disbursement interval is updated.
    /// @param oldFeeDisbursementInterval The previous fee disbursement interval.
    /// @param newFeeDisbursementInterval The new fee disbursement interval.
    event FeeDisbursementIntervalUpdated(uint128 oldFeeDisbursementInterval, uint128 newFeeDisbursementInterval);

    /// @notice Emitted when the contract is initialized with its initial configuration.
    /// @param sharesCalculator           The share calculator contract.
    /// @param feeDisbursementInterval   The minimum amount of time in seconds that must pass between fee disbursals.
    event Initialized(ISharesCalculator sharesCalculator, uint128 feeDisbursementInterval);

    /// @notice Emitted when fees are disbursed to the recipients.
    /// @param shareInfo The recipients of the fee share.
    /// @param grossRevenue The gross revenue before disbursement.
    event FeesDisbursed(ISharesCalculator.ShareInfo[] shareInfo, uint256 grossRevenue);

    /// @notice Emitted when the share calculator is updated.
    /// @param oldSharesCalculator The old share calculator contract.
    /// @param newSharesCalculator The new share calculator contract.
    event SharesCalculatorUpdated(address oldSharesCalculator, address newSharesCalculator);

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with all required addresses and parameters.
    /// @dev This function can only be called once and must be called by the ProxyAdmin owner.
    /// @param _sharesCalculator            The share calculator contract.
    /// @param _feeDisbursementInterval    The minimum amount of time in seconds that must pass between fee disbursals.
    function initialize(ISharesCalculator _sharesCalculator, uint128 _feeDisbursementInterval) external initializer {
        sharesCalculator = _sharesCalculator;
        feeDisbursementInterval = _feeDisbursementInterval;

        emit Initialized(_sharesCalculator, _feeDisbursementInterval);
    }

    /// @dev Receives ETH fees withdrawn from L2 FeeVaults.
    receive() external payable virtual {
        if (!_isTransientDisbursing()) revert FeeSplitter_ReceiveWindowClosed();
        if (
            msg.sender != Predeploys.SEQUENCER_FEE_WALLET && msg.sender != Predeploys.BASE_FEE_VAULT
                && msg.sender != Predeploys.L1_FEE_VAULT && msg.sender != Predeploys.OPERATOR_FEE_VAULT
        ) {
            revert FeeSplitter_SenderNotApprovedVault();
        }
        emit FeesReceived({ sender: msg.sender, amount: msg.value });
    }

    /// @notice Withdraws funds from FeeVaults and disburses them to the recipients.
    function disburseFees() external {
        if (block.timestamp < lastDisbursementTime + feeDisbursementInterval) {
            revert FeeSplitter_DisbursementIntervalNotReached();
        }

        // Pull fees into the contract
        _setTransientDisbursing(true);
        uint256 _sequencerFees = _feeVaultWithdrawal(payable(Predeploys.SEQUENCER_FEE_WALLET));
        uint256 _baseFees = _feeVaultWithdrawal(payable(Predeploys.BASE_FEE_VAULT));
        uint256 _l1Fees = _feeVaultWithdrawal(payable(Predeploys.L1_FEE_VAULT));
        uint256 _operatorFees = _feeVaultWithdrawal(payable(Predeploys.OPERATOR_FEE_VAULT));
        _setTransientDisbursing(false);

        uint256 _grossRevenue = _sequencerFees + _baseFees + _operatorFees + _l1Fees;

        // Revert if no fees were collected
        if (_grossRevenue == 0) {
            revert FeeSplitter_NoFeesCollected();
        }

        // Update the last disbursement time
        lastDisbursementTime = uint128(block.timestamp);

        // Call to the sharesCalculator to determine the fee share recipients, values, withdrawal networks, and data
        // DoS risk if array size is too large.
        (ISharesCalculator.ShareInfo[] memory _shareInfo) =
            sharesCalculator.getRecipientsAndValues(_sequencerFees, _baseFees, _operatorFees, _l1Fees);

        // Ensure the share calculator returned valid data
        if (_shareInfo.length == 0) revert FeeSplitter_FeeShareInfoEmpty();

        // Loop through the recipients and their corresponding fee shares
        uint256 _totalFeesDisbursed;
        for (uint256 i; i < _shareInfo.length; i++) {
            address payable _recipient = _shareInfo[i].recipient;
            uint256 _feeShareValue = _shareInfo[i].value;

            // Ensure the fee share is greater than zero
            if (_feeShareValue == 0) continue;

            bool success = SafeCall.send(address(_recipient), _feeShareValue);
            if (!success) {
                revert FeeSplitter_FailedToSendToRevenueShareRecipient();
            }
            _totalFeesDisbursed += _feeShareValue;
        }

        // Ensure the total fees disbursed is equal to the gross revenue
        /// NOTE: Contract can hold some balance after disbursement if tokens are force sent (using SELFDESTRUCT).
        if (_totalFeesDisbursed != _grossRevenue) revert FeeSplitter_SharesCalculatorMalformedOutput();

        emit FeesDisbursed({ shareInfo: _shareInfo, grossRevenue: _grossRevenue });
    }

    /// @notice Updates the fee disbursement interval. Only callable by the ProxyAdmin owner.
    /// @param _newFeeDisbursementInterval The new fee disbursement interval in seconds.
    function setFeeDisbursementInterval(uint128 _newFeeDisbursementInterval) external {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert FeeSplitter_OnlyProxyAdminOwner();
        }
        uint128 oldFeeDisbursementInterval = feeDisbursementInterval;
        feeDisbursementInterval = _newFeeDisbursementInterval;
        emit FeeDisbursementIntervalUpdated(oldFeeDisbursementInterval, _newFeeDisbursementInterval);
    }

    /// @notice Updates the share calculator contract. Only callable by the ProxyAdmin owner.
    /// @param _newSharesCalculator The new share calculator contract.
    function setSharesCalculator(ISharesCalculator _newSharesCalculator) external {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert FeeSplitter_OnlyProxyAdminOwner();
        }
        if (address(_newSharesCalculator) == address(0)) revert FeeSplitter_SharesCalculatorCannotBeZero();
        address oldSharesCalculator = address(sharesCalculator);
        sharesCalculator = _newSharesCalculator;
        emit SharesCalculatorUpdated(oldSharesCalculator, address(_newSharesCalculator));
    }

    /// @notice Checks & Withdraws fees from a FeeVault.
    /// @dev Withdrawal will only occur if the vault is properly configured and if the FeeVault's balance is greater
    /// than or equal to the minimum
    /// @param _feeVault The address of the FeeVault to withdraw from.
    /// @return value_ The amount of ETH that was withdrawn from the vault.
    function _feeVaultWithdrawal(address payable _feeVault) internal returns (uint256 value_) {
        if (IFeeVault(_feeVault).withdrawalNetwork() != Types.WithdrawalNetwork.L2) {
            revert FeeSplitter_FeeVaultMustWithdrawToL2();
        }
        if (IFeeVault(_feeVault).recipient() != address(this)) {
            revert FeeSplitter_FeeVaultMustWithdrawToFeeSplitter();
        }
        if (_feeVault.balance >= IFeeVault(_feeVault).minWithdrawalAmount()) {
            value_ = IFeeVault(_feeVault).withdraw();
        }
    }

    /// @notice Sets the transient disbursing flag.
    /// @param _enabled True to enable, false to disable.
    function _setTransientDisbursing(bool _enabled) internal {
        assembly {
            tstore(_FEE_SPLITTER_IS_DISBURSING_SLOT, _enabled)
        }
    }

    /// @notice Reads the transient disbursing flag.
    /// @return isDisbursing_ True if disbursement is in progress.
    function _isTransientDisbursing() internal view returns (bool isDisbursing_) {
        assembly {
            isDisbursing_ := tload(_FEE_SPLITTER_IS_DISBURSING_SLOT)
        }
    }
}
