// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFeeRouter {
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
    ///                                   Constants                                    ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @custom:semver 1.0.0
    function version() external view returns (string memory);

    /// @notice The basis point scale which revenue share splits are denominated in.
    function BASIS_POINT_SCALE() external view returns (uint32);

    /// @notice The minimum gas limit for the FeeRouter withdrawal transactions to L1.
    function WITHDRAWAL_MIN_GAS() external view returns (uint32);

    /// @notice The chain ID of the OP chain.
    function OP_CHAIN_ID() external view returns (uint256);

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                   Immutables                                   ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice Getter for the block chain ID.
    /// @return The chain ID of the current network.
    function BLOCK_CHAIN_ID() external view returns (uint256);

    //////////////////////////////////////////////////////////////////////////////////////
    ///                                    Storage                                     ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @notice The address of the L1 wallet that will receive the OP chain runner's share of fees.
    function l1Wallet() external view returns (address payable);

    /// @notice The address of the OP Fee Collector contract on OP Mainnet.
    function feeCollector() external view returns (address payable);

    /// @notice The address of the OP Portal contract.
    function opPortalAddress() external view returns (address payable);

    /// @notice The timestamp of the last disbursal.
    function lastDisbursementTime() external view returns (uint256);

    /// @notice Tracks aggregate net fee revenue which is the sum of all fees received by this contract.
    function netFeeRevenue() external view returns (uint256);

    /// @notice The L1 Fee Wallet share percentage denominated in basis points.
    function l1FeeWalletShare() external view returns (uint256);

    /// @notice The minimum amount of time in seconds that must pass between fee disbursal.
    function feeDisbursementInterval() external view returns (uint256);

    /// @notice Whether the contract has been initialized.
    function initialized() external view returns (bool);

    //////////////////////////////////////////////////////////////////////////////////////
    ///                               External Functions                               ///
    //////////////////////////////////////////////////////////////////////////////////////

    /// @dev Receives ETH fees withdrawn from L2 FeeVaults.
    /// @dev Will revert if ETH is not sent from L2 FeeVaults.
    receive() external payable;

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
        external;

    /// @notice Withdraws funds from FeeVaults, sends Optimism their revenue share, and withdraws remaining funds to L1.
    ///
    /// @dev Implements revenue share business logic as follows:
    ///          Net Revenue             = sequencer FeeVault fee revenue + base FeeVault fee revenue
    ///          Gross Revenue           = Net Revenue + l1 FeeVault fee revenue + operator FeeVault fee revenue
    ///          Optimism Revenue Share  = Maximum of 15% of Net Revenue and 2.5% of Gross Revenue
    ///          L1 Wallet Revenue Share = Gross Revenue - Optimism Revenue Share
    function disburseFees() external;

    /// @notice Updates the L1 wallet address.
    ///
    /// @param _newL1Wallet The new L1 wallet address.
    function setL1Wallet(address _newL1Wallet) external;

    /// @notice Updates the OP Fee Collector contract address.
    ///
    /// @param _newFeeCollector The new OP Fee Collector contract address.
    function setFeeCollector(address payable _newFeeCollector) external;

    /// @notice Updates the OP Portal address.
    ///
    /// @param _newOpPortalAddress The new OP Portal address.
    function setOpPortalAddress(address _newOpPortalAddress) external;

    /// @notice Updates the L1 fee wallet share percentage.
    ///
    /// @param _newL1FeeWalletShare The new L1 fee wallet share percentage in basis points.
    function setL1FeeWalletShare(uint256 _newL1FeeWalletShare) external;

    /// @notice Updates the fee disbursement interval.
    ///
    /// @param _newFeeDisbursementInterval The new fee disbursement interval in seconds.
    function setFeeDisbursementInterval(uint256 _newFeeDisbursementInterval) external;

    /// @notice Constructor function for the interface.
    function __constructor__() external;
}