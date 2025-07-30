// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { FeeVault } from "src/L2/FeeVault.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";
import { Types } from "src/libraries/Types.sol";

// Interfaces
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

// OpenZeppelin
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:proxied
/// @custom:predeploy 0x4200000000000000000000000000000000000029
/// @title FeeRouter
/// @notice Withdraws funds from system FeeVault contracts, bridges appropriate funds to L1 for OP chain runner fees,
/// and
///         shares the rest of the revenue with Optimism. Supports different behavior based on chain type (OP Mainnet vs
/// other OP chains).
contract FeeRouter is ISemver, Initializable {
    //////////////////////////////////////////////////////////////////////////////////////
    ///                                   Errors                                       ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when the contract is already initialized.
    error FeeRouter_AlreadyInitialized();

    /// @notice Thrown when the L1 wallet address is zero.
    error FeeRouter_L1WalletCannotBeZero();

    /// @notice Thrown when the OP Fee Collector contract address is zero.
    error FeeRouter_FeeCollectorCannotBeZero();

    /// @notice Thrown when the OP Portal address is zero.
    error FeeRouter_OpPortalAddressCannotBeZero();

    /// @notice Thrown when the fee disbursement interval is less than 24 hours.
    error FeeRouter_FeeDisbursementIntervalTooShort();

    /// @notice Thrown when the L1 fee wallet share exceeds 100%.
    error FeeRouter_L1FeeWalletShareExceeds100Percent();

    /// @notice Thrown when the disbursement interval has not been reached.
    error FeeRouter_DisbursementIntervalNotReached();

    /// @notice Thrown when the FeeVault does not withdraw to L2.
    error FeeRouter_FeeVaultMustWithdrawToL2();

    /// @notice Thrown when the FeeVault does not withdraw to FeeRouter contract.
    error FeeRouter_FeeVaultMustWithdrawToFeeRouter();

    /// @notice Thrown when the new L1 wallet address is zero.
    error FeeRouter_NewL1WalletCannotBeZero();

    /// @notice Thrown when the new OP Fee Collector contract address is zero.
    error FeeRouter_NewFeeCollectorCannotBeZero();

    /// @notice Thrown when the new OP Portal address is zero.
    error FeeRouter_NewOpPortalAddressCannotBeZero();

    /// @notice Thrown when the new L1 fee wallet share exceeds 100%.
    error FeeRouter_NewL1FeeWalletShareExceeds100Percent();

    /// @notice Thrown when the new fee disbursement interval is less than 24 hours.
    error FeeRouter_NewFeeDisbursementIntervalTooShort();

    /// @notice Thrown when the caller is not the ProxyAdmin owner.
    error FeeRouter_OnlyProxyAdminOwner();

    /// @notice Thrown when sending funds to OP Fee Collector contract fails.
    error FeeRouter_FailedToSendToFeeCollector();

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                   Constants                                    ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice The basis point scale which revenue share splits are denominated in.
    uint32 public constant BASIS_POINT_SCALE = 10_000;

    /// @notice The minimum gas limit for the FeeRouter withdrawal transactions to L1.
    uint32 public constant WITHDRAWAL_MIN_GAS = 35_000;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint256 public constant MIN_FEE_DISBURSEMENT_INTERVAL = 24 hours;

    /// @notice The chain ID of the OP chain.
    uint256 public constant OP_CHAIN_ID = 10;

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                   Immutables                                   ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice The chain ID of the current network.
    uint256 public immutable BLOCK_CHAIN_ID;

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                    Storage                                     ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice The address of the L1 wallet that will receive the OP chain runner's share of fees.
    address payable public l1Wallet;

    /// @notice The address of the OP Fee Collector contract on OP Mainnet.
    address payable public feeCollector;

    /// @notice The address of the OP Portal contract.
    address payable public opPortalAddress;

    /// @notice The timestamp of the last disbursal.
    uint256 public lastDisbursementTime;

    /// @notice Tracks aggregate net fee revenue which is the sum of all fees received by this contract.
    uint256 public netFeeRevenue;

    /// @notice The L1 Fee Wallet share percentage denominated in basis points.
    uint256 public l1FeeWalletShare;

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    uint256 public feeDisbursementInterval;

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                     Events                                     ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when fees are disbursed.
    ///
    /// @param disbursementTime   The time of the disbursement.
    /// @param paidToL1Wallet     The amount of fees disbursed to L1 wallet.
    /// @param paidToFeeCollector The amount of fees disbursed to OP Fee Collector contract.
    /// @param totalFeesDisbursed The total amount of fees disbursed.
    event FeesDisbursed(
        uint256 indexed disbursementTime, uint256 paidToL1Wallet, uint256 paidToFeeCollector, uint256 totalFeesDisbursed
    );

    /// @notice Emitted when fees are received from FeeVaults.
    ///
    /// @param sender The FeeVault that sent the fees.
    /// @param amount The amount of fees received.
    event FeesReceived(address indexed sender, uint256 amount);

    /// @notice Emitted when no fees are collected from FeeVaults at time of disbursement.
    event NoFeesCollected();

    /// @notice Emitted when the L1 wallet is updated.
    ///
    /// @param oldWallet The previous L1 wallet address.
    /// @param newWallet The new L1 wallet address.
    event L1WalletUpdated(address indexed oldWallet, address indexed newWallet);

    /// @notice Emitted when the OP Fee Collector address is updated.
    ///
    /// @param oldContract The previous OP Fee Collector contract address.
    /// @param newContract The new OP Fee Collector contract address.
    event FeeCollectorUpdated(address indexed oldContract, address indexed newContract);

    /// @notice Emitted when the OP Portal address is updated.
    ///
    /// @param oldAddress The previous OP Portal address.
    /// @param newAddress The new OP Portal address.
    event OpPortalAddressUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when the L1 fee wallet share is updated.
    ///
    /// @param oldShare The previous L1 fee wallet share.
    /// @param newShare The new L1 fee wallet share.
    event L1FeeWalletShareUpdated(uint256 oldShare, uint256 newShare);

    /// @notice Emitted when the fee disbursement interval is updated.
    ///
    /// @param oldInterval The previous fee disbursement interval.
    /// @param newInterval The new fee disbursement interval.
    event FeeDisbursementIntervalUpdated(uint256 oldInterval, uint256 newInterval);

    /// @notice Emitted when the contract is initialized.
    ///
    /// @param l1Wallet                The L1 address which receives the remainder of the revenue.
    /// @param feeCollector        The address of the OP Fee Collector contract (only used on OP Mainnet).
    /// @param opPortalAddress         The address of the OP Portal contract.
    /// @param feeDisbursementInterval The minimum amount of time in seconds that must pass between fee disbursals.
    /// @param l1FeeWalletShare        The L1 Fee Wallet share percentage in basis points.
    event Initialized(
        address payable l1Wallet,
        address payable feeCollector,
        address payable opPortalAddress,
        uint256 feeDisbursementInterval,
        uint256 l1FeeWalletShare
    );

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                  Constructor                                   ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Constructor for the FeeRouter contract which validates and sets immutable variables.
    constructor() {
        BLOCK_CHAIN_ID = block.chainid;
        _disableInitializers();
    }

    /// @notice Initializes the contract with all required addresses and parameters.
    /// @dev This function can only be called once and must be called by the ProxyAdmin owner.
    ///
    /// @param _l1Wallet                The L1 address which receives the remainder of the revenue.
    /// @param _feeCollector        The address of the OP Fee Collector contract (only used on OP Mainnet).
    /// @param _opPortalAddress         The address of the OP Portal contract.
    /// @param _feeDisbursementInterval The minimum amount of time in seconds that must pass between fee disbursals.
    /// @param _l1FeeWalletShare        The L1 Fee Wallet share percentage in basis points.
    function initialize(
        address payable _l1Wallet,
        address payable _feeCollector,
        address payable _opPortalAddress,
        uint256 _feeDisbursementInterval,
        uint256 _l1FeeWalletShare
    )
        external
        initializer
        onlyOwner
    {
        if (_l1Wallet == address(0)) revert FeeRouter_L1WalletCannotBeZero();
        if (_feeCollector == address(0)) revert FeeRouter_FeeCollectorCannotBeZero();
        if (_opPortalAddress == address(0)) revert FeeRouter_OpPortalAddressCannotBeZero();
        if (_feeDisbursementInterval < MIN_FEE_DISBURSEMENT_INTERVAL) {
            revert FeeRouter_FeeDisbursementIntervalTooShort();
        }
        if (_l1FeeWalletShare > BASIS_POINT_SCALE) revert FeeRouter_L1FeeWalletShareExceeds100Percent();

        l1Wallet = _l1Wallet;
        feeCollector = _feeCollector;
        opPortalAddress = _opPortalAddress;
        feeDisbursementInterval = _feeDisbursementInterval;
        l1FeeWalletShare = _l1FeeWalletShare;

        emit Initialized(_l1Wallet, _feeCollector, _opPortalAddress, _feeDisbursementInterval, _l1FeeWalletShare);
    }

    //////////////////////////////////////////////////////////////////////////////////////
    ///                               Modifiers                                       ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Modifier that restricts access to the ProxyAdmin owner.
    modifier onlyOwner() {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert FeeRouter_OnlyProxyAdminOwner();
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

    /// @notice Withdraws funds from FeeVaults, sends Optimism their revenue share, and withdraws remaining funds to L1.
    ///
    /// @dev Implements revenue share business logic as follows:
    ///          Net Revenue             = sequencer FeeVault fee revenue + base FeeVault fee revenue
    ///          Gross Revenue           = Net Revenue + l1 FeeVault fee revenue + operator FeeVault fee revenue
    ///          Optimism Revenue Share  = Maximum of 15% of Net Revenue and 2.5% of Gross Revenue
    ///          L1 Wallet Revenue Share = Gross Revenue - Optimism Revenue Share
    function disburseFees() external {
        if (block.timestamp < lastDisbursementTime + feeDisbursementInterval) {
            revert FeeRouter_DisbursementIntervalNotReached();
        }

        // Sequencer and base FeeVaults will withdraw fees to the FeeRouter
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

        // Calculate L1 fee wallet share
        uint256 l1FeeWalletShareAmount = feeBalance * l1FeeWalletShare / BASIS_POINT_SCALE;

        // OP Fee Collector share is the remainder of the fee balance
        uint256 opFeeCollectorShare = feeBalance - l1FeeWalletShareAmount;

        if (BLOCK_CHAIN_ID == OP_CHAIN_ID) {
            // OP Mainnet: Send to OP Fee Collector contract
            if (!SafeCall.send({ _target: feeCollector, _gas: gasleft(), _value: opFeeCollectorShare })) {
                revert FeeRouter_FailedToSendToFeeCollector();
            }

            // Send to L1 wallet via L2ToL1MessagePasser
            IL2ToL1MessagePasser(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER)).initiateWithdrawal{
                value: l1FeeWalletShareAmount
            }({ _target: l1Wallet, _gasLimit: WITHDRAWAL_MIN_GAS, _data: hex"" });
        } else {
            // On an OPStack Chain, send funds to L1 wallet via L2ToL1MessagePasser
            IL2ToL1MessagePasser(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER)).initiateWithdrawal{
                value: l1FeeWalletShareAmount
            }({ _target: l1Wallet, _gasLimit: WITHDRAWAL_MIN_GAS, _data: hex"" });

            // Build data for deposit transaction to OP Fee Collector contract
            bytes memory data = abi.encodeCall(
                IOptimismPortal2.depositTransaction,
                (feeCollector, opFeeCollectorShare, WITHDRAWAL_MIN_GAS, false, hex"")
            );

            // Send funds to OP Fee Collector contract via L2ToL1MessagePasser
            IL2ToL1MessagePasser(payable(Predeploys.L2_TO_L1_MESSAGE_PASSER)).initiateWithdrawal{
                value: opFeeCollectorShare
            }({ _target: opPortalAddress, _gasLimit: WITHDRAWAL_MIN_GAS, _data: data });
        }

        emit FeesDisbursed({
            disbursementTime: lastDisbursementTime,
            paidToL1Wallet: l1FeeWalletShareAmount,
            paidToFeeCollector: opFeeCollectorShare,
            totalFeesDisbursed: feeBalance
        });
    }

    /// @notice Updates the L1 wallet address.
    ///
    /// @param _newL1Wallet The new L1 wallet address.
    function setL1Wallet(address _newL1Wallet) external onlyOwner {
        if (_newL1Wallet == address(0)) revert FeeRouter_NewL1WalletCannotBeZero();
        address oldWallet = l1Wallet;
        l1Wallet = payable(_newL1Wallet);
        emit L1WalletUpdated(oldWallet, _newL1Wallet);
    }

    /// @notice Updates the OP Fee Collector contract address.
    ///
    /// @param _newFeeCollector The new OP Fee Collector contract address.
    function setFeeCollector(address payable _newFeeCollector) external onlyOwner {
        if (_newFeeCollector == address(0)) revert FeeRouter_NewFeeCollectorCannotBeZero();
        address oldContract = feeCollector;
        feeCollector = _newFeeCollector;
        emit FeeCollectorUpdated(oldContract, _newFeeCollector);
    }

    /// @notice Updates the OP Portal address.
    ///
    /// @param _newOpPortalAddress The new OP Portal address.
    function setOpPortalAddress(address _newOpPortalAddress) external onlyOwner {
        if (_newOpPortalAddress == address(0)) revert FeeRouter_NewOpPortalAddressCannotBeZero();
        address oldAddress = opPortalAddress;
        opPortalAddress = payable(_newOpPortalAddress);
        emit OpPortalAddressUpdated(oldAddress, _newOpPortalAddress);
    }

    /// @notice Updates the L1 fee wallet share percentage.
    ///
    /// @param _newL1FeeWalletShare The new L1 fee wallet share percentage in basis points.
    function setL1FeeWalletShare(uint256 _newL1FeeWalletShare) external onlyOwner {
        if (_newL1FeeWalletShare > BASIS_POINT_SCALE) revert FeeRouter_NewL1FeeWalletShareExceeds100Percent();
        uint256 oldShare = l1FeeWalletShare;
        l1FeeWalletShare = _newL1FeeWalletShare;
        emit L1FeeWalletShareUpdated(oldShare, _newL1FeeWalletShare);
    }

    /// @notice Updates the fee disbursement interval.
    ///
    /// @param _newFeeDisbursementInterval The new fee disbursement interval in seconds.
    function setFeeDisbursementInterval(uint256 _newFeeDisbursementInterval) external onlyOwner {
        if (_newFeeDisbursementInterval < MIN_FEE_DISBURSEMENT_INTERVAL) {
            revert FeeRouter_NewFeeDisbursementIntervalTooShort();
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
            revert FeeRouter_FeeVaultMustWithdrawToL2();
        }
        if (FeeVault(_feeVault).RECIPIENT() != address(this)) {
            revert FeeRouter_FeeVaultMustWithdrawToFeeRouter();
        }
        if (_feeVault.balance >= FeeVault(_feeVault).MIN_WITHDRAWAL_AMOUNT()) {
            FeeVault(_feeVault).withdraw();
        }
    }
}
