// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ResourceMetering } from "src/L1/ResourceMetering.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";
import { Constants } from "src/libraries/Constants.sol";
import { Types } from "src/libraries/Types.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { SecureMerkleTrie } from "src/libraries/trie/SecureMerkleTrie.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { AddressAliasHelper } from "src/vendor/AddressAliasHelper.sol";
import {
    BadTarget,
    LargeCalldata,
    SmallGasLimit,
    Unauthorized,
    CallPaused,
    GasEstimation,
    NonReentrant,
    InvalidProof,
    InvalidGameType,
    InvalidDisputeGame,
    InvalidMerkleProof,
    Blacklisted,
    Unproven,
    ProposalNotValidated,
    AlreadyFinalized,
    LegacyGame
} from "src/libraries/PortalErrors.sol";
import { GameStatus, GameType, Claim, Timestamp } from "src/dispute/lib/Types.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { IResourceMetering } from "interfaces/L1/IResourceMetering.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { IL1Block } from "interfaces/L2/IL1Block.sol";
import { ISharedLockbox } from "interfaces/L1/ISharedLockbox.sol";
import { IL1BlockInterop } from "interfaces/L2/IL1BlockInterop.sol";
import { ISuperchainConfigInterop } from "interfaces/L1/ISuperchainConfigInterop.sol";

/// @notice Error thrown when attempting to use custom gas token specific actions.
error CustomGasTokenNotSupported();

/// @title OptimismPortalMock
/// @notice This contract replicates the OptimismPortal2 logic, with the exception of the `proveWithdrawalTransaction`
///         function - where the input parameters are stored without any check as if the withdrawal was proven.
contract OptimismPortal2Mock is Initializable, ResourceMetering, ISemver {
    /// @notice Allows for interactions with non standard ERC20 tokens.
    using SafeERC20 for IERC20;

    /// @notice Represents a proven withdrawal.
    /// @custom:field disputeGameProxy The address of the dispute game proxy that the withdrawal was proven against.
    /// @custom:field timestamp        Timestamp at which the withdrawal was proven.
    struct ProvenWithdrawal {
        IDisputeGame disputeGameProxy;
        uint64 timestamp;
    }

    /// @notice The delay between when a withdrawal transaction is proven and when it may be finalized.
    uint256 internal immutable PROOF_MATURITY_DELAY_SECONDS;

    /// @notice The delay between when a dispute game is resolved and when a withdrawal proven against it may be
    ///         finalized.
    uint256 internal immutable DISPUTE_GAME_FINALITY_DELAY_SECONDS;

    /// @notice Version of the deposit event.
    uint256 internal constant DEPOSIT_VERSION = 0;

    /// @notice The L2 gas limit set when eth is deposited using the receive() function.
    uint64 internal constant RECEIVE_DEFAULT_GAS_LIMIT = 100_000;

    /// @notice The L2 gas limit for system deposit transactions that are initiated from L1.
    uint32 internal constant SYSTEM_DEPOSIT_GAS_LIMIT = 200_000;

    /// @notice Address of the L2 account which initiated a withdrawal in this transaction.
    ///         If the of this variable is the default L2 sender address, then we are NOT inside of
    ///         a call to finalizeWithdrawalTransaction.
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

    /// @notice Contract of the Superchain Config.
    ISuperchainConfig public superchainConfig;

    /// @custom:legacy
    /// @custom:spacer l2Oracle
    /// @notice Spacer taking up the legacy `l2Oracle` address slot.
    address private spacer_54_0_20;

    /// @notice Contract of the SystemConfig.
    /// @custom:network-specific
    ISystemConfig public systemConfig;

    /// @notice Address of the DisputeGameFactory.
    /// @custom:network-specific
    IDisputeGameFactory public disputeGameFactory;

    /// @notice A mapping of withdrawal hashes to proof submitters to `ProvenWithdrawal` data.
    mapping(bytes32 => mapping(address => ProvenWithdrawal)) public provenWithdrawals;

    /// @notice A mapping of dispute game addresses to whether or not they are blacklisted.
    mapping(IDisputeGame => bool) public disputeGameBlacklist;

    /// @notice The game type that the OptimismPortal consults for output proposals.
    GameType public respectedGameType;

    /// @notice The timestamp at which the respected game type was last updated.
    uint64 public respectedGameTypeUpdatedAt;

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
    /// @notice Spacer taking up the legacy `_balance` slot.
    uint256 private spacer_61_0_32;

    /// @notice Emitted when a transaction is deposited from L1 to L2.
    ///         The parameters of this event are read by the rollup node and used to derive deposit
    ///         transactions on L2.
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

    /// @notice Emitted when a withdrawal transaction is proven. Exists as a separate event to allow for backwards
    ///         compatibility for tooling that observes the `WithdrawalProven` event.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param proofSubmitter Address of the proof submitter.
    event WithdrawalProvenExtension1(bytes32 indexed withdrawalHash, address indexed proofSubmitter);

    /// @notice Emitted when a withdrawal transaction is finalized.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    /// @param success        Whether the withdrawal transaction was successful.
    event WithdrawalFinalized(bytes32 indexed withdrawalHash, bool success);

    /// @notice Emitted when a dispute game is blacklisted by the Guardian.
    /// @param disputeGame Address of the dispute game that was blacklisted.
    event DisputeGameBlacklisted(IDisputeGame indexed disputeGame);

    /// @notice Emitted when the Guardian changes the respected game type in the portal.
    /// @param newGameType The new respected game type.
    /// @param updatedAt   The timestamp at which the respected game type was updated.
    event RespectedGameTypeSet(GameType indexed newGameType, Timestamp indexed updatedAt);

    /// @notice Reverts when paused.
    modifier whenNotPaused() {
        if (paused()) revert CallPaused();
        _;
    }

    /// @notice Semantic version.
    /// @custom:semver 3.12.0-beta.2
    function version() public pure virtual returns (string memory) {
        return "3.12.0-beta.2";
    }

    /// @notice Constructs the OptimismPortal contract.
    constructor(uint256 _proofMaturityDelaySeconds, uint256 _disputeGameFinalityDelaySeconds) {
        PROOF_MATURITY_DELAY_SECONDS = _proofMaturityDelaySeconds;
        DISPUTE_GAME_FINALITY_DELAY_SECONDS = _disputeGameFinalityDelaySeconds;

        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _DISPUTE_GAME_FACTORY Contract of the DisputeGameFactory.
    /// @param _systemConfig Contract of the SystemConfig.
    /// @param _superchainConfig Contract of the SuperchainConfig.
    /// @param _initialRespectedGameType Initial game type to be respected.
    function initialize(
        IDisputeGameFactory _DISPUTE_GAME_FACTORY,
        ISystemConfig _systemConfig,
        ISuperchainConfig _superchainConfig,
        GameType _initialRespectedGameType
    )
        external
        virtual
        initializer
    {
        _initialize(_DISPUTE_GAME_FACTORY, _systemConfig, _superchainConfig, _initialRespectedGameType);
    }

    /// @notice Internal initializer function.
    /// @param _DISPUTE_GAME_FACTORY Contract of the DisputeGameFactory.
    /// @param _systemConfig Contract of the SystemConfig.
    /// @param _superchainConfig Contract of the SuperchainConfig.
    /// @param _initialRespectedGameType Initial game type to be respected.
    function _initialize(
        IDisputeGameFactory _DISPUTE_GAME_FACTORY,
        ISystemConfig _systemConfig,
        ISuperchainConfig _superchainConfig,
        GameType _initialRespectedGameType
    )
        internal
    {
        disputeGameFactory = _DISPUTE_GAME_FACTORY;
        systemConfig = _systemConfig;
        superchainConfig = _superchainConfig;

        // Set the `l2Sender` slot, only if it is currently empty. This signals the first initialization of the
        // contract.
        if (l2Sender == address(0)) {
            l2Sender = Constants.DEFAULT_L2_SENDER;

            // Set the `respectedGameTypeUpdatedAt` timestamp, to ignore all games of the respected type prior
            // to this operation.
            respectedGameTypeUpdatedAt = uint64(block.timestamp);

            // Set the initial respected game type
            respectedGameType = _initialRespectedGameType;
        }

        __ResourceMetering_init();
    }

    /// @notice Getter function for the address of the guardian.
    ///         Public getter is legacy and will be removed in the future. Use `SuperchainConfig.guardian()` instead.
    /// @return Address of the guardian.
    /// @custom:legacy
    function guardian() public view returns (address) {
        return superchainConfig.guardian();
    }

    /// @notice Getter for the current paused status.
    function paused() public view returns (bool) {
        return superchainConfig.paused();
    }

    /// @notice Getter for the proof maturity delay.
    function proofMaturityDelaySeconds() public view returns (uint256) {
        return PROOF_MATURITY_DELAY_SECONDS;
    }

    /// @notice Getter for the dispute game finality delay.
    function disputeGameFinalityDelaySeconds() public view returns (uint256) {
        return DISPUTE_GAME_FINALITY_DELAY_SECONDS;
    }

    /// @notice Computes the minimum gas limit for a deposit.
    ///         The minimum gas limit linearly increases based on the size of the calldata.
    ///         This is to prevent users from creating L2 resource usage without paying for it.
    ///         This function can be used when interacting with the portal to ensure forwards
    ///         compatibility.
    /// @param _byteCount Number of bytes in the calldata.
    /// @return The minimum gas limit for a deposit.
    function minimumGasLimit(uint64 _byteCount) public pure returns (uint64) {
        return _byteCount * 16 + 21000;
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

    /// @notice Getter for the resource config.
    ///         Used internally by the ResourceMetering contract.
    ///         The SystemConfig is the source of truth for the resource config.
    /// @return config_ ResourceMetering ResourceConfig
    function _resourceConfig() internal view override returns (ResourceMetering.ResourceConfig memory config_) {
        IResourceMetering.ResourceConfig memory config = systemConfig.resourceConfig();
        assembly ("memory-safe") {
            config_ := config
        }
    }

    /// @notice Validates a withdrawal before it is proved or finalized.
    /// @param _tx Withdrawal transaction to validate.
    function _validateWithdrawal(Types.WithdrawalTransaction memory _tx) internal view virtual {
        // Prevent users from creating a deposit transaction where this address is the message
        // sender on L2. Because this is checked here, we do not need to check again in
        // `finalizeWithdrawalTransaction`.
        if (_tx.target == address(this)) revert BadTarget();
    }

    /// @notice Proves a withdrawal transaction.
    /// @param _tx               Withdrawal transaction to finalize.
    function proveWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        uint256,
        Types.OutputRootProof calldata,
        bytes[] calldata
    )
        external
        whenNotPaused
    {
        // Validate the withdrawal before it is proved.
        _validateWithdrawal(_tx);

        // Prevent users from creating a deposit transaction where this address is the message
        // sender on L2. Because this is checked here, we do not need to check again in
        // `finalizeWithdrawalTransaction`.
        if (_tx.target == address(this)) revert BadTarget();

        // Load the ProvenWithdrawal into memory, using the withdrawal hash as a unique identifier.
        bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);

        // Designate the withdrawalHash as proven by storing the `disputeGameProxy` & `timestamp` in the
        // `provenWithdrawals` mapping. A `withdrawalHash` can only be proven once unless the dispute game it proved
        // against resolves against the favor of the root claim.
        // disputeGameProxy is not used in this mock finalizationWithdrawalTransaction()
        provenWithdrawals[withdrawalHash][msg.sender] =
            ProvenWithdrawal({ disputeGameProxy: IDisputeGame(address(0)), timestamp: uint64(block.timestamp) });

        // Emit a `WithdrawalProven` event.
        emit WithdrawalProven(withdrawalHash, _tx.sender, _tx.target);
        // Emit a `WithdrawalProvenExtension1` event.
        emit WithdrawalProvenExtension1(withdrawalHash, msg.sender);

        // Add the proof submitter to the list of proof submitters for this withdrawal hash.
        proofSubmitters[withdrawalHash].push(msg.sender);
    }

    /// @notice Finalizes a withdrawal transaction.
    /// @param _tx Withdrawal transaction to finalize.
    /// @return success_ Used to track the success of the call on testing campaign.
    function finalizeWithdrawalTransaction(Types.WithdrawalTransaction memory _tx)
        external
        whenNotPaused
        returns (bool success_)
    {
        return finalizeWithdrawalTransactionExternalProof(_tx, msg.sender);
    }

    /// @notice Finalizes a withdrawal transaction, using an external proof submitter.
    /// @param _tx Withdrawal transaction to finalize.
    /// @param _proofSubmitter Address of the proof submitter.
    function finalizeWithdrawalTransactionExternalProof(
        Types.WithdrawalTransaction memory _tx,
        address _proofSubmitter
    )
        public
        whenNotPaused
        returns (bool success_)
    {
        // Make sure that the l2Sender has not yet been set. The l2Sender is set to a value other
        // than the default value when a withdrawal transaction is being finalized. This check is
        // a defacto reentrancy guard.
        if (l2Sender != Constants.DEFAULT_L2_SENDER) revert NonReentrant();

        // Compute the withdrawal hash.
        bytes32 withdrawalHash = Hashing.hashWithdrawal(_tx);

        // Check that the withdrawal can be finalized.
        checkWithdrawal(withdrawalHash, _proofSubmitter);

        // Mark the withdrawal as finalized so it can't be replayed.
        finalizedWithdrawals[withdrawalHash] = true;

        // Set the l2Sender so contracts know who triggered this withdrawal on L2.
        l2Sender = _tx.sender;

        // This function unlocks ETH from the SharedLockbox when using the OptimismPortalInterop contract.
        // If the interop version is not used, this function is a no-ops.
        _unlockETH(_tx);

        // Trigger the call to the target contract. We use a custom low level method
        // SafeCall.callWithMinGas to ensure two key properties
        //   1. Target contracts cannot force this call to run out of gas by returning a very large
        //      amount of data (and this is OK because we don't care about the returndata here).
        //   2. The amount of gas provided to the execution context of the target is at least the
        //      gas limit specified by the user. If there is not enough gas in the current context
        //      to accomplish this, `callWithMinGas` will revert.
        success_ = SafeCall.callWithMinGas(_tx.target, _tx.gasLimit, _tx.value, _tx.data);

        // Reset the l2Sender back to the default value.
        l2Sender = Constants.DEFAULT_L2_SENDER;

        // All withdrawals are immediately finalized. Replayability can
        // be achieved through contracts built on top of this contract
        emit WithdrawalFinalized(withdrawalHash, success_);

        // Reverting here is useful for determining the exact gas cost to successfully execute the
        // sub call to the target contract if the minimum gas limit specified by the user would not
        // be sufficient to execute the sub call.
        if (!success_ && tx.origin == Constants.ESTIMATION_ADDRESS) {
            revert GasEstimation();
        }
    }

    /// @notice Accepts deposits of ETH and data, and emits a TransactionDeposited event for use in
    ///         deriving deposit transactions. Note that if a deposit is made by a contract, its
    ///         address will be aliased when retrieved using `tx.origin` or `msg.sender`. Consider
    ///         using the CrossDomainMessenger contracts for a simpler developer experience.
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
        // This function locks ETH in the SharedLockbox when using the OptimismPortalInterop contract.
        // If the interop version is not used, this function is a no-ops.
        _lockETH();

        // Just to be safe, make sure that people specify address(0) as the target when doing
        // contract creations.
        if (_isCreation && _to != address(0)) revert BadTarget();

        // Prevent depositing transactions that have too small of a gas limit. Users should pay
        // more for more resource usage.
        if (_gasLimit < minimumGasLimit(uint64(_data.length))) revert SmallGasLimit();

        // Prevent the creation of deposit transactions that have too much calldata. This gives an
        // upper limit on the size of unsafe blocks over the p2p network. 120kb is chosen to ensure
        // that the transaction can fit into the p2p network policy of 128kb even though deposit
        // transactions are not gossipped over the p2p network.
        if (_data.length > 120_000) revert LargeCalldata();

        // Transform the from-address to its alias if the caller is a contract.
        address from = msg.sender;
        if (msg.sender != tx.origin) {
            from = AddressAliasHelper.applyL1ToL2Alias(msg.sender);
        }

        // Compute the opaque data that will be emitted as part of the TransactionDeposited event.
        // We use opaque data so that we can update the TransactionDeposited event in the future
        // without breaking the current interface.
        bytes memory opaqueData = abi.encodePacked(msg.value, _value, _gasLimit, _isCreation, _data);

        // Emit a TransactionDeposited event so that the rollup node can derive a deposit
        // transaction for this deposit.
        emit TransactionDeposited(from, _to, DEPOSIT_VERSION, opaqueData);
    }

    /// @notice Blacklists a dispute game. Should only be used in the event that a dispute game resolves incorrectly.
    /// @param _disputeGame Dispute game to blacklist.
    function blacklistDisputeGame(IDisputeGame _disputeGame) external {
        if (msg.sender != guardian()) revert Unauthorized();
        disputeGameBlacklist[_disputeGame] = true;
        emit DisputeGameBlacklisted(_disputeGame);
    }

    /// @notice Sets the respected game type. Changing this value can alter the security properties of the system,
    ///         depending on the new game's behavior.
    /// @param _gameType The game type to consult for output proposals.
    function setRespectedGameType(GameType _gameType) external {
        if (msg.sender != guardian()) revert Unauthorized();
        // respectedGameTypeUpdatedAt is now no longer set by default. We want to avoid modifying
        // this function's signature as that would result in changes to the DeputyGuardianModule.
        // We use type(uint32).max as a temporary solution to allow us to update the
        // respectedGameTypeUpdatedAt timestamp without modifying this function's signature.
        if (_gameType.raw() == type(uint32).max) {
            respectedGameTypeUpdatedAt = uint64(block.timestamp);
        } else {
            respectedGameType = _gameType;
        }
        emit RespectedGameTypeSet(respectedGameType, Timestamp.wrap(respectedGameTypeUpdatedAt));
    }

    /// @notice Checks if a withdrawal can be finalized. This function will revert if the withdrawal cannot be
    ///         finalized, and otherwise has no side-effects.
    /// @param _withdrawalHash Hash of the withdrawal to check.
    /// @param _proofSubmitter The submitter of the proof for the withdrawal hash
    function checkWithdrawal(bytes32 _withdrawalHash, address _proofSubmitter) public view {
        ProvenWithdrawal memory provenWithdrawal = provenWithdrawals[_withdrawalHash][_proofSubmitter];

        // A withdrawal can only be finalized if it has been proven. We know that a withdrawal has
        // been proven at least once when its timestamp is non-zero. Unproven withdrawals will have
        // a timestamp of zero.
        if (provenWithdrawal.timestamp == 0) revert Unproven();

        // Check that this withdrawal has not already been finalized, this is replay protection.
        if (finalizedWithdrawals[_withdrawalHash]) revert AlreadyFinalized();
    }

    /// @notice External getter for the number of proof submitters for a withdrawal hash.
    /// @param _withdrawalHash Hash of the withdrawal.
    /// @return The number of proof submitters for the withdrawal hash.
    function numProofSubmitters(bytes32 _withdrawalHash) external view returns (uint256) {
        return proofSubmitters[_withdrawalHash].length;
    }

    /// @notice No-op function to be used to lock ETH in the SharedLockbox in the interop contract.
    function _lockETH() internal virtual { }

    /// @notice No-op function to be used to unlock ETH from the SharedLockbox in the interop contract.
    /// @param _tx Withdrawal transaction to finalize.
    function _unlockETH(Types.WithdrawalTransaction memory _tx) internal virtual { }
}

contract OptimismPortalInteropMock is OptimismPortal2Mock {
    /// @notice Emitted when the contract migrates the ETH liquidity to the SharedLockbox.
    /// @param amount Amount of ETH migrated.
    event ETHMigrated(uint256 amount);

    /// @notice Error thrown when the withdrawal target is the SharedLockbox.
    error MessageTargetSharedLockbox();

    /// @notice Storage slot that the OptimismPortalStorage struct is stored at.
    /// keccak256(abi.encode(uint256(keccak256("optimismPortal.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant OPTIMISM_PORTAL_STORAGE_SLOT =
        0x554bed1aae13f6a1ca3b124bc567e2e458d6903a211d2d3a4ec21fca3b2b6c00;

    /// @notice Storage struct for the OptimismPortal specific storage data.
    /// @custom:storage-location erc7201:OptimismPortal.storage
    struct OptimismPortalStorage {
        /// @notice The address of the SharedLockbox.
        address sharedLockbox;
        /// @notice A flag indicating whether the contract has migrated the ETH liquidity to the SharedLockbox.
        bool migrated;
    }

    /// @notice Returns the storage for the OptimismPortalStorage.
    function _storage() private pure returns (OptimismPortalStorage storage storage_) {
        assembly {
            storage_.slot := OPTIMISM_PORTAL_STORAGE_SLOT
        }
    }

    constructor(
        uint256 _proofMaturityDelaySeconds,
        uint256 _disputeGameFinalityDelaySeconds
    )
        OptimismPortal2Mock(_proofMaturityDelaySeconds, _disputeGameFinalityDelaySeconds)
    { }

    /// @custom:semver +interop-beta.11
    function version() public pure override returns (string memory) {
        return string.concat(super.version(), "+interop-beta.11");
    }

    /// @notice Initializer.
    /// @param _DISPUTE_GAME_FACTORY Contract of the DisputeGameFactory.
    /// @param _systemConfig Contract of the SystemConfig.
    /// @param _superchainConfig Contract of the SuperchainConfig.
    /// @param _initialRespectedGameType Initial game type to be respected.
    function initialize(
        IDisputeGameFactory _DISPUTE_GAME_FACTORY,
        ISystemConfig _systemConfig,
        ISuperchainConfig _superchainConfig,
        GameType _initialRespectedGameType
    )
        external
        override
        initializer
    {
        _initialize(_DISPUTE_GAME_FACTORY, _systemConfig, _superchainConfig, _initialRespectedGameType);

        OptimismPortalStorage storage s = _storage();
        s.sharedLockbox = address(ISuperchainConfigInterop(address(_superchainConfig)).sharedLockbox());
    }

    /// @notice Getter for the address of the shared lockbox.
    function sharedLockbox() external view returns (ISharedLockbox) {
        return ISharedLockbox(_storage().sharedLockbox);
    }

    /// @notice Getter for the migrated flag.
    function migrated() external view returns (bool) {
        return _storage().migrated;
    }

    /// @notice Validates a withdrawal before it is proved or finalized.
    /// @param _tx Withdrawal transaction to validate.
    function _validateWithdrawal(Types.WithdrawalTransaction memory _tx) internal view virtual override {
        super._validateWithdrawal(_tx);

        OptimismPortalStorage storage s = _storage();

        // We don't allow the SharedLockbox to be the target of a withdrawal.
        // This is to prevent the SharedLockbox from being drained.
        // This check needs to be done for every withdrawal.
        if (_tx.target == s.sharedLockbox) revert MessageTargetSharedLockbox();
    }

    /// @notice Unlock and receive the ETH from the SharedLockbox.
    /// @param _tx Withdrawal transaction to finalize.
    function _unlockETH(Types.WithdrawalTransaction memory _tx) internal virtual override {
        OptimismPortalStorage storage s = _storage();

        // If ETH liquidity has not been migrated to the SharedLockbox yet, maintain legacy behavior
        // where ETH accumulates in the portal contract itself rather than being managed by the lockbox
        if (!s.migrated) return;

        // Skip calling the lockbox if the withdrawal value is 0 since there is no ETH to unlock
        if (_tx.value == 0) return;

        ISharedLockbox(s.sharedLockbox).unlockETH(_tx.value);
    }

    /// @notice Locks the ETH in the SharedLockbox.
    function _lockETH() internal virtual override {
        // Skip calling the lockbox if the deposit value is 0 since there is no ETH to lock
        if (msg.value == 0) return;

        // If ETH liquidity has not been migrated to the SharedLockbox yet, maintain legacy behavior
        // where ETH accumulates in the portal contract itself rather than being managed by the lockbox
        OptimismPortalStorage storage s = _storage();
        if (!s.migrated) return;

        ISharedLockbox(s.sharedLockbox).lockETH{ value: msg.value }();
    }

    /// @notice Migrates the ETH liquidity to the SharedLockbox. This function will only be called once by the
    ///         SuperchainConfig when adding this chain to the dependency set.
    function migrateLiquidity() external {
        if (msg.sender != address(superchainConfig)) revert Unauthorized();

        OptimismPortalStorage storage s = _storage();
        s.migrated = true;

        uint256 ethBalance = address(this).balance;

        ISharedLockbox(s.sharedLockbox).lockETH{ value: ethBalance }();

        emit ETHMigrated(ethBalance);
    }
}
