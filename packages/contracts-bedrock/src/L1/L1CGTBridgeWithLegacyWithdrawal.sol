// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { L1CGTBridge } from "./L1CGTBridge.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { SecureMerkleTrie } from "src/libraries/trie/SecureMerkleTrie.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interfaces
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { L2CGTBridge } from "src/L2/L2CGTBridge.sol";

/// @custom:proxied true
/// @title L1CGTBridgeWithLegacyWithdrawal
/// @notice Extension of L1CGTBridge that includes functionality for handling legacy
///         withdrawals from before CGT migration, bridge management controls, and trusted state
///         management.
contract L1CGTBridgeWithLegacyWithdrawal is L1CGTBridge {
    using SafeERC20 for IERC20;

    /// @notice Storage slot for the trusted L2ToL1MessagePasser storage root
    bytes32 private _trustedMessagePasserStorageRoot;

    /// @notice Flag indicating if the trusted state has been set.
    bool private _trustedStateSet;

    /// @notice Flag indicating if deposits are enabled.
    bool private _depositsEnabled;

    /// @notice Flag indicating if withdrawals are enabled.
    bool private _withdrawalsEnabled;

    /// @notice Mapping of withdrawal hashes to proof submitters to finalization status.
    mapping(bytes32 => mapping(address => bool)) public provenLegacyWithdrawals;

    /// @notice Mapping of withdrawal hashes to finalization status.
    mapping(bytes32 => bool) public finalizedLegacyWithdrawals;

    /// @notice Reference to the OptimismPortal2 contract.
    /// @custom:network-specific
    IOptimismPortal2 public optimismPortal;

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[50] private __gap;

    /// @notice Thrown when trying to set trusted state more than once.
    error TrustedStateAlreadySet();

    /// @notice Thrown when trying to use legacy functions before setting trusted state.
    error TrustedStateNotSet();

    /// @notice Thrown when deposits are disabled.
    error DepositsDisabled();

    /// @notice Thrown when withdrawals are disabled.
    error WithdrawalsDisabled();

    /// @notice Thrown when withdrawal has already been finalized.
    error WithdrawalAlreadyFinalized();

    /// @notice Thrown when withdrawal has not been proven.
    error WithdrawalNotProven();

    /// @notice Thrown when trying to finalize a withdrawal with zero value.
    error InvalidWithdrawalValue();

    /// @notice Thrown when withdrawal target is the CGT token contract.
    error InvalidWithdrawalTarget();

    /// @notice Thrown when trusted root is zero.
    error InvalidTrustedRoot();

    /// @notice Emitted when a legacy withdrawal is proven.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param from           Address of the sender.
    /// @param to             Address of the receiver.
    event WithdrawalProven(bytes32 indexed withdrawalHash, address indexed from, address indexed to);

    /// @notice Emitted when a legacy withdrawal is proven (extension event).
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param proofSubmitter Address that submitted the proof.
    event WithdrawalProvenExtension1(bytes32 indexed withdrawalHash, address indexed proofSubmitter);

    /// @notice Emitted when a legacy withdrawal is finalized.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param success        Whether the withdrawal was successful.
    event WithdrawalFinalized(bytes32 indexed withdrawalHash, bool success);

    /// @notice Emitted when deposits are enabled or disabled.
    /// @param enabled Whether deposits are enabled.
    event DepositsToggled(bool enabled);

    /// @notice Emitted when withdrawals are enabled or disabled.
    /// @param enabled Whether withdrawals are enabled.
    event WithdrawalsToggled(bool enabled);

    /// @notice Emitted when the trusted state is set.
    /// @param trustedRoot The trusted L2ToL1MessagePasser storage root.
    event TrustedStateSet(bytes32 indexed trustedRoot);

    /// @notice Returns the trusted L2ToL1MessagePasser storage root.
    /// @return The trusted storage root, or zero if not set.
    function trustedMessagePasserStorageRoot() external view returns (bytes32) {
        return _trustedMessagePasserStorageRoot;
    }

    /// @notice Returns whether deposits are currently enabled.
    /// @return True if deposits are enabled, false otherwise.
    function depositsEnabled() external view returns (bool) {
        return _depositsEnabled;
    }

    /// @notice Returns whether withdrawals are currently enabled.
    /// @return True if withdrawals are enabled, false otherwise.
    function withdrawalsEnabled() external view returns (bool) {
        return _withdrawalsEnabled;
    }

    /// @notice Semantic version.
    /// @custom:semver 1.1.0
    function version() public pure override returns (string memory) {
        return "1.1.0";
    }

    /// @notice Constructs the L1CGTBridgeWithLegacyWithdrawal contract.
    /// @param _cgtToken    Address of the CGT token.
    /// @param _l2CGTBridge Address of the corresponding bridge on the other network.
    constructor(address _cgtToken, address _l2CGTBridge) L1CGTBridge(_cgtToken, _l2CGTBridge) { }

    /// @notice Initializer.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _superchainConfig Address of the SuperchainConfig contract.
    /// @param _optimismPortal   Address of the OptimismPortal2 contract.
    function initialize(
        ICrossDomainMessenger _messenger,
        ISuperchainConfig _superchainConfig,
        IOptimismPortal2 _optimismPortal
    )
        external
        reinitializer(initVersion())
    {
        // Initialization transactions must come from the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        messenger = _messenger;
        superchainConfig = _superchainConfig;
        optimismPortal = _optimismPortal;

        // Initialize state variables
        _depositsEnabled = true;
        _withdrawalsEnabled = true;
    }

    /// @notice Sends CGT tokens to a receiver's address on the other chain.
    /// @param _to          Address to bridge the CGT tokens to.
    /// @param _amount      Amount of CGT tokens to bridge.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    function bridgeCGT(address _to, uint256 _amount, uint32 _minGasLimit) external override {
        if (!_depositsEnabled) revert DepositsDisabled();
        if (superchainConfig.paused(address(this))) revert Paused();

        IERC20(cgtToken).safeTransferFrom(msg.sender, address(this), _amount);

        messenger.sendMessage({
            _target: address(l2CGTBridge),
            _message: abi.encodeCall(L2CGTBridge.finalizeBridgeCGT, (msg.sender, _to, _amount)),
            _minGasLimit: _minGasLimit
        });

        emit CGTBridgeInitiated(msg.sender, _to, _amount);
    }

    /// @notice Finalizes a CGT bridge on this chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the CGT being bridged.
    function finalizeBridgeCGT(address _from, address _to, uint256 _amount) external override {
        if (!_withdrawalsEnabled) revert WithdrawalsDisabled();
        if (superchainConfig.paused(address(this))) revert Paused();

        if (msg.sender != address(messenger) || messenger.xDomainMessageSender() != address(l2CGTBridge)) {
            revert OnlyL2CGTBridge();
        }

        if (_to == address(this) || _to == address(messenger)) {
            revert InvalidRecipient();
        }

        IERC20(cgtToken).safeTransfer(_to, _amount);

        emit CGTBridgeFinalized(_from, _to, _amount);
    }

    /// @notice Sets the trusted L2ToL1MessagePasser storage root for legacy withdrawal verification.
    ///         This function can only be called once during migration.
    /// @param _trustedRoot The trusted storage root to set.
    function setTrustedStateOnce(bytes32 _trustedRoot) external {
        _assertOnlyProxyAdminOrProxyAdminOwner();

        if (_trustedStateSet) revert TrustedStateAlreadySet();
        if (_trustedRoot == bytes32(0)) revert InvalidTrustedRoot();

        _trustedMessagePasserStorageRoot = _trustedRoot;
        _trustedStateSet = true;

        emit TrustedStateSet(_trustedRoot);
    }

    /// @notice Proves a legacy withdrawal transaction using the trusted storage root.
    /// @param _tx              The withdrawal transaction to prove.
    /// @param _withdrawalProof The proof of inclusion in the trusted storage root.
    function legacyProveWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        bytes[] calldata _withdrawalProof
    )
        external
    {
        if (!_trustedStateSet) revert TrustedStateNotSet();

        // Only process withdrawals with native asset value (CGT conversions)
        if (_tx.value == 0) revert InvalidWithdrawalValue();

        // Prevent withdrawals to the CGT token contract
        if (_tx.target == address(cgtToken)) revert InvalidWithdrawalTarget();

        // Prevent withdrawals to this contract or the messenger
        if (_tx.target == address(this) || _tx.target == address(messenger)) {
            revert InvalidRecipient();
        }

        bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);

        // Verify the inclusion proof using the trusted storage root
        bytes32 storageKey = keccak256(abi.encode(withdrawalHash, uint256(0)));
        bytes32 storageValue = bytes32(uint256(1));

        SecureMerkleTrie.verifyInclusionProof({
            _key: abi.encode(storageKey),
            _value: abi.encode(storageValue),
            _proof: _withdrawalProof,
            _root: _trustedMessagePasserStorageRoot
        });

        // Mark the withdrawal as proven by this submitter
        provenLegacyWithdrawals[withdrawalHash][msg.sender] = true;

        emit WithdrawalProven(withdrawalHash, _tx.sender, _tx.target);
        emit WithdrawalProvenExtension1(withdrawalHash, msg.sender);
    }

    /// @notice Finalizes a proven legacy withdrawal transaction.
    /// @param _tx The withdrawal transaction to finalize.
    function legacyFinalizeWithdrawalTransaction(Types.WithdrawalTransaction memory _tx) external {
        if (!_trustedStateSet) revert TrustedStateNotSet();

        // Only process withdrawals with native asset value (CGT conversions)
        if (_tx.value == 0) revert InvalidWithdrawalValue();

        // Prevent withdrawals to the CGT token contract
        if (_tx.target == address(cgtToken)) revert InvalidWithdrawalTarget();

        // Prevent withdrawals to this contract or the messenger
        if (_tx.target == address(this) || _tx.target == address(messenger)) {
            revert InvalidRecipient();
        }

        bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);

        // Check that the withdrawal has been proven by the caller
        if (!provenLegacyWithdrawals[withdrawalHash][msg.sender]) {
            revert WithdrawalNotProven();
        }

        // Check that the withdrawal has not been finalized
        if (finalizedLegacyWithdrawals[withdrawalHash]) {
            revert WithdrawalAlreadyFinalized();
        }

        // Check that OptimismPortal hasn't finalized this withdrawal
        if (optimismPortal.finalizedWithdrawals(withdrawalHash)) {
            revert WithdrawalAlreadyFinalized();
        }

        // Mark as finalized to prevent replay
        finalizedLegacyWithdrawals[withdrawalHash] = true;

        // Transfer CGT tokens equivalent to the native asset value
        IERC20(cgtToken).safeTransfer(_tx.target, _tx.value);

        // Execute the withdrawal data if present
        bool success = true;
        if (_tx.data.length > 0 && _tx.gasLimit > 0) {
            (success,) = _tx.target.call{ gas: _tx.gasLimit }(_tx.data);
        }

        emit WithdrawalFinalized(withdrawalHash, success);
    }

    /// @notice Enables deposit functionality.
    function enableDeposits() external {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        _depositsEnabled = true;
        emit DepositsToggled(true);
    }

    /// @notice Disables deposit functionality.
    function disableDeposits() external {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        _depositsEnabled = false;
        emit DepositsToggled(false);
    }

    /// @notice Enables withdrawal functionality.
    function enableWithdrawals() external {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        _withdrawalsEnabled = true;
        emit WithdrawalsToggled(true);
    }

    /// @notice Disables withdrawal functionality.
    function disableWithdrawals() external {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        _withdrawalsEnabled = false;
        emit WithdrawalsToggled(false);
    }
}
