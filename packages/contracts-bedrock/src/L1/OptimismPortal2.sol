// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ProxyAdminOwnedBase } from "src/universal/ProxyAdminOwnedBase.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ResourceMetering } from "src/L1/ResourceMetering.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";

// Libraries
import { EOA } from "src/libraries/EOA.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";
import { Constants } from "src/libraries/Constants.sol";
import { Types } from "src/libraries/Types.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { SecureMerkleTrie } from "src/libraries/trie/SecureMerkleTrie.sol";
import { AddressAliasHelper } from "src/vendor/AddressAliasHelper.sol";
import { Claim, GameStatus, GameType, GameTypes } from "src/dispute/lib/Types.sol";
import { Features } from "src/libraries/Features.sol";
import { Asset, BridgeHookItem, Direction, Item } from "src/libraries/BridgeHookItem.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { IResourceMetering } from "interfaces/L1/IResourceMetering.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { IAnchorStateRegistry } from "interfaces/dispute/IAnchorStateRegistry.sol";
import { IETHLockbox } from "interfaces/L1/IETHLockbox.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IBridgeHook } from "interfaces/universal/IBridgeHook.sol";

/// @custom:proxied true
/// @title OptimismPortal2
/// @notice The OptimismPortal is a low-level contract responsible for passing messages between L1
///         and L2. Messages sent directly to the OptimismPortal have no form of replayability.
///         Users are encouraged to use the L1CrossDomainMessenger for a higher-level interface.
contract OptimismPortal2 is Initializable, ResourceMetering, ReinitializableBase, ProxyAdminOwnedBase, ISemver {
    /// @notice Represents a proven withdrawal.
    /// @custom:field disputeGameProxy Game that the withdrawal was proven against.
    /// @custom:field timestamp        Timestamp at which the withdrawal was proven.
    struct ProvenWithdrawal {
        IDisputeGame disputeGameProxy;
        uint64 timestamp;
    }

    /// @notice The delay between when a withdrawal is proven and when it may be finalized.
    uint256 internal immutable PROOF_MATURITY_DELAY_SECONDS;

    /// @notice Version of the deposit event.
    uint256 internal constant DEPOSIT_VERSION = 0;

    /// @notice The L2 gas limit set when eth is deposited using the receive() function.
    uint64 internal constant RECEIVE_DEFAULT_GAS_LIMIT = 100_000;

    /// @notice Address of the L2 account which initiated a withdrawal in this transaction.
    ///         If the value of this variable is the default L2 sender address, then we are NOT
    ///         inside of a call to finalizeWithdrawalTransaction.
    address public l2Sender;

    /// @notice A list of withdrawal hashes which have been successfully finalized.
    mapping(bytes32 => bool) public finalizedWithdrawals;

    /// @custom:legacy
    /// @custom:spacer provenWithdrawals
    /// @notice Spacer taking up the legacy `provenWithdrawals` mapping slot.
    bytes32 private spacer_52_0_32;

    /// @custom:legacy
    /// @custom:spacer paused
    /// @notice Spacer for backwards compatibility.
    bool private spacer_53_0_1;

    /// @custom:legacy
    /// @custom:spacer superchainConfig
    /// @notice Spacer for backwards compatibility.
    address private spacer_53_1_20;

    /// @custom:legacy
    /// @custom:spacer l2Oracle
    /// @notice Spacer taking up the legacy `l2Oracle` address slot.
    address private spacer_54_0_20;

    /// @notice Address of the SystemConfig contract.
    /// @custom:network-specific
    ISystemConfig public systemConfig;

    /// @custom:network-specific
    /// @custom:legacy
    /// @custom:spacer disputeGameFactory
    /// @notice Spacer taking up the legacy `disputeGameFactory` address slot.
    address private spacer_56_0_20;

    /// @notice A mapping of withdrawal hashes to proof submitters to ProvenWithdrawal data.
    mapping(bytes32 => mapping(address => ProvenWithdrawal)) public provenWithdrawals;

    /// @custom:legacy
    /// @custom:spacer disputeGameBlacklist
    bytes32 private spacer_58_0_32;

    /// @custom:legacy
    /// @custom:spacer respectedGameType
    GameType private spacer_59_0_4;

    /// @custom:legacy
    /// @custom:spacer respectedGameTypeUpdatedAt
    uint64 private spacer_59_4_8;

    /// @notice Mapping of withdrawal hashes to addresses that have submitted a proof for the
    ///         withdrawal. Original OptimismPortal contract only allowed one proof to be submitted
    ///         for any given withdrawal hash. Fault Proofs version of this contract must allow
    ///         multiple proofs for the same withdrawal hash to prevent a malicious user from
    ///         blocking other withdrawals by proving them against invalid proposals. Submitters
    ///         are tracked in an array to simplify the off-chain process of determining which
    ///         proof submission should be used when finalizing a withdrawal.
    mapping(bytes32 => address[]) public proofSubmitters;

    /// @custom:legacy
    /// @custom:spacer _balance
    uint256 private spacer_61_0_32;

    /// @notice Address of the AnchorStateRegistry contract.
    IAnchorStateRegistry public anchorStateRegistry;

    /// @notice Address of the ETHLockbox contract. NOTE that as of v4.1.0 it is not possible to
    ///         set this value in storage and it is only possible for this value to be set if the
    ///         chain was first upgraded to v4.0.0. Chains that skip v4.0.0 will not have any
    ///         ETHLockbox set here.
    IETHLockbox public ethLockbox;

    /// @custom:legacy
    /// @custom:spacer superRootsActive
    bool private spacer_63_20_1;

    /// @notice Address of the bridge hook, gated by the BRIDGE_HOOK feature. When both are set,
    ///         the Portal defers to the hook on deposits and on withdrawal finalization.
    /// @custom:network-specific
    IBridgeHook public bridgeHook;

    /// @notice Counter the Portal folds into a deposit's identifier, which is what makes two
    ///         otherwise identical deposits distinct. Only advanced while the hook is in use.
    uint64 public depositNonce;

    /// @notice Reentrancy guard held for the duration of any call into the hook. At finalization
    ///         that call runs after the ETH is unlocked and before `l2Sender` is set, so neither
    ///         the Portal's own `l2Sender` guard nor the lockbox's covers it, and it cannot reuse
    ///         `l2Sender` because `ETHLockbox.unlockETH` reverts when the calling portal has one
    ///         set. On deposits the guard is what makes the returned-value check meaningful:
    ///         without it a hook could keep the ETH it was handed and restore the Portal's balance
    ///         by re-depositing from inside the same call.
    /// @dev Packed into the same slot as `bridgeHook`, so reading it is free on any path that has
    ///      already resolved the hook address, and costs nothing at all on a chain with no hook.
    bool internal _inBridgeHook;

    /// @notice Terms the Portal committed to for deposits it deferred to the hook. The Portal
    ///         will later act on terms the hook supplies, so it commits to them first and refuses
    ///         to act on any others.
    mapping(bytes32 => bool) public pendingDeposits;

    /// @notice Terms the Portal committed to for withdrawals it finalized into holding, keyed by
    ///         the item identifier. One bit is enough, because the identifier already binds every
    ///         field of the item and the item carries the withdrawal's own hash.
    mapping(bytes32 => bool) public heldWithdrawals;

    /// @notice Hash of the withdrawal currently being finalized, or zero when none is. Exposed so
    ///         that a contract called during finalization can identify which withdrawal it is
    ///         acting for, which the call chain does not otherwise carry: the messenger does not
    ///         know it and the bridge is two frames further down.
    /// @dev The direct analogue of `l2Sender`, set and cleared on the same lines, and read by the
    ///      L1StandardBridge so that a token withdrawal can be identified by the protocol's own
    ///      hash instead of a counter it mints itself. That is what makes a verdict recordable
    ///      during the challenge window for tokens as well as for ETH. Zero is a safe sentinel
    ///      because a keccak output is never zero.
    bytes32 internal _currentWithdrawalHash;

    /// @notice Items this contract has deferred to the hook and not yet completed.
    /// @dev Both release paths are gated on the live `bridgeHook` address, so repointing or
    ///      unsetting it while anything is outstanding would leave held value with no caller able
    ///      to move it. This counter is what lets `setBridgeHook` refuse that, and it is the only
    ///      reason the Portal counts items at all.
    uint64 public outstandingBridgeHookItems;

    /// @notice Emitted when the Portal is migrated.
    /// @param oldLockbox The lockbox before the migration
    /// @param newLockbox The shared lockbox
    /// @param oldAnchorStateRegistry The anchorStateRegistry used before the migration
    /// @param newAnchorStateRegistry The anchorStateRegistry used after the migration
    event PortalMigrated(
        IETHLockbox oldLockbox,
        IETHLockbox newLockbox,
        IAnchorStateRegistry oldAnchorStateRegistry,
        IAnchorStateRegistry newAnchorStateRegistry
    );

    /// @notice Migrates the total ETH balance to the ETHLockbox.
    event ETHMigrated(address indexed lockbox, uint256 balance);

    /// @notice Emitted when a transaction is deposited from L1 to L2. The parameters of this event
    ///         are read by the rollup node and used to derive deposit transactions on L2.
    /// @param from       Address that triggered the deposit transaction.
    /// @param to         Address that the deposit transaction is directed to.
    /// @param version    Version of this deposit transaction event.
    /// @param opaqueData ABI encoded deposit data to be parsed off-chain.
    event TransactionDeposited(address indexed from, address indexed to, uint256 indexed version, bytes opaqueData);

    /// @notice Emitted when a withdrawal transaction is proven.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param from           Address that triggered the withdrawal transaction.
    /// @param to             Address that the withdrawal transaction is directed to.
    event WithdrawalProven(bytes32 indexed withdrawalHash, address indexed from, address indexed to);

    /// @notice Emitted when a withdrawal transaction is proven. Exists as a separate event to
    ///         allow for backwards compatibility for tooling that observes the WithdrawalProven
    ///         event.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param proofSubmitter Address of the proof submitter.
    event WithdrawalProvenExtension1(bytes32 indexed withdrawalHash, address indexed proofSubmitter);

    /// @notice Emitted when a withdrawal transaction is finalized.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param success        Whether the withdrawal transaction was successful.
    event WithdrawalFinalized(bytes32 indexed withdrawalHash, bool success);

    /// @notice Emitted when a proof for a withdrawal transaction is deleted.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param proofSubmitter Address of the proof submitter.
    event WithdrawalProofDeleted(bytes32 indexed withdrawalHash, address indexed proofSubmitter);

    /// @notice Emitted when the bridge hook address is set.
    /// @param bridgeHook Address of the bridge hook.
    event BridgeHookSet(address indexed bridgeHook);

    /// @notice Emitted when a deposit is held by the bridge hook. No TransactionDeposited is
    ///         emitted and no ETH is locked until the deposit completes, so this is the event an
    ///         indexer should watch on a hook-enabled chain.
    /// @dev The nonce is emitted because it is the one part of the identifier's preimage that
    ///      cannot be recovered from the submitting transaction. With it, the backlog is
    ///      reconstructible from a protocol event plus the original transaction, without
    ///      depending on the hook having behaved.
    /// @param id    Identifier of the held deposit.
    /// @param nonce Counter folded into the identifier.
    event DepositPending(bytes32 indexed id, uint64 nonce);

    /// @notice Emitted when a withdrawal finalizes into holding rather than paying its recipient.
    ///         The withdrawal is consumed against the protocol either way.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param id             Identifier of the held item.
    event WithdrawalHeld(bytes32 indexed withdrawalHash, bytes32 indexed id);

    /// @notice Thrown when a withdrawal has already been finalized.
    error OptimismPortal_AlreadyFinalized();

    /// @notice Thrown when the target of a withdrawal is unsafe.
    error OptimismPortal_BadTarget();

    /// @notice Thrown when the calldata for a deposit is too large.
    error OptimismPortal_CalldataTooLarge();

    /// @notice Thrown when the portal is paused.
    error OptimismPortal_CallPaused();

    /// @notice Thrown when a CGT withdrawal is not allowed.
    error OptimismPortal_NotAllowedOnCGTMode();

    /// @notice Thrown when a gas estimation transaction is being executed.
    error OptimismPortal_GasEstimation();

    /// @notice Thrown when the gas limit for a deposit is too low.
    error OptimismPortal_GasLimitTooLow();

    /// @notice Thrown when the target of a withdrawal is not a proper dispute game.
    error OptimismPortal_ImproperDisputeGame();

    /// @notice Thrown when a withdrawal has not been proven against a valid dispute game.
    error OptimismPortal_InvalidDisputeGame();

    /// @notice Thrown when Interop is set without the lockbox feature flag
    error OptimismPortal_InvalidInteropState();

    /// @notice Thrown when a withdrawal has not been proven against a valid merkle proof.
    error OptimismPortal_InvalidMerkleProof();

    /// @notice Thrown when a withdrawal has not been proven against a valid output root proof.
    error OptimismPortal_InvalidOutputRootProof();

    /// @notice Thrown when a withdrawal's timestamp is not greater than the dispute game's creation timestamp.
    error OptimismPortal_InvalidProofTimestamp();

    /// @notice Thrown when the root claim of a dispute game is invalid.
    error OptimismPortal_InvalidRootClaim();

    /// @notice Thrown when migrating to the registry that was previously
    /// set on the OptimismPortal prior to the migration
    error OptimismPortal_MigratingToSameRegistry();

    /// @notice Thrown when a withdrawal is being finalized by a reentrant call.
    error OptimismPortal_NoReentrancy();

    /// @notice Thrown when calling a function that is only available when INTEROP
    /// is enabled
    error OptimismPortal_NotUsingInterop();

    /// @notice Thrown when calling a function that requires an active ETHLockbox.
    error OptimismPortal_NotUsingLockbox();

    /// @notice Thrown when a withdrawal has not been proven for long enough.
    error OptimismPortal_ProofNotOldEnough();

    /// @notice Thrown when a withdrawal has not been proven.
    error OptimismPortal_Unproven();

    /// @notice Thrown when ETHLockbox is set/unset incorrectly depending on the feature flag.
    error OptimismPortal_InvalidLockboxState();

    /// @notice Thrown when migrateToSharedDisputeGame is called with a zero address.
    error OptimismPortal_ZeroAddress();

    /// @notice Thrown when the new lockbox has not authorized this portal.
    error OptimismPortal_LockboxNotAuthorizedForPortal();

    /// @notice Thrown when a dispute game has not been permanently invalidated.
    error OptimismPortal_DisputeGameNotInvalidated();

    /// @notice Thrown when the bridge hook is set or unset while the feature is not enabled.
    error OptimismPortal_InvalidBridgeHookState();

    /// @notice Thrown when a hook-only entry point is called by anyone else.
    error OptimismPortal_NotBridgeHook();

    /// @notice Thrown when an item is supplied that the Portal never committed to.
    error OptimismPortal_UncommittedItem();

    /// @notice Thrown when the bridge hook would be repointed while items are still deferred to it.
    error OptimismPortal_BridgeHookItemsOutstanding();

    /// @notice Thrown when the value arriving does not match the amount the Portal committed to.
    error OptimismPortal_ItemValueMismatch();

    /// @notice Thrown when the call made on behalf of a released withdrawal fails.
    error OptimismPortal_ReleaseFailed();

    /// @notice Semantic version.
    /// @custom:semver 5.11.0
    function version() public pure virtual returns (string memory) {
        return "5.11.0";
    }

    /// @param _proofMaturityDelaySeconds The proof maturity delay in seconds.
    constructor(uint256 _proofMaturityDelaySeconds) ReinitializableBase(3) {
        PROOF_MATURITY_DELAY_SECONDS = _proofMaturityDelaySeconds;
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _systemConfig Address of the SystemConfig.
    /// @param _anchorStateRegistry Address of the AnchorStateRegistry.
    function initialize(
        ISystemConfig _systemConfig,
        IAnchorStateRegistry _anchorStateRegistry,
        IETHLockbox _ethLockbox
    )
        external
        reinitializer(initVersion())
    {
        // Initialization transactions must come from the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        // Now perform initialization logic.
        systemConfig = _systemConfig;
        anchorStateRegistry = _anchorStateRegistry;
        if (address(_ethLockbox) != address(0)) {
            ethLockbox = _ethLockbox;
        }

        _assertValidInteropState();
        // Assert that the lockbox state is valid.
        _assertValidLockboxState();

        // Set the l2Sender slot, only if it is currently empty. This signals the first
        // initialization of the contract.
        if (l2Sender == address(0)) {
            l2Sender = Constants.DEFAULT_L2_SENDER;
        }

        // Initialize the ResourceMetering contract.
        __ResourceMetering_init();
    }

    /// @notice Getter for the current paused status.
    function paused() public view returns (bool) {
        return ethLockbox.paused();
    }

    /// @notice Hash of the withdrawal currently being finalized, or zero if none is.
    /// @dev Callees reached during a finalization use this to identify the withdrawal they are
    ///      acting for. The L1StandardBridge needs it because a token withdrawal has no
    ///      protocol-assigned identity of its own by the time it arrives there.
    /// @return bytes32 The withdrawal hash, or zero.
    function currentWithdrawalHash() external view returns (bytes32) {
        return _currentWithdrawalHash;
    }

    /// @notice Getter for the proof maturity delay.
    function proofMaturityDelaySeconds() public view returns (uint256) {
        return PROOF_MATURITY_DELAY_SECONDS;
    }

    /// @notice Getter for the address of the DisputeGameFactory contract.
    function disputeGameFactory() public view returns (IDisputeGameFactory) {
        return anchorStateRegistry.disputeGameFactory();
    }

    /// @notice Returns the SuperchainConfig contract.
    /// @return ISuperchainConfig The SuperchainConfig contract.
    function superchainConfig() external view returns (ISuperchainConfig) {
        return ethLockbox.superchainConfig();
    }

    /// @custom:legacy
    /// @notice Getter function for the address of the guardian.
    function guardian() external view returns (address) {
        return ethLockbox.guardian();
    }

    /// @custom:legacy
    /// @notice Getter for the dispute game finality delay.
    function disputeGameFinalityDelaySeconds() external view returns (uint256) {
        return anchorStateRegistry.disputeGameFinalityDelaySeconds();
    }

    /// @custom:legacy
    /// @notice Getter for the respected game type.
    function respectedGameType() external view returns (GameType) {
        return anchorStateRegistry.respectedGameType();
    }

    /// @custom:legacy
    /// @notice Getter for the retirement timestamp. Note that this value NO LONGER reflects the
    ///         timestamp at which the respected game type was updated. Game retirement and
    ///         respected game type value have been decoupled, this function now only returns the
    ///         retirement timestamp.
    function respectedGameTypeUpdatedAt() external view returns (uint64) {
        return anchorStateRegistry.retirementTimestamp();
    }

    /// @custom:legacy
    /// @notice Getter for the dispute game blacklist.
    /// @param _disputeGame The dispute game to check.
    /// @return Whether the dispute game is blacklisted.
    function disputeGameBlacklist(IDisputeGame _disputeGame) public view returns (bool) {
        return anchorStateRegistry.disputeGameBlacklist(_disputeGame);
    }

    /// @notice Computes the minimum gas limit for a deposit.
    ///         The minimum gas limit linearly increases based on the size of the calldata.
    ///         This is to prevent users from creating L2 resource usage without paying for it.
    ///         This function can be used when interacting with the portal to ensure forwards
    ///         compatibility.
    /// @param _byteCount Number of bytes in the calldata.
    /// @return The minimum gas limit for a deposit.
    function minimumGasLimit(uint64 _byteCount) public pure returns (uint64) {
        return _byteCount * 40 + 21000;
    }

    /// @notice Accepts value so that users can send ETH directly to this contract and have the
    ///         funds be deposited to their address on L2. This is intended as a convenience
    ///         function for EOAs. Contracts should call the depositTransaction() function directly
    ///         otherwise any deposited funds will be lost due to address aliasing.
    receive() external payable {
        depositTransaction(msg.sender, msg.value, RECEIVE_DEFAULT_GAS_LIMIT, false, bytes(""));
    }

    /// @notice Accepts ETH value without triggering a deposit to L2.
    function donateETH() external payable {
        // Intentionally empty.
    }

    /// @notice Sets the bridge hook. Can only be called by the ProxyAdmin or its owner, which is
    ///         the same authority that sets the feature flag: together they enable the feature.
    /// @dev Never repoint the hook while items are held. The terms survive, because they live
    ///      here, but the verdicts and the custody live in the hook.
    /// @param _bridgeHook Address of the bridge hook, or zero to unset it.
    function setBridgeHook(IBridgeHook _bridgeHook) external {
        _assertOnlyProxyAdminOrProxyAdminOwner();

        // Mirrors the lockbox arrangement: this contract checks the feature before allowing the
        // address to be set, and SystemConfig checks the address before allowing the feature to
        // be unset.
        if (!systemConfig.isFeatureEnabled(Features.BRIDGE_HOOK)) {
            revert OptimismPortal_InvalidBridgeHookState();
        }

        // Refuse to move the pointer while anything is still deferred. `completeDepositTransaction`
        // and `completeWithdrawalTransaction` both gate on the live address, so repointing here
        // would strand every held item behind a caller that no longer exists. Emergency stops
        // belong in the hook, which can stop screening without giving up custody.
        if (_bridgeHook != bridgeHook && outstandingBridgeHookItems != 0) {
            revert OptimismPortal_BridgeHookItemsOutstanding();
        }

        bridgeHook = _bridgeHook;
        emit BridgeHookSet(address(_bridgeHook));
    }

    /// @notice Proves a withdrawal transaction using an Output Root proof.
    /// @param _tx               Withdrawal transaction to finalize.
    /// @param _disputeGameIndex Index of the dispute game to prove the withdrawal against.
    /// @param _outputRootProof  Inclusion proof of the L2ToL1MessagePasser storage root.
    /// @param _withdrawalProof  Inclusion proof of the withdrawal within the L2ToL1MessagePasser.
    function proveWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        uint256 _disputeGameIndex,
        Types.OutputRootProof calldata _outputRootProof,
        bytes[] calldata _withdrawalProof
    )
        external
    {
        // Cannot prove withdrawal transactions while the system is paused.
        _assertNotPaused();

        // Make sure that the target address is safe.
        if (_isUnsafeTarget(_tx.target)) {
            revert OptimismPortal_BadTarget();
        }

        // Cannot prove withdrawal with value when custom gas token mode is enabled.
        if (_isUsingCustomGasToken()) {
            if (_tx.value > 0) revert OptimismPortal_NotAllowedOnCGTMode();
        }

        // Fetch the dispute game proxy from the `DisputeGameFactory` contract.
        (,, IDisputeGame disputeGameProxy) = disputeGameFactory().gameAtIndex(_disputeGameIndex);

        // Game must be a Proper Game.
        if (!anchorStateRegistry.isGameProper(disputeGameProxy)) {
            revert OptimismPortal_ImproperDisputeGame();
        }

        // Game must have been respected game type when created.
        if (!anchorStateRegistry.isGameRespected(disputeGameProxy)) {
            revert OptimismPortal_InvalidDisputeGame();
        }

        // Game must not have resolved in favor of the Challenger (invalid root claim).
        if (disputeGameProxy.status() == GameStatus.CHALLENGER_WINS) {
            revert OptimismPortal_InvalidDisputeGame();
        }

        // As a sanity check, we make sure that the current timestamp is not less than or equal to
        // the dispute game's creation timestamp. Not strictly necessary but extra layer of
        // safety against weird bugs. Note that this blocks withdrawals from being proven in the
        // same block that a dispute game is created.
        if (block.timestamp <= disputeGameProxy.createdAt().raw()) {
            revert OptimismPortal_InvalidProofTimestamp();
        }

        // Extract the output root claim. Super game types use rootClaimByChainId to extract
        // the per-chain output root from the super root. Legacy game types use rootClaim directly.
        // TODO(#19816): Post interop clean up the legacy rootClaim() usage in OptimismPortal2.
        Claim outputRootClaim;
        if (GameTypes.isSuperGame(disputeGameProxy.gameType())) {
            outputRootClaim = disputeGameProxy.rootClaimByChainId(systemConfig.l2ChainId());
        } else {
            outputRootClaim = disputeGameProxy.rootClaim();
        }

        // Verify that the output root can be generated with the elements in the proof.
        if (outputRootClaim.raw() != Hashing.hashOutputRootProof(_outputRootProof)) {
            revert OptimismPortal_InvalidOutputRootProof();
        }

        // Load the ProvenWithdrawal into memory, using the withdrawal hash as a unique identifier.
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
                _root: _outputRootProof.messagePasserStorageRoot
            }) == false
        ) {
            revert OptimismPortal_InvalidMerkleProof();
        }

        // Designate the withdrawalHash as proven by storing the disputeGameProxy and timestamp in
        // the provenWithdrawals mapping. A given user may re-prove a withdrawalHash multiple
        // times, but each proof will reset the proof timer.
        provenWithdrawals[withdrawalHash][msg.sender] =
            ProvenWithdrawal({ disputeGameProxy: disputeGameProxy, timestamp: uint64(block.timestamp) });

        // Add the proof submitter to the list of proof submitters for this withdrawal hash.
        proofSubmitters[withdrawalHash].push(msg.sender);

        // Emit a WithdrawalProven events.
        emit WithdrawalProven(withdrawalHash, _tx.sender, _tx.target);
        emit WithdrawalProvenExtension1(withdrawalHash, msg.sender);
    }

    /// @notice Finalizes a withdrawal transaction.
    /// @param _tx Withdrawal transaction to finalize.
    function finalizeWithdrawalTransaction(Types.WithdrawalTransaction memory _tx) external {
        finalizeWithdrawalTransactionExternalProof(_tx, msg.sender);
    }

    /// @notice Migrates the total ETH balance of this contract to the ETHLockbox. Custom gas
    ///         token chains keep custody in the portal and cannot migrate ETH.
    function migrateLiquidity() public {
        if (!_isUsingLockbox()) revert OptimismPortal_NotUsingLockbox();
        // Liquidity migration can only be triggered by the ProxyAdmin owner.
        _assertOnlyProxyAdminOwner();

        if (_isUsingCustomGasToken()) revert OptimismPortal_NotAllowedOnCGTMode();

        // Migrate the liquidity.
        uint256 ethBalance = address(this).balance;
        ethLockbox.lockETH{ value: ethBalance }();
        emit ETHMigrated(address(ethLockbox), ethBalance);
    }

    /// @notice Allows the owner of the ProxyAdmin to migrate the OptimismPortal to use a new
    ///         lockbox, point at a new AnchorStateRegistry, and start to use the Super Roots proof
    ///         method. Primarily used for OptimismPortal instances to join the interop set, but
    ///         can also be used to swap the proof method from Output Roots to Super Roots if the
    ///         provided lockbox is the same as the current one.
    /// @dev    It is possible to change lockboxes without migrating liquidity. This can cause one
    ///         of the OptimismPortal instances connected to the new lockbox to not be able to
    ///         unlock sufficient ETH to finalize withdrawals which would trigger reverts. To avoid
    ///         this issue, guarantee that this function is called atomically alongside the
    ///         ETHLockbox.migrateLiquidity() function within the same transaction.
    /// @param _newLockbox The address of the new ETHLockbox contract.
    /// @param _newAnchorStateRegistry The address of the new AnchorStateRegistry contract.

    function migrateToSharedDisputeGame(
        IETHLockbox _newLockbox,
        IAnchorStateRegistry _newAnchorStateRegistry
    )
        external
    {
        if (!_isUsingInterop()) revert OptimismPortal_NotUsingInterop();
        // Migration can only be triggered when the system is not paused because the migration can
        // potentially unpause the system as a result of the modified ETHLockbox address.
        _assertNotPaused();

        // Migration can only be triggered by the ProxyAdmin owner.
        _assertOnlyProxyAdminOwner();

        // Chains can use this method to swap the proof method from Output Roots to Super Roots
        // without joining the interop set. In this case, the old and new lockboxes will be the
        // same. However, whether or not a chain is joining the interop set, all chains will need a
        // new AnchorStateRegistry when migrating to Super Roots. We therefore check that the new
        // AnchorStateRegistry is different than the old one to prevent this function from being
        // accidentally misused.
        if (anchorStateRegistry == _newAnchorStateRegistry) {
            revert OptimismPortal_MigratingToSameRegistry();
        }

        // Defense-in-depth: reject obvious operator footguns. The ProxyAdmin owner is fully
        // trusted (can upgrade the portal), but these checks make it harder to brick the portal by
        // installing zero / non-contract / unauthorized / mis-wired addresses.
        if (address(_newLockbox) == address(0) || address(_newAnchorStateRegistry) == address(0)) {
            revert OptimismPortal_ZeroAddress();
        }
        if (!_newLockbox.authorizedPortals(IOptimismPortal2(payable(address(this))))) {
            revert OptimismPortal_LockboxNotAuthorizedForPortal();
        }

        // Update the ETHLockbox.
        IETHLockbox oldLockbox = ethLockbox;
        ethLockbox = _newLockbox;

        // Update the AnchorStateRegistry.
        IAnchorStateRegistry oldAnchorStateRegistry = anchorStateRegistry;
        anchorStateRegistry = _newAnchorStateRegistry;

        // Emit a PortalMigrated event.
        emit PortalMigrated(oldLockbox, _newLockbox, oldAnchorStateRegistry, _newAnchorStateRegistry);
    }

    /// @notice Finalizes a withdrawal transaction, using an external proof submitter.
    /// @param _tx Withdrawal transaction to finalize.
    /// @param _proofSubmitter Address of the proof submitter.
    function finalizeWithdrawalTransactionExternalProof(
        Types.WithdrawalTransaction memory _tx,
        address _proofSubmitter
    )
        public
    {
        // Cannot finalize withdrawal transactions while the system is paused.
        _assertNotPaused();

        // Cannot finalize withdrawal with value when custom gas token mode is enabled.
        if (_isUsingCustomGasToken()) {
            if (_tx.value > 0) revert OptimismPortal_NotAllowedOnCGTMode();
        }

        // Make sure that the l2Sender has not yet been set. The l2Sender is set to a value other
        // than the default value when a withdrawal transaction is being finalized. This check is
        // a defacto reentrancy guard. The hook call happens before l2Sender is set, so it carries
        // its own flag and is checked here too.
        if (l2Sender != Constants.DEFAULT_L2_SENDER || _inBridgeHook) {
            revert OptimismPortal_NoReentrancy();
        }

        // Make sure that the target address is safe.
        if (_isUnsafeTarget(_tx.target)) {
            revert OptimismPortal_BadTarget();
        }

        // Grab the withdrawal.
        bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);

        // Check that the withdrawal can be finalized.
        checkWithdrawal(withdrawalHash, _proofSubmitter);

        // Mark the withdrawal as finalized so it can't be replayed.
        finalizedWithdrawals[withdrawalHash] = true;

        // If using ETHLockbox, unlock the ETH from the ETHLockbox.
        if (_isUsingLockbox()) {
            if (_tx.value > 0) ethLockbox.unlockETH(_tx.value);
        }

        // Screen the withdrawal immediately before value would be released. Custody is taken here
        // and never earlier: a proven withdrawal is not a valid one, since its output root may
        // still be invalidated, so finalization is the first moment value can safely leave.
        //
        // Every withdrawal is screened, with or without ETH. A withdrawal carrying no value still
        // executes an arbitrary call on L1 chosen by an L2 sender, and this is the only place that
        // sees it. The one shape that passes without a verdict is a token withdrawal, which the
        // hook recognises and defers to the bridge because that is where its value moves and where
        // the parties arrive as typed arguments. Deciding that is the hook's business, not this
        // contract's.
        if (_isUsingBridgeHook()) {
            if (!_screenWithdrawal(withdrawalHash, _tx)) return;
        }

        // Set the l2Sender so contracts know who triggered this withdrawal on L2, and the
        // withdrawal hash so they know which withdrawal they are acting for.
        l2Sender = _tx.sender;
        _currentWithdrawalHash = withdrawalHash;

        // Trigger the call to the target contract. We use a custom low level method
        // SafeCall.callWithMinGas to ensure two key properties
        //   1. Target contracts cannot force this call to run out of gas by returning a very large
        //      amount of data (and this is OK because we don't care about the returndata here).
        //   2. The amount of gas provided to the execution context of the target is at least the
        //      gas limit specified by the user. If there is not enough gas in the current context
        //      to accomplish this, `callWithMinGas` will revert.
        bool success = SafeCall.callWithMinGas(_tx.target, _tx.gasLimit, _tx.value, _tx.data);

        // Reset the l2Sender back to the default value.
        l2Sender = Constants.DEFAULT_L2_SENDER;
        _currentWithdrawalHash = bytes32(0);

        // All withdrawals are immediately finalized. Replayability can
        // be achieved through contracts built on top of this contract
        emit WithdrawalFinalized(withdrawalHash, success);

        // If using ETHLockbox, send ETH back to the Lockbox in the case of a failed transaction or
        // it'll get stuck here and would need to be moved back via admin action.
        if (_isUsingLockbox()) {
            if (!success && _tx.value > 0) {
                ethLockbox.lockETH{ value: _tx.value }();
            }
        }

        // Reverting here is useful for determining the exact gas cost to successfully execute the
        // sub call to the target contract if the minimum gas limit specified by the user would not
        // be sufficient to execute the sub call.
        if (!success && tx.origin == Constants.ESTIMATION_ADDRESS) {
            revert OptimismPortal_GasEstimation();
        }
    }

    /// @notice Releases a withdrawal the bridge hook held, paying its original recipient. Only the
    ///         hook can call this.
    /// @dev The release re-enters the contract that would have paid on a stock chain because the
    ///      recipient-facing action has to come from the address the recipient expects. The
    ///      messenger forces it outright: `L1CrossDomainMessenger` accepts a `relayMessage` only
    ///      from this contract with the right `l2Sender`, and that is the target of essentially
    ///      every real user withdrawal, so the hook cannot replay it.
    ///
    ///      A failed release reverts. Stock finalization returns the ETH to the lockbox on a
    ///      failed call and leaves the withdrawal consumed, which is right there because it must
    ///      be consumed exactly once. Doing that here would put frozen value back into a protocol
    ///      contract and destroy a claim whose record the hook already deleted. Nothing is
    ///      consumed at release, so the release is atomic and anyone can retry.
    /// @param _tx The held withdrawal.
    function completeWithdrawalTransaction(Types.WithdrawalTransaction memory _tx) external payable {
        if (msg.sender != address(bridgeHook)) revert OptimismPortal_NotBridgeHook();

        // The hook is never a route for value the guardian has frozen. The hook checks this too,
        // but that is a check it must keep through every upgrade rather than a property this
        // contract enforces, so it is enforced here as well.
        _assertNotPaused();

        if (l2Sender != Constants.DEFAULT_L2_SENDER || _inBridgeHook) {
            revert OptimismPortal_NoReentrancy();
        }

        // The item is rebuilt through the same function the screening path used, so the two derive
        // the same identifier by construction. Requiring the commitment against it is what
        // verifies the terms. Nothing else about the withdrawal has to be re-checked: the proof,
        // the game, the maturity and the target were all checked when it was finalized.
        bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);
        bytes32 id = BridgeHookItem.hash(BridgeHookItem.fromWithdrawalTransaction(_tx, withdrawalHash));
        if (!heldWithdrawals[id]) revert OptimismPortal_UncommittedItem();
        if (msg.value != _tx.value) revert OptimismPortal_ItemValueMismatch();

        delete heldWithdrawals[id];
        outstandingBridgeHookItems--;

        l2Sender = _tx.sender;
        _currentWithdrawalHash = withdrawalHash;
        bool success = SafeCall.callWithMinGas(_tx.target, _tx.gasLimit, _tx.value, _tx.data);
        l2Sender = Constants.DEFAULT_L2_SENDER;
        _currentWithdrawalHash = bytes32(0);

        emit WithdrawalFinalized(withdrawalHash, success);

        if (!success) revert OptimismPortal_ReleaseFailed();
    }

    /// @notice Screens a withdrawal through the bridge hook and, on a hold, commits to its terms
    ///         and hands the ETH over.
    /// @dev The withdrawal is already marked finalized by the time this runs, so a hold consumes
    ///      it against the protocol whether or not it ever clears and the user's claim becomes a
    ///      claim on the hook. That is the intended effect of taking the value out of protocol
    ///      custody, and it has no deposit-side analogue.
    /// @return pass_ True if the withdrawal should be paid out here, false if it was held.
    function _screenWithdrawal(
        bytes32 _withdrawalHash,
        Types.WithdrawalTransaction memory _tx
    )
        internal
        returns (bool pass_)
    {
        Item memory item = BridgeHookItem.fromWithdrawalTransaction(_tx, _withdrawalHash);

        _inBridgeHook = true;
        pass_ = bridgeHook.screenWithdrawal(item);

        if (!pass_) {
            bytes32 id = BridgeHookItem.hash(item);
            heldWithdrawals[id] = true;
            outstandingBridgeHookItems++;
            emit WithdrawalHeld(_withdrawalHash, id);
            bridgeHook.holdWithdrawal{ value: _tx.value }(item);
        }
        _inBridgeHook = false;
    }

    /// @notice Checks that a withdrawal has been proven and is ready to be finalized.
    /// @param _withdrawalHash Hash of the withdrawal.
    /// @param _proofSubmitter Address of the proof submitter.
    function checkWithdrawal(bytes32 _withdrawalHash, address _proofSubmitter) public view {
        // Grab the withdrawal and dispute game proxy.
        ProvenWithdrawal memory provenWithdrawal = provenWithdrawals[_withdrawalHash][_proofSubmitter];
        IDisputeGame disputeGameProxy = provenWithdrawal.disputeGameProxy;

        // Check that this withdrawal has not already been finalized, this is replay protection.
        if (finalizedWithdrawals[_withdrawalHash]) {
            revert OptimismPortal_AlreadyFinalized();
        }

        // A withdrawal can only be finalized if it has been proven. We know that a withdrawal has
        // been proven at least once when its timestamp is non-zero. Unproven withdrawals will have
        // a timestamp of zero.
        if (provenWithdrawal.timestamp == 0) {
            revert OptimismPortal_Unproven();
        }

        // As a sanity check, we make sure that the proven withdrawal's timestamp is greater than
        // starting timestamp inside the Dispute Game. Not strictly necessary but extra layer of
        // safety against weird bugs in the proving step. Note that this blocks withdrawals that
        // are proven in the same block that a dispute game is created.
        if (provenWithdrawal.timestamp <= disputeGameProxy.createdAt().raw()) {
            revert OptimismPortal_InvalidProofTimestamp();
        }

        // A proven withdrawal must wait at least `PROOF_MATURITY_DELAY_SECONDS` before finalizing.
        if (block.timestamp - provenWithdrawal.timestamp <= PROOF_MATURITY_DELAY_SECONDS) {
            revert OptimismPortal_ProofNotOldEnough();
        }

        // Check that the root claim is valid.
        if (!anchorStateRegistry.isGameClaimValid(disputeGameProxy)) {
            revert OptimismPortal_InvalidRootClaim();
        }
    }

    /// @notice Deletes a withdrawal proof whose dispute game can never lead to finalization.
    ///         Permissionless because both conditions checked here are permanent.
    /// @param _withdrawalHash Hash of the withdrawal.
    /// @param _proofSubmitter Address of the proof submitter.
    function deleteProvenWithdrawal(bytes32 _withdrawalHash, address _proofSubmitter) external {
        ProvenWithdrawal memory provenWithdrawal = provenWithdrawals[_withdrawalHash][_proofSubmitter];
        if (provenWithdrawal.timestamp == 0) {
            revert OptimismPortal_Unproven();
        }

        IDisputeGame disputeGameProxy = provenWithdrawal.disputeGameProxy;
        if (
            disputeGameProxy.status() != GameStatus.CHALLENGER_WINS
                && !anchorStateRegistry.isGameBlacklisted(disputeGameProxy)
        ) {
            revert OptimismPortal_DisputeGameNotInvalidated();
        }

        delete provenWithdrawals[_withdrawalHash][_proofSubmitter];

        emit WithdrawalProofDeleted(_withdrawalHash, _proofSubmitter);
    }

    /// @notice Accepts deposits of ETH and data, and emits a TransactionDeposited event for use in
    ///         deriving deposit transactions. Note that if a deposit is made by a contract, its
    ///         address will be aliased when retrieved using `tx.origin` or `msg.sender`. Consider
    ///         using the CrossDomainMessenger contracts for a simpler developer experience.
    /// @dev    The `msg.value` is locked on the ETHLockbox and minted as ETH when the deposit
    ///         arrives on L2, while `_value` specifies how much ETH to send to the target.
    /// @param _to         Target address on L2.
    /// @param _value      ETH value to send to the recipient.
    /// @param _gasLimit   Amount of L2 gas to purchase by burning gas on L1.
    /// @param _isCreation Whether or not the transaction is a contract creation.
    /// @param _data       Data to trigger the recipient with.
    function depositTransaction(
        address _to,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes memory _data
    )
        public
        payable
        metered(_gasLimit)
    {
        if (_isUsingCustomGasToken()) {
            if (msg.value > 0) revert OptimismPortal_NotAllowedOnCGTMode();
        }

        // Just to be safe, make sure that people specify address(0) as the target when doing
        // contract creations.
        if (_isCreation && _to != address(0)) {
            revert OptimismPortal_BadTarget();
        }

        // Prevent depositing transactions that have too small of a gas limit. Users should pay
        // more for more resource usage.
        if (_gasLimit < minimumGasLimit(uint64(_data.length))) {
            revert OptimismPortal_GasLimitTooLow();
        }

        // Prevent the creation of deposit transactions that have too much calldata. This gives an
        // upper limit on the size of unsafe blocks over the p2p network. 120kb is chosen to ensure
        // that the transaction can fit into the p2p network policy of 128kb even though deposit
        // transactions are not gossipped over the p2p network.
        if (_data.length > 120_000) {
            revert OptimismPortal_CalldataTooLarge();
        }

        // Transform the from-address to its alias if the caller is a contract. Aliasing is applied
        // up front so that this derivation is untouched by the hook and completing a held deposit
        // is a verbatim emit of a sender the Portal itself derived.
        address from = msg.sender;
        bool aliased;
        if (!EOA.isSenderEOA()) {
            from = AddressAliasHelper.applyL1ToL2Alias(msg.sender);
            aliased = true;
        }

        // Screen the deposit. This runs after validation, so a hold can never exist for an item
        // that would have reverted, and before the ETH is locked, so the hold path never touches
        // the lockbox.
        //
        // Every deposit is screened, with or without value. This function is the force-inclusion
        // path, and covering transactions submitted directly to L1 is the whole reason the hook
        // exists, so exempting the ones that carry no ETH would leave arbitrary L2 execution
        // unscreened. Nothing needs to be held for such an item, only deferred: the completion
        // path emits a zero mint the same way it emits any other. Whether an item with nothing at
        // stake is interesting at all is the policy's judgment, not this contract's.
        if (_isUsingBridgeHook()) {
            // A deposit cannot be made from inside a hook call. The check sits here rather than at
            // the top of the function so that a chain with no hook pays nothing for it, and the
            // slot is already warm from resolving the hook address.
            if (_inBridgeHook) revert OptimismPortal_NoReentrancy();

            if (!_screenDeposit(from, aliased, _to, _value, _gasLimit, _isCreation, _data)) return;
        }

        _depositTransaction(from, _to, msg.value, _value, _gasLimit, _isCreation, _data);
    }

    /// @notice Completes a deposit that the bridge hook held. Only the hook can call this, and the
    ///         terms come from the re-supplied preimage rather than from the hook's word.
    /// @dev Two requirements are the security of the whole deposit path. The commitment proves the
    ///      user paid these terms at submission; the value check proves the hook actually returned
    ///      the ETH now. Together they make the mint exactly the ETH in hand, which is what the
    ///      stock deposit path gets for free by having no mint parameter at all.
    ///
    ///      Not metered, because the item was metered once at submission. Not gated on the pause,
    ///      because `depositTransaction` has no pause check either.
    /// @param _item The held deposit.
    function completeDepositTransaction(Item memory _item) external payable {
        if (msg.sender != address(bridgeHook)) revert OptimismPortal_NotBridgeHook();
        if (_inBridgeHook) revert OptimismPortal_NoReentrancy();

        bytes32 id = BridgeHookItem.hash(_item);
        if (!pendingDeposits[id]) revert OptimismPortal_UncommittedItem();
        if (msg.value != _item.amount) revert OptimismPortal_ItemValueMismatch();

        // Delete the commitment before any external call, so an item completes at most once.
        delete pendingDeposits[id];
        outstandingBridgeHookItems--;

        // `Item` carries the gas limit wide and the event emits it narrow. Every item this
        // contract commits to was built from a uint64, so the cast cannot lose anything today,
        // but a silent truncation here would complete a deposit on terms other than the ones
        // committed, which is the single thing this function exists to prevent.
        if (_item.gasLimit > type(uint64).max) revert OptimismPortal_GasLimitTooLow();

        _depositTransaction(
            _item.from, _item.to, msg.value, _item.value, uint64(_item.gasLimit), _item.isCreation, _item.data
        );
    }

    /// @notice Screens a deposit through the bridge hook and, on a hold, commits to its terms.
    /// @dev The identifier is derived here and by the hook from the same item through the same
    ///      library, so the two agree by construction and no caller can supply one that disagrees
    ///      with the terms.
    /// @return pass_ True if the deposit should proceed, false if it was held.
    function _screenDeposit(
        address _from,
        bool _aliased,
        address _to,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes memory _data
    )
        internal
        returns (bool pass_)
    {
        uint64 nonce = depositNonce;
        depositNonce = nonce + 1;

        Item memory item = Item({
            direction: Direction.Deposit,
            asset: Asset.ETH,
            from: _from,
            aliased: _aliased,
            to: _to,
            localToken: address(0),
            remoteToken: address(0),
            amount: msg.value,
            value: _value,
            gasLimit: _gasLimit,
            isCreation: _isCreation,
            data: _data,
            // A deposit has no reconstruction data and no protocol-assigned identity. Nothing
            // on chain distinguishes two identical deposits in the same block, so the counter is
            // the only uniqueness available.
            messageNonce: 0,
            uid: bytes32(uint256(nonce))
        });

        // The question carries no value. The ETH stays here unless the answer is hold, and only
        // then does it move, in a second call and after the terms are committed. The alternative,
        // handing the ETH over with the question and taking it back on a pass, would put every
        // depositor's ETH through the hook for no reason and oblige this contract to check that
        // it came back.
        _inBridgeHook = true;
        pass_ = bridgeHook.screenDeposit(item);

        if (!pass_) {
            bytes32 id = BridgeHookItem.hash(item);
            pendingDeposits[id] = true;
            outstandingBridgeHookItems++;
            emit DepositPending(id, nonce);

            // Committed first, handed over second, so the hook can never be holding value this
            // contract has not already written down the terms for.
            bridgeHook.holdDeposit{ value: msg.value }(item);
        }

        _inBridgeHook = false;
    }

    /// @notice Takes custody of a deposit's ETH and emits the TransactionDeposited event the rollup
    ///         node derives the deposit from. Common tail of both deposit entry points.
    /// @dev Only the effect is shared, never the validation. A submission validates its terms and
    ///      pays for them; a completion replays terms a commitment already fixed, so re-running the
    ///      checks would at best re-derive what the commitment settled, and the Custom Gas Token
    ///      check would be worse than redundant: it reads a SystemConfig flag, so flipping the
    ///      chain into CGT mode while an item is held would leave its ETH with no way out.
    ///
    ///      `_mint` is both locked and announced here, which is what makes the mint backed. The
    ///      stock path cannot express an unbacked mint because there the mint *is* `msg.value`;
    ///      taking one parameter for both keeps that property once the two are decoupled. Callers
    ///      must therefore establish that the ETH in hand equals `_mint`: `depositTransaction`
    ///      passes `msg.value` itself, and `completeDepositTransaction` proves the equality.
    /// @param _from       Sender of the deposit, already aliased if it needed to be.
    /// @param _to         Target address on L2.
    /// @param _mint       ETH to lock on L1 and mint on L2. Must equal the ETH in hand.
    /// @param _value      ETH value to send to the recipient.
    /// @param _gasLimit   Amount of L2 gas purchased for the deposit.
    /// @param _isCreation Whether or not the transaction is a contract creation.
    /// @param _data       Data to trigger the recipient with.
    function _depositTransaction(
        address _from,
        address _to,
        uint256 _mint,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes memory _data
    )
        internal
    {
        // If using ETHLockbox, lock the ETH in the ETHLockbox.
        if (_isUsingLockbox()) {
            if (_mint > 0) ethLockbox.lockETH{ value: _mint }();
        }

        // Compute the opaque data that will be emitted as part of the TransactionDeposited event.
        // We use opaque data so that we can update the TransactionDeposited event in the future
        // without breaking the current interface.
        bytes memory opaqueData = abi.encodePacked(_mint, _value, _gasLimit, _isCreation, _data);

        // Emit a TransactionDeposited event so that the rollup node can derive a deposit
        // transaction for this deposit.
        emit TransactionDeposited(_from, _to, DEPOSIT_VERSION, opaqueData);
    }

    /// @notice External getter for the number of proof submitters for a withdrawal hash.
    /// @param _withdrawalHash Hash of the withdrawal.
    /// @return The number of proof submitters for the withdrawal hash.
    function numProofSubmitters(bytes32 _withdrawalHash) external view returns (uint256) {
        return proofSubmitters[_withdrawalHash].length;
    }

    /// @notice Checks if the ETHLockbox feature is enabled.
    /// @return bool True if the ETHLockbox feature is enabled.
    function _isUsingLockbox() internal view returns (bool) {
        return systemConfig.isFeatureEnabled(Features.ETH_LOCKBOX) && address(ethLockbox) != address(0);
    }

    /// @notice Checks if the bridge hook feature is enabled and a hook is configured.
    /// @dev The local address is read first on purpose. A chain with no hook then pays one SLOAD
    ///      and never makes the external call to SystemConfig.
    /// @return bool True if the Portal should defer to a bridge hook.
    function _isUsingBridgeHook() internal view returns (bool) {
        return address(bridgeHook) != address(0) && systemConfig.isFeatureEnabled(Features.BRIDGE_HOOK);
    }

    /// @notice Checks if the Interop feature is enabled.
    /// @return bool True if the Interop feature is enabled.
    function _isUsingInterop() internal view returns (bool) {
        return systemConfig.isFeatureEnabled(Features.INTEROP) && systemConfig.isFeatureEnabled(Features.ETH_LOCKBOX);
    }

    /// @notice Checks if the Custom Gas Token feature is enabled.
    /// @return bool True if the Custom Gas Token feature is enabled.
    function _isUsingCustomGasToken() internal view returns (bool) {
        // NOTE: Chains are not supposed to enable Custom Gas Token (CGT) mode after initial deployment.
        //       Enabling CGT post-deployment is strongly discouraged and may lead to unexpected behavior.
        return systemConfig.isFeatureEnabled(Features.CUSTOM_GAS_TOKEN);
    }

    /// @notice Asserts that the contract is not paused.
    function _assertNotPaused() internal view {
        if (paused()) {
            revert OptimismPortal_CallPaused();
        }
    }

    /// @notice Asserts the ETHLockbox feature flag must be set if INTEROP is set
    function _assertValidInteropState() internal view {
        if (systemConfig.isFeatureEnabled(Features.INTEROP) && !systemConfig.isFeatureEnabled(Features.ETH_LOCKBOX)) {
            revert OptimismPortal_InvalidInteropState();
        }
    }

    /// @notice Asserts that the ETHLockbox is configured.
    function _assertValidLockboxState() internal view {
        if (!systemConfig.isFeatureEnabled(Features.ETH_LOCKBOX) || address(ethLockbox) == address(0)) {
            revert OptimismPortal_InvalidLockboxState();
        }
    }

    /// @notice Checks if a target address is unsafe.
    function _isUnsafeTarget(address _target) internal view virtual returns (bool) {
        // Prevent users from targeting an unsafe target address on a withdrawal transaction. The
        // bridge hook is included for the same reason as the lockbox: it holds value, and a
        // withdrawal must not be able to call into it with l2Sender set by this contract.
        return _target == address(this) || _target == address(ethLockbox) || _target == address(bridgeHook);
    }

    /// @notice Getter for the resource config. Used internally by the ResourceMetering contract.
    ///         The SystemConfig is the source of truth for the resource config.
    /// @return config_ ResourceMetering ResourceConfig
    function _resourceConfig() internal view override returns (ResourceMetering.ResourceConfig memory config_) {
        IResourceMetering.ResourceConfig memory config = systemConfig.resourceConfig();
        assembly ("memory-safe") {
            config_ := config
        }
    }
}
