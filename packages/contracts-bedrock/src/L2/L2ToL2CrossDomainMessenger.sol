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

/// @notice Thrown when attempting to relay a message whose target is L2ToL2CrossDomainMessenger.
error MessageTargetL2ToL2CrossDomainMessenger();

/// @notice Thrown when attempting to relay a message that has already been relayed.
error MessageAlreadyRelayed();

/// @notice Thrown when a reentrant call is detected.
error ReentrantCall();

/// @notice Thrown when the provided message parameters do not match any hash of a previously sent message.
error InvalidMessage();

struct DecodedPayload {
    uint256 destination;
    address target;
    uint256 nonce;
    address sender;
    bytes message;
    bytes originContext;
}

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000023
/// @title L2ToL2CrossDomainMessenger
/// @notice The L2ToL2CrossDomainMessenger is a higher level abstraction on top of the CrossL2Inbox that provides
///         features necessary for secure transfers ERC20 tokens between L2 chains. Messages sent through the
///         L2ToL2CrossDomainMessenger on the source chain receive both replay protection as well as domain binding.
contract L2ToL2CrossDomainMessenger is ISemver, TransientReentrancyAware {
    /// @notice Current origin context encoding version identifier.
    uint8 public constant ORIGIN_CONTEXT_ENCODING_VERSION = 1;

    /// @notice Storage slot for the sender of the current cross domain message.
    ///         Equal to bytes32(uint256(keccak256("l2tol2crossdomainmessenger.sender")) - 1)
    bytes32 internal constant CROSS_DOMAIN_MESSAGE_SENDER_SLOT =
        0xb83444d07072b122e2e72a669ce32857d892345c19856f4e7142d06a167ab3f3;

    /// @notice Storage slot for the source of the current cross domain message.
    ///         Equal to bytes32(uint256(keccak256("l2tol2crossdomainmessenger.source")) - 1)
    bytes32 internal constant CROSS_DOMAIN_MESSAGE_SOURCE_SLOT =
        0x711dfa3259c842fffc17d6e1f1e0fc5927756133a2345ca56b4cb8178589fee7;

    //  TODO: revisit hashing EIP
    /// @notice First storage slot for the context of the current cross domain message.
    ///         Equal to bytes32(uint256(keccak256("l2tol2crossdomainmessenger.context.versionAndTxOrigin")) - 1)
    bytes32 internal constant ORIGIN_CONTEXT_INITIAL_SLOT =
        0x38167f9cfee4801f34ebb75cec632f57fd469c39267fe50486522db1f637c8b3;

    /// @notice Second storage slot for the context of the current cross domain message.
    ///         Equal to bytes32(uint256(keccak256("l2tol2crossdomainmessenger.context.messagePayloadHash")) - 1)
    bytes32 internal constant ORIGIN_CONTEXT_SECOND_SLOT =
    //  TODO: Calculate
     0x3a44497cbc2aebc161f6363847442155c66e50761ba6a20dff3957d614c82156;

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
    /// @param message      Message payload to call target with.
    /// @param originContext Context of the message
    event SentMessage(
        uint256 indexed destination,
        address indexed target,
        uint256 indexed messageNonce,
        address sender,
        bytes message,
        bytes originContext
    );

    /// @notice Emitted whenever a message is successfully relayed on this chain.
    /// @param source       Chain ID of the source chain.
    /// @param messageNonce Nonce associated with the messsage sent
    /// @param messageHash  Hash of the message that was relayed.
    /// @param returnDataHash Hash of the return data from the message that was relayed.
    event RelayedMessage(
        uint256 indexed source, uint256 indexed messageNonce, bytes32 indexed messageHash, bytes32 returnDataHash
    );

    /// @notice Emitted whenever a message is successfully relayed on this chain.
    /// @param msgHash Hash of the message that was relayed.
    /// @param rootMsgHash Hash of the root message that was relayed.
    /// @param relayer Address of the relayer that relayed the message.
    /// @param txOrigin Address of the transaction origin.
    /// @param cost Cost of the message relay.
    event RelayedMessageGasReceipt(
        bytes32 indexed msgHash, bytes32 indexed rootMsgHash, address relayer, address txOrigin, uint256 cost
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

    /// @notice Retrieves the origin context of the current cross domain message. If not entered, reverts.
    /// @return context_ Origin context of the current cross domain message.
    function crossDomainMessageOriginContext() external view onlyEntered returns (bytes memory context_) {
        return _crossDomainMessageOriginContext();
    }

    /// @notice Retrieves the context of the current cross domain message. If not entered, reverts.
    /// @return sender_ Address of the sender of the current cross domain message.
    /// @return source_ Chain ID of the source of the current cross domain message.
    /// @return originContext_ Origin context of the current cross domain message. Leaving as bytes instead of the fixed
    ///                        struct for flexibility.
    function crossDomainMessageContext()
        external
        view
        onlyEntered
        returns (address sender_, uint256 source_, bytes memory originContext_)
    {
        bytes memory originContextFirstSlot;
        bytes32 messagePayloadHash;
        assembly {
            sender_ := tload(CROSS_DOMAIN_MESSAGE_SENDER_SLOT)
            source_ := tload(CROSS_DOMAIN_MESSAGE_SOURCE_SLOT)
            originContextFirstSlot := tload(ORIGIN_CONTEXT_INITIAL_SLOT)
            messagePayloadHash := tload(ORIGIN_CONTEXT_SECOND_SLOT)
        }

        // TODO: See if an encode and decode can be avoided
        (uint8 encodingVersion, address txOrigin) = abi.decode(originContextFirstSlot, (uint8, address));
        originContext_ = abi.encode(encodingVersion, txOrigin, messagePayloadHash);
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
        if (_destination == block.chainid) revert MessageDestinationSameChain();
        if (_target == Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) revert MessageTargetL2ToL2CrossDomainMessenger();

        uint256 nonce = messageNonce();
        bytes32 messagePayloadHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: _destination,
            _source: block.chainid,
            _nonce: nonce,
            _sender: msg.sender,
            _target: _target,
            _message: _message
        });

        bytes memory originContext = _crossDomainMessageOriginContext();
        if (originContext.length == 0) {
            originContext = abi.encodePacked(ORIGIN_CONTEXT_ENCODING_VERSION, abi.encode(tx.origin, messagePayloadHash));
        }

        // new "top-level" cross domain call (messageHash_ == outbound message)
        // TODO: Check if packing is too different and more efficient
        messageHash_ = keccak256(abi.encode(messagePayloadHash, originContext));

        sentMessages[messageHash_] = true;
        msgNonce++;

        emit SentMessage(_destination, _target, nonce, msg.sender, _message, originContext);
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
    /// @param _originContext Origin context of the message.
    /// @return messageHash_ The hash of the message being re-sent.
    function resendMessage(
        uint256 _destination,
        uint256 _nonce,
        address _sender,
        address _target,
        bytes calldata _message,
        bytes calldata _originContext
    )
        external
        returns (bytes32 messageHash_)
    {
        bytes32 messagePayloadHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: _destination,
            _source: block.chainid,
            _nonce: _nonce,
            _sender: _sender,
            _target: _target,
            _message: _message
        });

        // TODO: Add this encoding on hashing lib as well as msg payload hashing
        messageHash_ = keccak256(abi.encode(messagePayloadHash, _originContext));

        if (!sentMessages[messageHash_]) revert InvalidMessage();

        emit SentMessage(_destination, _target, _nonce, _sender, _message, _originContext);
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
        uint256 initialGas = gasleft();

        // Ensure the log came from the messenger.
        if (_id.origin != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) {
            revert IdOriginNotL2ToL2CrossDomainMessenger();
        }

        // Signal that this is a cross chain call that needs to have the identifier validated
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(_id, keccak256(_sentMessage));

        // Decode the payload
        DecodedPayload memory decodedPayload = _decodeSentMessagePayload(_sentMessage);

        // Assert invariants on the message
        if (decodedPayload.destination != block.chainid) revert MessageDestinationNotRelayChain();

        uint256 source = _id.chainId;
        bytes32 messagePayloadHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: decodedPayload.destination,
            _source: source,
            _nonce: decodedPayload.nonce,
            _sender: decodedPayload.sender,
            _target: decodedPayload.target,
            _message: decodedPayload.message
        });

        bytes32 messageHash = keccak256(abi.encode(messagePayloadHash, decodedPayload.originContext));

        if (successfulMessages[messageHash]) {
            revert MessageAlreadyRelayed();
        }

        successfulMessages[messageHash] = true;
        _storeMessageMetadata(source, decodedPayload.sender, decodedPayload.originContext);

        bool success;
        (success, returnData_) = decodedPayload.target.call{ value: msg.value }(decodedPayload.message);

        // Clean the transient storage
        _storeMessageMetadata(0, address(0), bytes(""));

        if (success) {
            (, address txOrigin, bytes32 contextMessagePayloadHash) =
                abi.decode(decodedPayload.originContext, (uint8, address, bytes32));
            bytes32 rootMessageHash = keccak256(abi.encode(contextMessagePayloadHash, decodedPayload.originContext));
            emit RelayedMessage(source, decodedPayload.nonce, messageHash, keccak256(returnData_));

            uint256 gasUsed = (initialGas - gasleft()); // TODO: + non reentrat overhead + RELAY_MESSAGE_GAS_OVERHEAD;
            emit RelayedMessageGasReceipt(messageHash, rootMessageHash, msg.sender, txOrigin, _cost(gasUsed));
        } else {
            assembly {
                revert(add(32, returnData_), mload(returnData_))
            }
        }
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
    function _storeMessageMetadata(uint256 _source, address _sender, bytes memory _originContext) internal {
        // Decode the origin context
        (bytes32 originContextFirstSlot, bytes32 messagePayloadHash) = _parseOriginContext(_originContext);

        // Store the message metadata
        assembly {
            tstore(CROSS_DOMAIN_MESSAGE_SOURCE_SLOT, _source)
            tstore(CROSS_DOMAIN_MESSAGE_SENDER_SLOT, _sender)
            tstore(ORIGIN_CONTEXT_INITIAL_SLOT, originContextFirstSlot)
            tstore(ORIGIN_CONTEXT_SECOND_SLOT, messagePayloadHash)
        }
    }

    // TODO: Add internal function just to know how to write and read the context, so if it changes, that only changes
    // there
    function _parseOriginContext(bytes memory _originContext)
        internal
        pure
        returns (bytes32 originContextFirstSlot_, bytes32 messagePayloadHash_)
    {
        address txOrigin;
        (uint8 originContextVersion, bytes memory originContextData) = abi.decode(_originContext, (uint8, bytes));
        (messagePayloadHash_, txOrigin) = abi.decode(originContextData, (bytes32, address));

        // Pack the origin context version and tx origin
        originContextFirstSlot_ = bytes32(abi.encodePacked(originContextVersion, txOrigin));
    }

    /// @notice Retrieves the context of the current cross domain message. If not entered, reverts.
    /// @return originContext_ Origin context of the current cross domain message.
    function _crossDomainMessageOriginContext() internal view returns (bytes memory originContext_) {
        bytes32 originContextFirstSlot;
        bytes32 messagePayloadHash;
        assembly {
            originContextFirstSlot := tload(ORIGIN_CONTEXT_INITIAL_SLOT)
            messagePayloadHash := tload(ORIGIN_CONTEXT_SECOND_SLOT)
        }

        (uint8 encodingVersion, address txOrigin) = abi.decode(abi.encode(originContextFirstSlot), (uint8, address));
        originContext_ = abi.encode(encodingVersion, txOrigin, messagePayloadHash);
    }

    /// @notice Calculates the cost of a message relay.
    function _cost(uint256 _gasUsed) internal view returns (uint256) {
        return block.basefee * _gasUsed;
    }

    /// @notice Decodes the payload of a SentMessage event.
    /// @dev    The payload format is as follows:
    ///         encodePacked(
    ///               encode(event selector, destination, target, nonce),
    ///               encode(sender, message)
    ///         )
    /// @param _payload         Payload of the SentMessage event.
    /// @return decodedPayload_ Decoded message.
    function _decodeSentMessagePayload(bytes calldata _payload)
        internal
        pure
        returns (DecodedPayload memory decodedPayload_)
    {
        // Validate Selector (also reverts if LOG0 with no topics)
        bytes32 selector = abi.decode(_payload[:32], (bytes32));
        if (selector != SentMessage.selector) revert EventPayloadNotSentMessage();

        // Topics
        (uint256 destination_, address target_, uint256 nonce_) =
            abi.decode(_payload[32:128], (uint256, address, uint256));

        // Data
        (address sender_, bytes memory message_, bytes memory originContext_) =
            abi.decode(_payload[128:], (address, bytes, bytes));

        decodedPayload_ = DecodedPayload({
            destination: destination_,
            target: target_,
            nonce: nonce_,
            sender: sender_,
            message: message_,
            originContext: originContext_
        });
    }
}
