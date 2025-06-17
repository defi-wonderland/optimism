// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Encoding } from "src/libraries/Encoding.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { TransientReentrancyAware } from "src/libraries/TransientContext.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossL2Inbox, Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { ICrossMessageBundler } from "interfaces/L2/ICrossMessageBundler.sol";
import { IBundleRelayer } from "interfaces/L2/IBundleRelayer.sol";

/// @notice Thrown when a non-written slot in transient storage is attempted to be read from.
error NotEntered();

/// @notice Thrown when attempting to relay a message where payload origin is not L2ToL2CrossDomainMessenger.
error IdOriginNotL2ToL2CrossDomainMessenger();

/// @notice Thrown when the payload provided to the relay is not a SentMessage event.
error EventPayloadNotSentMessage();

/// @notice Thrown when attempting to send a message to the chain that the message is being sent from.
error MessageDestinationSameChain();

/// @notice Thrown when attempting to relay a message whose destination chain is not the chain relaying it.
error MessageDestinationNotRelayChain();

/// @notice Thrown when attempting to relay a message that has an entrypoint defined but is not being relayed from that
///         address.
error MessageEntrypointNotCaller();

/// @notice Thrown when attempting to relay a message whose target is L2ToL2CrossDomainMessenger.
error MessageTargetL2ToL2CrossDomainMessenger();

/// @notice Thrown when attempting to relay a message that has already been relayed.
error MessageAlreadyRelayed();

/// @notice Thrown when a reentrant call is detected.
error ReentrantCall();

/// @notice Thrown when the provided message parameters do not match any hash of a previously sent message.
error InvalidMessage();

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000023
/// @title L2ToL2CrossDomainMessenger
/// @notice The L2ToL2CrossDomainMessenger is a higher level abstraction on top of the CrossL2Inbox that provides
///         features necessary for secure transfers ERC20 tokens between L2 chains. Messages sent through the
///         L2ToL2CrossDomainMessenger on the source chain receive both replay protection as well as domain binding.
contract L2ToL2CrossDomainMessenger is ISemver, TransientReentrancyAware {
    /// @notice Storage slot for the sender of the current cross domain message.
    ///         Equal to bytes32(uint256(keccak256("l2tol2crossdomainmessenger.sender")) - 1)
    bytes32 internal constant CROSS_DOMAIN_MESSAGE_SENDER_SLOT =
        0xb83444d07072b122e2e72a669ce32857d892345c19856f4e7142d06a167ab3f3;

    /// @notice Storage slot for the source of the current cross domain message.
    ///         Equal to bytes32(uint256(keccak256("l2tol2crossdomainmessenger.source")) - 1)
    bytes32 internal constant CROSS_DOMAIN_MESSAGE_SOURCE_SLOT =
        0x711dfa3259c842fffc17d6e1f1e0fc5927756133a2345ca56b4cb8178589fee7;

    /// @notice Storage slot for the entrypoint of the current cross domain message.
    ///         Equal to bytes32(uint256(keccak256("l2tol2crossdomainmessenger.entrypoint")) - 1)
    bytes32 internal constant CROSS_DOMAIN_MESSAGE_ENTRYPOINT_SLOT =
        0x4f785a87c3805277007014d2b9bc19a6bf5d719f15bbf276e96c0e164571d512;

    /// @notice Storage slot for the current entrypoint depth.
    ///         Equal to bytes32(uint256(keccak256("l2tol2crossdomainmessenger.entrypointDepth")) - 1)
    bytes32 internal constant ENTRYPOINT_DEPTH_SLOT = 0x9f81af2e5421aeedf35d1553557543a8dfc18543a8386a619c17fce34086b462;

    /// @notice Event selector for the SentMessage event. Will be removed in favor of reading
    //          the `selector` property directly once crytic/slithe/#2566 is fixed.
    bytes32 internal constant SENT_MESSAGE_EVENT_SELECTOR =
        0x65f7fa83885abdbef9cab58474f555aa731b64afad093d9fbe25c446e18115f0;

    /// @notice Current message version identifier.
    uint16 public constant messageVersion = uint16(0);

    /// @notice Semantic version.
    /// @custom:semver 1.2.0
    string public constant version = "1.2.0";

    /// @notice Mapping of message hashes to boolean receipt values. Note that a message will only be present in this
    ///         mapping if it has successfully been relayed on this chain, and can therefore not be relayed again.
    mapping(bytes32 => bool) public successfulMessages;

    /// @notice Nonce for the next message to be sent, without the message version applied. Use the messageNonce getter,
    ///         which will insert the message version into the nonce to give you the actual nonce to be used for the
    ///         message.
    uint240 internal msgNonce;

    /// @notice Mapping of message hashes to boolean sent values. Note that a message will only be present in this
    ///         mapping if it has been sent from this chain to a destination chain.
    mapping(bytes32 => bool) public sentMessages;

    /// @notice Emitted whenever a message is sent to a destination
    /// @param destination  Chain ID of the destination chain.
    /// @param target       Target contract or wallet address.
    /// @param messageNonce Nonce associated with the message sent
    /// @param sender       Address initiating this message call
    /// @param entrypointHash The hash composed from the bundle's and message's entrypoint.
    /// @param message      Message payload to call target with.
    event SentMessage(
        uint256 indexed destination,
        address indexed target,
        uint256 indexed messageNonce,
        address sender,
        bytes32 entrypointHash,
        bytes message
    );

    /// @notice Emitted whenever a message is successfully relayed on this chain.
    /// @param source       Chain ID of the source chain.
    /// @param messageNonce Nonce associated with the messsage sent
    /// @param messageHash  Hash of the message that was relayed.
    /// @param returnDataHash Hash of the return data from the message that was relayed.
    event RelayedMessage(
        uint256 indexed source, uint256 indexed messageNonce, bytes32 indexed messageHash, bytes32 returnDataHash
    );

    /// @notice Retrieves the sender of the current cross domain message. If not entered, reverts.
    /// @return sender_ Address of the sender of the current cross domain message.
    function crossDomainMessageSender() external view onlyEntered returns (address sender_) {
        assembly {
            sender_ := tload(CROSS_DOMAIN_MESSAGE_SENDER_SLOT)
        }
    }

    /// @notice Retrieves the source of the current cross domain message. If not entered, reverts.
    /// @return source_ Chain ID of the source of the current cross domain message.
    function crossDomainMessageSource() external view onlyEntered returns (uint256 source_) {
        assembly {
            source_ := tload(CROSS_DOMAIN_MESSAGE_SOURCE_SLOT)
        }
    }

    /// @notice Retrieves the context of the current cross domain message. If not entered, reverts.
    /// @return sender_ Address of the sender of the current cross domain message.
    /// @return source_ Chain ID of the source of the current cross domain message.
    function crossDomainMessageContext() external view onlyEntered returns (address sender_, uint256 source_) {
        assembly {
            sender_ := tload(CROSS_DOMAIN_MESSAGE_SENDER_SLOT)
            source_ := tload(CROSS_DOMAIN_MESSAGE_SOURCE_SLOT)
        }
    }

    /// @notice Retrieves the recursive depth of the message bundle being created.
    /// @return depth_ The depth of the bundle.
    function messageBundleDepth() public view returns (uint256 depth_) {
        assembly {
            depth_ := tload(ENTRYPOINT_DEPTH_SLOT)
        }
    }

    /// @notice Retrieves the entrypoint hash of the current message bundle.
    /// @return entrypointHash_ The entrypoint hash of the current message bundle.
    function messageBundleEntrypoint() public view returns (bytes32 entrypointHash_) {
        assembly {
            let depth := tload(ENTRYPOINT_DEPTH_SLOT)
            // TODO: Should we revert if depth is 0?
            entrypointHash_ := tload(add(ENTRYPOINT_DEPTH_SLOT, depth))
        }
    }

    /// @notice Creates a bundle of messages.
    /// @param _entrypoint The entrypoint address of the bundle.
    /// @param _context The context of the bundle.
    function createBundle(address _entrypoint, bytes calldata _context) external {
        // TODO: Should we check for the caller supporting the ICrossMessageBundler interface before?
        uint256 depth = messageBundleDepth();
        bytes32 entrypointHash = messageBundleEntrypoint();

        _storeEntrypointDepth(depth + 1);
        _storeEntrypointHash(depth + 1, keccak256(abi.encodePacked(entrypointHash, _entrypoint)));

        ICrossMessageBundler(msg.sender).onCreateBundle(_context);

        _storeEntrypointDepth(depth);
    }

    /// @notice Relays a bundle of messages.
    /// @param _context The context of the bundle.
    function relayBundle(bytes calldata _context) external {
        uint256 depth = messageBundleDepth();
        bytes32 entrypointHash = messageBundleEntrypoint();

        _storeEntrypointDepth(depth + 1);
        _storeEntrypointHash(depth + 1, keccak256(abi.encodePacked(entrypointHash, msg.sender)));

        IBundleRelayer(msg.sender).onRelayBundle(_context);

        _storeEntrypointDepth(depth);
    }

    /// @notice Sends a message to some target address on a destination chain. Note that if the call always reverts,
    ///         then the message will be unrelayable and any ETH sent will be permanently locked. The same will occur
    ///         if the target on the other chain is considered unsafe (see the _isUnsafeTarget() function).
    /// @param _destination Chain ID of the destination chain.
    /// @param _target      Target contract or wallet address.
    /// @param _message     Message payload to call target with.
    /// @return messageHash_ The hash of the message being sent, used to track whether the message
    ///                      has successfully been relayed.
    function sendMessage(
        uint256 _destination,
        address _target,
        bytes calldata _message
    )
        external
        returns (bytes32 messageHash_)
    {
        return _sendMessage(_destination, _target, address(0), _message);
    }

    /// @notice Sends a message to some target address on a destination chain with an entrypoint address as an
    ///         authorized relayer.
    ///         authorized relayer. Note that if the call always reverts, then the message will be unrelayable and any
    ///         ETH sent will be permanently locked. The same will occur if the target on the other chain is considered
    ///         unsafe (see the _isUnsafeTarget() function). The entrypoint must have the capability to call
    ///         `relayMessage` for successful relaying.
    /// @param _destination Chain ID of the destination chain.
    /// @param _target      Target contract or wallet address.
    /// @param _entrypoint  Address of the entrypoint on the destination chain.
    /// @param _message     Message payload to call target with.
    /// @return messageHash_ The hash of the message being sent, used to track whether the message has successfully been
    /// relayed.
    function sendMessageWithEntrypoint(
        uint256 _destination,
        address _target,
        address _entrypoint,
        bytes calldata _message
    )
        external
        returns (bytes32 messageHash_)
    {
        return _sendMessage(_destination, _target, _entrypoint, _message);
    }

    /// @notice Re-emits a previously sent message event for old messages that haven't been
    ///         relayed yet, allowing offchain infrastructure to pick them up and relay them.
    /// @dev    Emitting a message that has already been relayed will have no effect, as it is only
    ///         relayed once on the destination chain.
    /// @param _destination Chain ID of the destination chain.
    /// @param _nonce Nonce of the message sent
    /// @param _sender Address that sent the message
    /// @param _target Target contract or wallet address.
    /// @param _message Message payload to call target with.
    /// @param _entrypointHash The hash composed from the bundle's and message's entrypoint.
    /// @return messageHash_ The hash of the message being re-sent.
    function resendMessage(
        uint256 _destination,
        uint256 _nonce,
        address _sender,
        address _target,
        bytes32 _entrypointHash,
        bytes calldata _message
    )
        external
        returns (bytes32 messageHash_)
    {
        messageHash_ = Hashing.hashL2toL2CrossDomainMessage({
            _destination: _destination,
            _source: block.chainid,
            _nonce: _nonce,
            _sender: _sender,
            _target: _target,
            _entrypointHash: _entrypointHash,
            _message: _message
        });

        if (!sentMessages[messageHash_]) revert InvalidMessage();

        emit SentMessage(_destination, _target, _nonce, _sender, _entrypointHash, _message);
    }

    /// @notice Relays a message that was sent by the other L2ToL2CrossDomainMessenger contract. Can only be executed
    ///         via cross chain call from the other messenger OR if the message was already received once and is
    ///         currently being replayed.
    /// @param _id          Identifier of the SentMessage event to be relayed
    /// @param _sentMessage Payload of the `SentMessage` event
    /// @return returnData_ Return data from the target contract call.
    function relayMessage(
        Identifier calldata _id,
        bytes calldata _sentMessage
    )
        external
        payable
        nonReentrant
        returns (bytes memory returnData_)
    {
        // Ensure the log came from the messenger.
        if (_id.origin != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) {
            revert IdOriginNotL2ToL2CrossDomainMessenger();
        }

        // Signal that this is a cross chain call that needs to have the identifier validated
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(_id, keccak256(_sentMessage));

        // Decode the payload
        (
            uint256 destination,
            address target,
            uint256 nonce,
            address sender,
            bytes32 entrypointHash,
            bytes memory message
        ) = _decodeSentMessagePayload(_sentMessage);

        // Assert invariants on the message
        if (destination != block.chainid) revert MessageDestinationNotRelayChain();

        _validateEntrypoint(entrypointHash);

        uint256 source = _id.chainId;
        bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: destination,
            _source: source,
            _nonce: nonce,
            _sender: sender,
            _target: target,
            _entrypointHash: entrypointHash,
            _message: message
        });

        if (successfulMessages[messageHash]) {
            revert MessageAlreadyRelayed();
        }

        successfulMessages[messageHash] = true;
        _storeMessageMetadata(source, sender);

        bool success;
        (success, returnData_) = target.call{ value: msg.value }(message);

        if (!success) {
            assembly {
                revert(add(32, returnData_), mload(returnData_))
            }
        }

        emit RelayedMessage(source, nonce, messageHash, keccak256(returnData_));

        _storeMessageMetadata(0, address(0));
    }

    /// @notice Retrieves the next message nonce. Message version will be added to the upper two bytes of the message
    ///         nonce. Message version allows us to treat messages as having different structures.
    /// @return Nonce of the next message to be sent, with added message version.
    function messageNonce() public view returns (uint256) {
        return Encoding.encodeVersionedNonce(msgNonce, messageVersion);
    }

    /// @notice Stores message data such as sender and source in transient storage.
    /// @param _source Chain ID of the source chain.
    /// @param _sender Address of the sender of the message.
    function _storeMessageMetadata(uint256 _source, address _sender) internal {
        assembly {
            tstore(CROSS_DOMAIN_MESSAGE_SOURCE_SLOT, _source)
            tstore(CROSS_DOMAIN_MESSAGE_SENDER_SLOT, _sender)
        }
    }

    /// @notice Decodes the payload of a SentMessage event.
    /// @dev    The payload format is as follows:
    ///         encodePacked(
    ///               encode(event selector, destination, target, nonce),
    ///               encode(sender, message)
    ///         )
    /// @param _payload         Payload of the SentMessage event.
    /// @return destination_    Destination chain ID.
    /// @return target_         Target contract of the message.
    /// @return nonce_          Nonce associated with the messsage sent.
    /// @return sender_         Address initiating this message call.
    /// @return entrypointHash_ The hash composed from the bundle's and message's entrypoint.
    /// @return message_        Message payload to call target with.
    function _decodeSentMessagePayload(bytes calldata _payload)
        internal
        pure
        returns (
            uint256 destination_,
            address target_,
            uint256 nonce_,
            address sender_,
            bytes32 entrypointHash_,
            bytes memory message_
        )
    {
        // Validate Selector (also reverts if LOG0 with no topics)
        bytes32 selector = abi.decode(_payload[:32], (bytes32));
        if (selector != SENT_MESSAGE_EVENT_SELECTOR) revert EventPayloadNotSentMessage();

        // Topics
        (destination_, target_, nonce_) = abi.decode(_payload[32:128], (uint256, address, uint256));

        // Data
        (sender_, entrypointHash_, message_) = abi.decode(_payload[128:], (address, bytes32, bytes));
    }

    /// @notice Sends a message to a target address on a destination chain.Add commentMore actions
    ///      This function checks that the destination is not the same as the current chain and that the target
    ///      is not the CrossL2Inbox or the L2ToL2CrossDomainMessenger itself. It emits a SentMessage event
    ///      and increments the message nonce.
    /// @param _destination Chain ID of the destination chain.
    /// @param _target      Target contract or wallet address.Add commentMore actions
    /// @param _message     Message payload to call target with.
    /// @param _entrypoint  Address of the entrypoint contract on the destination chain or address(0) if there is none.
    /// @return messageHash_ The hash of the message being sent, used to track whether the message has successfully been
    /// relayed.
    function _sendMessage(
        uint256 _destination,
        address _target,
        address _entrypoint,
        bytes calldata _message
    )
        internal
        returns (bytes32 messageHash_)
    {
        uint256 depth = messageBundleDepth();
        bytes32 entrypointHash = messageBundleEntrypoint();

        bytes32 messageEntrypointHash;
        if (depth > 0) {
            // We are in a bundle
            messageEntrypointHash =
                _entrypoint == address(0) ? entrypointHash : keccak256(abi.encodePacked(entrypointHash, _entrypoint));
        } else {
            // We are in a standalone message
            messageEntrypointHash = _entrypoint == address(0) ? bytes32(0) : keccak256(abi.encodePacked(_entrypoint));
        }

        if (_destination == block.chainid) revert MessageDestinationSameChain();
        if (_target == Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) revert MessageTargetL2ToL2CrossDomainMessenger();

        uint256 nonce = messageNonce();
        messageHash_ = Hashing.hashL2toL2CrossDomainMessage({
            _destination: _destination,
            _source: block.chainid,
            _nonce: nonce,
            _sender: msg.sender,
            _target: _target,
            _entrypointHash: messageEntrypointHash,
            _message: _message
        });

        sentMessages[messageHash_] = true;
        msgNonce++;

        emit SentMessage(_destination, _target, nonce, msg.sender, messageEntrypointHash, _message);
    }

    /// @notice Checks that the message entrypoint hash corresponds with the caller's hash.
    ///         Takes into account whether the message is in a bundle or not.
    /// @param _messageEntrypointHash The hash of the entrypoint of the message.
    function _validateEntrypoint(bytes32 _messageEntrypointHash) internal view {
        uint256 depth = messageBundleDepth();
        bytes32 storedRelayerHash = messageBundleEntrypoint();

        bytes32 senderHash = keccak256(abi.encodePacked(msg.sender));
        bool isValidEntrypoint;
        if (depth > 0) {
            // This message is part of a bundle
            isValidEntrypoint = _messageEntrypointHash == keccak256(abi.encodePacked(storedRelayerHash, msg.sender))
                || _messageEntrypointHash == storedRelayerHash;
        } else {
            // This is a standalone message
            isValidEntrypoint = _messageEntrypointHash == bytes32(0) || _messageEntrypointHash == senderHash;
        }

        if (!isValidEntrypoint) {
            revert MessageEntrypointNotCaller();
        }
    }

    /// @notice Stores the entrypoint depth in storage.
    /// @param _depth The depth to store.
    function _storeEntrypointDepth(uint256 _depth) internal {
        assembly {
            tstore(ENTRYPOINT_DEPTH_SLOT, _depth)
        }
    }

    /// @notice Stores the entrypoint hash for a given depth.
    /// @param _depth The depth to store the entrypoint hash for.
    /// @param _entrypointHash The entrypoint hash to store.
    function _storeEntrypointHash(uint256 _depth, bytes32 _entrypointHash) internal {
        assembly {
            tstore(add(ENTRYPOINT_DEPTH_SLOT, _depth), _entrypointHash)
        }
    }
}
