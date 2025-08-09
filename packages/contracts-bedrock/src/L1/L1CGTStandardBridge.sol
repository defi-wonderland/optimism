// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { StandardCGTBridge } from "src/universal/StandardCGTBridge.sol";
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EOA } from "src/libraries/EOA.sol";
import { Types } from "src/libraries/Types.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { Constants } from "src/libraries/Constants.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";
import { SecureMerkleTrie } from "src/libraries/trie/SecureMerkleTrie.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";

/// @custom:proxied true
/// @title L1CGTStandardBridge
/// @notice The L1CGTStandardBridge is responsible for transferring Custom Gas Tokens (CGT) from L1
///         to L2 where they are converted to native assets through the LiquidityController system.
///         This bridge escrows CGT tokens on L1 and triggers the minting of equivalent native
///         assets on L2.
contract L1CGTStandardBridge is StandardCGTBridge, ProxyAdminOwnedBase, ReinitializableBase, ISemver {
    using SafeERC20 for IERC20;

    /// @notice Address of the SystemConfig contract.
    /// @custom:network-specific
    ISystemConfig public systemConfig;

    /// @notice Address of the SuperchainConfig contract.
    /// @custom:network-specific
    ISuperchainConfig public superchainConfig;

    /// @notice Reference to the OptimismPortal2 contract.
    /// @custom:network-specific
    IOptimismPortal2 public optimismPortal;

    /// @notice Total amount of CGT tokens deposited.
    uint256 public cgtDeposits;

    /// @notice Total amount of CGT tokens available for legacy withdrawals.
    /// @dev This tracks tokens migrated from the old system that can be withdrawn.
    uint256 public legacyWithdrawalBalance;

    /// @notice Trusted storage root of the L2ToL1MessagePasser contract after upgrade.
    bytes32 public trustedMessagePasserStorageRoot;

    /// @notice Address of the sender of the L2 withdrawal transaction.
    address public l2Sender;

    /// @notice Flag to ensure trustedMessagePasserStorageRoot is set only once.
    bool public trustedStateSet;

    /// @notice Whether deposits are enabled.
    bool public depositsEnabled;

    /// @notice Whether withdrawals are enabled.
    bool public withdrawalsEnabled;

    /// @notice Represents a proven legacy withdrawal.
    /// @custom:field timestamp Timestamp at which the withdrawal was proven.
    struct ProvenLegacyWithdrawal {
        uint64 timestamp;
    }

    /// @notice Mapping of withdrawal hashes to proof submitters to ProvenLegacyWithdrawal data.
    mapping(bytes32 => mapping(address => ProvenLegacyWithdrawal)) public provenLegacyWithdrawals;

    /// @notice Mapping of withdrawal hashes to finalization status for legacy withdrawals.
    mapping(bytes32 => bool) public finalizedLegacyWithdrawals;

    /// @notice Mapping of withdrawal hashes to arrays of proof submitters for legacy withdrawals.
    mapping(bytes32 => address[]) public proofLegacySubmitters;

    /// @notice Emitted when a legacy withdrawal transaction is proven.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param from           Address of the sender of the withdrawal transaction.
    /// @param to             Address of the target of the withdrawal transaction.
    event WithdrawalProven(bytes32 indexed withdrawalHash, address indexed from, address indexed to);

    /// @notice Emitted when a legacy withdrawal transaction is proven.
    /// @param withdrawalHash    Hash of the withdrawal transaction.
    /// @param proofSubmitter   Address of the proof submitter.
    event WithdrawalProvenExtension1(bytes32 indexed withdrawalHash, address indexed proofSubmitter);

    /// @notice Emitted when a legacy withdrawal transaction is finalized.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param success        Whether the finalization was successful.
    event WithdrawalFinalized(bytes32 indexed withdrawalHash, bool success);

    /// @notice Emitted when the trusted state is set.
    /// @param trustedRoot The trusted message passer storage root.
    event TrustedStateSet(bytes32 indexed trustedRoot);

    /// @notice Thrown when a withdrawal has zero balance.
    error ZeroBalance();

    /// @notice Thrown when trying to call the token contract directly.
    error BadTarget();

    /// @notice Thrown when a withdrawal has not been proven.
    error Unproven();

    /// @notice Thrown when a withdrawal has already been finalized.
    error AlreadyFinalized();

    /// @notice Thrown when the Merkle proof is invalid.
    error InvalidMerkleProof();

    /// @notice Thrown when a non-reentrant call is attempted.
    error NonReentrant();

    /// @notice Thrown when gas estimation fails.
    error GasEstimation();

    /// @notice Thrown when transfer fails.
    error TransferFailed();

    /// @notice Thrown when trusted state is already set.
    error TrustedStateAlreadySet();

    /// @notice Thrown when deposits are disabled.
    error DepositsDisabled();

    /// @notice Thrown when withdrawals are disabled.
    error WithdrawalsDisabled();

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant VERSION = "1.0.0";

    /// @notice Constructs the L1CGTStandardBridge contract.
    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Returns the semantic version of the contract.
    /// @return Semver contract version as a string.
    function version() external pure override returns (string memory) {
        return VERSION;
    }

    /// @notice Returns whether the bridge is paused.
    /// @return Whether the bridge is paused.
    function paused() public view override returns (bool) {
        return superchainConfig.paused();
    }

    /// @notice Returns whether a legacy withdrawal can be finalized.
    /// @param _withdrawalHash Hash of the withdrawal transaction.
    /// @param _proofSubmitter Address of the proof submitter.
    function legacyCanFinalizeWithdrawal(
        bytes32 _withdrawalHash,
        address _proofSubmitter
    )
        external
        view
        returns (bool)
    {
        return _legacyCheckWithdrawal(_withdrawalHash, _proofSubmitter);
    }

    /// @notice Initializer.
    /// @param _cgtToken         Address of the CGT token.
    /// @param _messenger        Address of the CrossDomainMessenger on this network.
    /// @param _otherBridge      Address of the corresponding bridge on the other network.
    /// @param _systemConfig     Address of the SystemConfig contract.
    /// @param _superchainConfig Address of the SuperchainConfig contract.
    /// @param _optimismPortal   Address of the OptimismPortal2 contract.
    function initialize(
        address _cgtToken,
        ICrossDomainMessenger _messenger,
        StandardCGTBridge _otherBridge,
        ISystemConfig _systemConfig,
        ISuperchainConfig _superchainConfig,
        IOptimismPortal2 _optimismPortal
    )
        external
        reinitializer(initVersion())
    {
        // Initialization transactions must come from the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        systemConfig = _systemConfig;
        superchainConfig = _superchainConfig;
        optimismPortal = _optimismPortal;
        l2Sender = Constants.DEFAULT_L2_SENDER;
        depositsEnabled = true;
        withdrawalsEnabled = true;
        __StandardCGTBridge_init({ _cgtToken: _cgtToken, _messenger: _messenger, _otherBridge: _otherBridge });
    }

    /// @notice Sets the trusted message passer storage root once. This represents the state
    ///         of the L2ToL1MessagePasser contract after the upgrade and migration.
    /// @param _trustedMessagePasserStorageRoot The trusted storage root.
    function setTrustedStateOnce(bytes32 _trustedMessagePasserStorageRoot) external {
        // Only the ProxyAdmin owner can set the trusted state.
        _assertOnlyProxyAdminOwner();

        if (trustedStateSet) {
            revert TrustedStateAlreadySet();
        }

        trustedMessagePasserStorageRoot = _trustedMessagePasserStorageRoot;
        trustedStateSet = true;

        emit TrustedStateSet(_trustedMessagePasserStorageRoot);
    }

    /// @notice Sets the initial balance for legacy withdrawals after migration.
    /// @param _legacyBalance The amount of CGT tokens available for legacy withdrawals.
    function setLegacyWithdrawalBalance(uint256 _legacyBalance) external {
        _assertOnlyProxyAdminOwner();
        legacyWithdrawalBalance = _legacyBalance;
    }

    /// @notice Enables deposits for the bridge.
    function enableDeposits() external {
        _assertOnlyProxyAdminOwner();
        depositsEnabled = true;
    }

    /// @notice Disables deposits for the bridge.
    function disableDeposits() external {
        _assertOnlyProxyAdminOwner();
        depositsEnabled = false;
    }

    /// @notice Enables withdrawals for the bridge.
    function enableWithdrawals() external {
        _assertOnlyProxyAdminOwner();
        withdrawalsEnabled = true;
    }

    /// @notice Disables withdrawals for the bridge.
    function disableWithdrawals() external {
        _assertOnlyProxyAdminOwner();
        withdrawalsEnabled = false;
    }

    /// @notice Sends CGT tokens to the sender's address on the other chain.
    /// @param _amount      Amount of CGT tokens to bridge.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    /// @param _extraData   Extra data to forward.
    function bridgeCGT(uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData) external payable override {
        _initiateBridgeCGT(msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @notice Sends CGT tokens to a receiver's address on the other chain.
    /// @param _to          Address to bridge the CGT tokens to.
    /// @param _amount      Amount of CGT tokens to bridge.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    /// @param _extraData   Extra data to forward.
    function bridgeCGTTo(
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        payable
        override
    {
        _initiateBridgeCGT(msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

    /// @notice Finalizes a CGT bridge on this chain. Can only be triggered by the other
    ///         StandardBridge contract on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the CGT being bridged.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function finalizeBridgeCGT(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        override
    {
        if (paused()) {
            revert Paused();
        }

        if (msg.sender != address(messenger)) {
            revert FunctionCanOnlyBeCalledFromOtherBridge();
        }
        if (messenger.xDomainMessageSender() != address(otherBridge)) {
            revert FunctionCanOnlyBeCalledFromOtherBridge();
        }

        cgtDeposits = cgtDeposits - _amount;
        IERC20(cgtToken).safeTransfer(_to, _amount);

        emit CGTBridgeFinalized(_from, _to, _amount, _extraData);
    }

    /// @notice Proves a legacy withdrawal transaction using trusted state.
    /// @param _tx              Withdrawal transaction to prove.
    /// @param _withdrawalProof Inclusion proof of the withdrawal in L2ToL1MessagePasser contract.
    function legacyProveWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        bytes[] calldata _withdrawalProof
    )
        external
    {
        if (paused()) {
            revert Paused();
        }

        if (!withdrawalsEnabled) {
            revert WithdrawalsDisabled();
        }

        // Load the withdrawal hash as a unique identifier.
        bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);

        // Compute the storage slot of the withdrawal hash in the L2ToL1MessagePasser contract.
        // Refer to the Solidity documentation for more information on how storage layouts are
        // computed for mappings.
        bytes32 storageKey = keccak256(
            abi.encode(
                withdrawalHash,
                uint256(0) // The withdrawals mapping is at the first slot in the layout.
            )
        );

        // Verify that the hash of this withdrawal was stored in the L2toL1MessagePasser contract
        // on L2. If this is true, under the assumption that the SecureMerkleTrie does not have
        // bugs, then we know that this withdrawal was actually triggered on L2 and can therefore
        // be relayed on L1.
        if (
            SecureMerkleTrie.verifyInclusionProof({
                _key: abi.encode(storageKey),
                _value: hex"01",
                _proof: _withdrawalProof,
                _root: trustedMessagePasserStorageRoot
            }) == false
        ) revert InvalidMerkleProof();

        // Designate the withdrawalHash as proven by storing the `timestamp` in the
        // `provenLegacyWithdrawals` mapping.
        provenLegacyWithdrawals[withdrawalHash][msg.sender] =
            ProvenLegacyWithdrawal({ timestamp: uint64(block.timestamp) });

        // Add the proof submitter to the list of proof submitters for this withdrawal hash.
        proofLegacySubmitters[withdrawalHash].push(msg.sender);

        // Emit a `WithdrawalProven` event.
        emit WithdrawalProven(withdrawalHash, _tx.sender, _tx.target);
        // Emit a `WithdrawalProvenExtension1` event.
        emit WithdrawalProvenExtension1(withdrawalHash, msg.sender);
    }

    /// @notice Finalizes a legacy withdrawal transaction.
    /// @param _tx Withdrawal transaction to finalize.
    function legacyFinalizeWithdrawalTransaction(Types.WithdrawalTransaction memory _tx) external {
        _legacyFinalizeWithdrawalTransaction(_tx, msg.sender);
    }

    /// @notice Finalizes a legacy withdrawal transaction, using an external proof submitter.
    /// @param _tx            Withdrawal transaction to finalize.
    /// @param _proofSubmitter Address of the proof submitter.
    function legacyFinalizeWithdrawalTransactionExternalProof(
        Types.WithdrawalTransaction memory _tx,
        address _proofSubmitter
    )
        external
    {
        _legacyFinalizeWithdrawalTransaction(_tx, _proofSubmitter);
    }

    /// @notice Sends CGT tokens to the sender's address on the other chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of CGT tokens to bridge.
    /// @param _minGasLimit Minimum gas limit for the bridge.
    /// @param _extraData   Extra data to forward.
    function _initiateBridgeCGT(
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        internal
    {
        if (!EOA.isSenderEOA()) {
            revert FunctionCanOnlyBeCalledFromEOA();
        }

        if (paused()) {
            revert Paused();
        }

        if (!depositsEnabled) {
            revert DepositsDisabled();
        }

        if (msg.value > 0) {
            revert CGTBridge_ETHNotAllowed();
        }

        if (_amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        if (_to == address(0)) {
            revert RecipientCannotBeZeroAddress();
        }

        IERC20(cgtToken).safeTransferFrom(_from, address(this), _amount);
        cgtDeposits = cgtDeposits + _amount;

        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeWithSelector(this.finalizeBridgeCGT.selector, _from, _to, _amount, _extraData),
            _minGasLimit: _minGasLimit
        });

        emit CGTBridgeInitiated(_from, _to, _amount, _extraData);
    }

    /// @notice Finalizes a legacy withdrawal transaction, using an external proof submitter.
    /// @param _tx            Withdrawal transaction to finalize.
    /// @param _proofSubmitter Address of the proof submitter.
    function _legacyFinalizeWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        address _proofSubmitter
    )
        internal
    {
        if (paused()) {
            revert Paused();
        }

        if (!withdrawalsEnabled) {
            revert WithdrawalsDisabled();
        }

        // Make sure that the l2Sender has not yet been set. The l2Sender is set to a value other
        // than the default value when a withdrawal transaction is being finalized. This check is
        // a defacto reentrancy guard.
        if (l2Sender != Constants.DEFAULT_L2_SENDER) revert NonReentrant();

        // Compute the withdrawal hash.
        bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);

        // Check that the withdrawal can be finalized.
        if (!_legacyCheckWithdrawal(withdrawalHash, _proofSubmitter)) {
            revert Unproven();
        }

        // Mark the withdrawal as finalized so it can't be replayed.
        finalizedLegacyWithdrawals[withdrawalHash] = true;

        // Set the l2Sender so contracts know who triggered this withdrawal on L2.
        l2Sender = _tx.sender;

        bool success;
        {
            // Only withdrawals that contain CGT token value must be able to finalize.
            // In CGT chains, _tx.value represents the amount of CGT tokens that were native assets in L2
            if (_tx.value == 0) revert ZeroBalance();

            // Cannot call the token contract directly from the CGTBridge. This would allow an attacker
            // to call approve from a withdrawal and drain the balance of the CGTBridge.
            if (_tx.target == cgtToken) revert BadTarget();

            // Transfer CGT tokens when value is specified.
            // Note: _tx.value here represents CGT token amount, not ETH amount
            if (_tx.value != 0) {
                // Update the legacy withdrawal balance accounting.
                // This tracks how many CGT tokens are still available for legacy withdrawals
                if (legacyWithdrawalBalance >= _tx.value) {
                    legacyWithdrawalBalance -= _tx.value;
                }

                // Read the balance of the target contract before the transfer so the consistency
                // of the transfer can be checked afterwards.
                uint256 startBalance = IERC20(cgtToken).balanceOf(address(this));

                // Transfer the CGT tokens to the target address
                // _tx.value represents the amount of CGT tokens, not ETH
                IERC20(cgtToken).safeTransfer(_tx.target, _tx.value);

                // The balance must be transferred exactly.
                if (IERC20(cgtToken).balanceOf(address(this)) != startBalance - _tx.value) {
                    revert TransferFailed();
                }
            }

            // Make a call to the target contract only if there is calldata.
            if (_tx.data.length != 0) {
                success = SafeCall.callWithMinGas(_tx.target, _tx.gasLimit, 0, _tx.data);
            } else {
                success = true;
            }
        }

        // Reset the l2Sender back to the default value.
        l2Sender = Constants.DEFAULT_L2_SENDER;

        // Reverting here is useful for determining the exact gas cost to successfully execute the
        // sub call to the target contract if the minimum gas limit specified by the user would not
        // be sufficient to execute the sub call.
        if (!success && tx.origin == Constants.ESTIMATION_ADDRESS) {
            revert GasEstimation();
        }

        // All withdrawals are immediately finalized. Replayability can
        // be achieved through contracts built on top of this contract
        emit WithdrawalFinalized(withdrawalHash, success);
    }

    /// @notice Checks that a legacy withdrawal can be finalized.
    /// @param _withdrawalHash Hash of the withdrawal transaction.
    /// @param _proofSubmitter Address of the proof submitter.
    function _legacyCheckWithdrawal(bytes32 _withdrawalHash, address _proofSubmitter) internal view returns (bool) {
        ProvenLegacyWithdrawal memory provenWithdrawal = provenLegacyWithdrawals[_withdrawalHash][_proofSubmitter];

        // A withdrawal can only be finalized if it has been proven. We know that a withdrawal has
        // been proven at least once when its timestamp is non-zero. Unproven withdrawals will have
        // a timestamp of zero.
        if (provenWithdrawal.timestamp == 0) revert Unproven();

        // Check that this withdrawal has not already been finalized, this is replay protection.
        if (optimismPortal.finalizedWithdrawals(_withdrawalHash) || finalizedLegacyWithdrawals[_withdrawalHash]) {
            revert AlreadyFinalized();
        } else {
            return true;
        }
    }
}
