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

/// @notice Decoded data of a SentMessage event.
/// @param dstChain Chain ID of the destination chain.
/// @param dstAddress Target contract or wallet address.
/// @param nonce Nonce associated with the message sent
/// @param srcSender Address initiating this message call
/// @param dstCallData Data to call target with.
/// @param originContext Context of the original message
struct SentMessagePayload {
    uint256 dstChain;
    address dstAddress;
    uint256 nonce;
    address srcSender;
    bytes dstCallData;
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

    /// @notice First storage slot for the context of the current cross domain message.
    ///         Equal to bytes32(uint256(keccak256("l2tol2crossdomainmessenger.context.version")) - 1)
    bytes32 internal constant ORIGIN_CONTEXT_VERSION_SLOT =
        0xaf29438f3d49a80862278626ba8ccaf84aebc36dcd6f78f3e9101efa0aaef129;

    /// @notice Second storage slot for the context of the current cross domain message.
    ///         Equal to bytes32(uint256(keccak256("l2tol2crossdomainmessenger.context.messagePayloadHash")) - 1)
    bytes32 internal constant ORIGIN_CONTEXT_MESSAGE_PAYLOAD_HASH_SLOT =  // TODO: rename ORIGIN_CONTENT_HASH_SLOT
     0x1599376b7dd96feafb3dee69530b7c0f4ac6e0447ea06adb0f7c431e59c5547c;

    /// @notice Current message version identifier.
    uint16 public constant messageVersion = uint16(0);

    /// @notice Semantic version.
    /// @custom:semver 1.3.0
    string public constant version = "1.3.0";

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
    /// @param dstChain      Chain ID of the destination chain.
    /// @param dstAddress    Target contract or wallet address.
    /// @param nonce         Nonce associated with the message sent
    /// @param srcSender     Address initiating this message call
    /// @param dstCallData   Data to call target with.
    /// @param originContext   Context of the message
    event SentMessage(
        uint256 indexed dstChain,
        address indexed dstAddress,
        uint256 indexed nonce,
        address srcSender,
        bytes dstCallData,
        bytes originContext
    );

    /// @notice Emitted whenever a message is successfully relayed on this chain.
    /// @param srcChain Chain ID of the source chain.
    /// @param nonce    Nonce associated with the messsage sent
    /// @param payloadHash  Hash of the message payload that was relayed.
    /// @param returnDataHash Hash of the return data from the message that was relayed.
    event RelayedMessage(
        uint256 indexed srcChain, uint256 indexed nonce, bytes32 indexed payloadHash, bytes32 returnDataHash
    );

    /// @notice Emitted whenever a message is successfully relayed on this chain.
    /// @param msgHash Hash of the message that was relayed.
    /// @param rootMsgHash Hash of the root message that was relayed.
    /// @param relayer Address of the relayer that relayed the message.
    /// @param cost Cost of the message relay.
    event RelayedMessageGasReceipt(bytes32 indexed msgHash, bytes32 indexed rootMsgHash, address relayer, uint256 cost);

    /// @notice Retrieves the sender of the current cross domain message. If not entered, reverts.
    /// @return sender_ Address of the sender of the current cross domain message.
    function crossDomainMessageSender() external view onlyEntered returns (address sender_) {
        assembly {
            sender_ := tload(CROSS_DOMAIN_MESSAGE_SENDER_SLOT)
        }
    }

    /// @notice Retrieves the source of the current cross domain message. If not entered, reverts.
    /// @return srcChain_ Chain ID of the source of the current cross domain message.
    function crossDomainMessageSource() external view onlyEntered returns (uint256 srcChain_) {
        assembly {
            srcChain_ := tload(CROSS_DOMAIN_MESSAGE_SOURCE_SLOT)
        }
    }

    /// @notice Retrieves the origin context of the current cross domain message. If not entered, reverts.
    /// @return context_ Origin context of the current cross domain message.
    function crossDomainMessageOriginContext() external view onlyEntered returns (bytes memory context_) {
        return _crossDomainMessageOriginContext();
    }

    /// @notice Retrieves the context of the current cross domain message. If not entered, reverts.
    /// @return srcSender_ Address of the sender of the current cross domain message.
    /// @return srcChain_ Chain ID of the source of the current cross domain message.
    /// @return originContext_ Origin context of the current cross domain message. Leaving as bytes instead of the fixed
    ///                        struct for flexibility.
    function crossDomainMessageContext()
        external
        view
        onlyEntered
        returns (address srcSender_, uint256 srcChain_, bytes memory originContext_)
    {
        uint8 encodingVersion;
        bytes32 payloadHash;
        assembly {
            srcSender_ := tload(CROSS_DOMAIN_MESSAGE_SENDER_SLOT)
            srcChain_ := tload(CROSS_DOMAIN_MESSAGE_SOURCE_SLOT)
            encodingVersion := tload(ORIGIN_CONTEXT_VERSION_SLOT)
            payloadHash := tload(ORIGIN_CONTEXT_MESSAGE_PAYLOAD_HASH_SLOT)
        }

        originContext_ = abi.encode(encodingVersion, payloadHash);
    }

    /// @notice Sends a message to some target address on a destination chain. Note that if the call always reverts,
    ///         then the message will be unrelayable and any ETH sent will be permanently locked. The same will occur
    ///         if the target on the other chain is considered unsafe (see the _isUnsafeTarget() function).
    /// @param _dstChain    Chain ID of the destination chain.
    /// @param _dstAddress      Target contract or wallet address.
    /// @param _dstCallData     Message payload to call target with.
    /// @return payloadHash_ The hash of the message payload being sent, used to track whether the message
    ///                      has successfully been relayed.
    function sendMessage( // Note: this is basically a solidity "call()" with chain id added
        uint256 _dstChain,
        address _dstAddress,
        bytes calldata _dstCallData
    )
        external
        returns (bytes32 payloadHash_)
    {
        if (_dstChain == block.chainid) revert MessageDestinationSameChain();

        uint256 nonce = messageNonce();

        // TODO: rename hashL2toL2CrossDomainMessagePayload to hashL2toL2CrossDomainMessageContent
        bytes32 contentHash_ = Hashing.hashL2toL2CrossDomainMessagePayload({ // TODO: rename the args
            _destination: _dstChain, // TODO: put these args in the same order as the log
            _source: block.chainid,
            _nonce: nonce,
            _sender: msg.sender,
            _target: _dstAddress,
            _message: _dstCallData
        });

        // TODO refactor encodingVersion into _crossDomainMessageOriginContext with parse (or 3rd) function
        bytes memory originContext = _crossDomainMessageOriginContext();
        (uint8 encodingVersion,) = _parseOriginContext(originContext);

        // When 0 (empty originContext) means this is the first message sent
        if (encodingVersion == 0) {
            originContext = abi.encode(ORIGIN_CONTEXT_ENCODING_VERSION, contentHash_);
        }

        payloadHash_ = keccak256(abi.encodePacked(contentHash_, originContext));

        sentMessages[payloadHash_] = true;
        msgNonce++;

        emit SentMessage(_dstChain, _dstAddress, nonce, msg.sender, _dstCallData, originContext);
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
    /// @return payloadHash_ The hash of the message being re-sent.
    function resendMessage(
        uint256 _destination,
        uint256 _nonce,
        address _sender,
        address _target,
        bytes calldata _message,
        bytes calldata _originContext
    )
        external
        returns (bytes32 payloadHash_)
    {
        bytes32 contentHash_ = Hashing.hashL2toL2CrossDomainMessagePayload({
            _destination: _destination,
            _source: block.chainid,
            _nonce: _nonce,
            _sender: _sender,
            _target: _target,
            _message: _message
        });

        payloadHash_ = keccak256(abi.encodePacked(contentHash_, _originContext));

        if (!sentMessages[payloadHash_]) revert InvalidMessage();

        emit SentMessage(_destination, _target, _nonce, _sender, _message, _originContext);
    }

    /// @notice Relays a message that was sent by the other L2ToL2CrossDomainMessenger contract. Can only be executed
    ///         via cross chain call from the other messenger OR if the message was already received once and is
    ///         currently being replayed.
    /// @param _id          Identifier of the SentMessage event to be relayed
    /// @param _sentMessagePayload Payload of the `SentMessage` event
    /// @return returnData_ Return data from the target contract call.
    function relayMessage(
        Identifier calldata _id,
        bytes calldata _sentMessagePayload
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
        ICrossL2Inbox(Predeploys.CROSS_L2_INBOX).validateMessage(_id, keccak256(_sentMessagePayload));

        // Decode the payload
        SentMessagePayload memory decodedPayload = _decodeSentMessagePayload(_sentMessagePayload);

        // Assert invariants on the message
        if (decodedPayload.dstChain != block.chainid) revert MessageDestinationNotRelayChain();

        uint256 srcChain = _id.chainId;
        bytes32 contentHash_ = Hashing.hashL2toL2CrossDomainMessagePayload({
            _destination: decodedPayload.dstChain,
            _source: srcChain,
            _nonce: decodedPayload.nonce,
            _sender: decodedPayload.srcSender,
            _target: decodedPayload.dstAddress,
            _message: decodedPayload.dstCallData
        });

        bytes32 payloadHash_ = keccak256(abi.encodePacked(contentHash_, decodedPayload.originContext));

        if (successfulMessages[payloadHash_]) {
            revert MessageAlreadyRelayed();
        }

        successfulMessages[payloadHash_] = true;
        _storeMessageMetadata(srcChain, decodedPayload.srcSender, decodedPayload.originContext);

        bool success;
        (success, returnData_) = decodedPayload.dstAddress.call{ value: msg.value }(decodedPayload.dstCallData);

        if (!success) {
            assembly {
                revert(add(32, returnData_), mload(returnData_))
            }
        }

        emit RelayedMessage(srcChain, decodedPayload.nonce, payloadHash_, keccak256(returnData_));

        _storeMessageMetadata(0, address(0), "");
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
    /// @param _originContext Origin context of the message.
    function _storeMessageMetadata(uint256 _source, address _sender, bytes memory _originContext) internal {
        uint8 encodingVersion;
        bytes32 originContentHash;
        if (_originContext.length != 0) {
            // Decode the origin context
            (encodingVersion, originContentHash) = _parseOriginContext(_originContext);
        }

        // Store the message metadata
        assembly {
            tstore(CROSS_DOMAIN_MESSAGE_SOURCE_SLOT, _source)
            tstore(CROSS_DOMAIN_MESSAGE_SENDER_SLOT, _sender)
            tstore(ORIGIN_CONTEXT_VERSION_SLOT, encodingVersion)
            tstore(ORIGIN_CONTEXT_MESSAGE_PAYLOAD_HASH_SLOT, originContentHash)
        }
    }

    // Use this internal function just to know how to write and read the context, so if it changes, it's only here
    function _parseOriginContext(bytes memory _originContext)
        internal
        pure
        returns (uint8 encodingVersion_, bytes32 originContentHash_)
    {
        (encodingVersion_, originContentHash_) = abi.decode(_originContext, (uint8, bytes32));
    }

    /// @notice Retrieves the context of the current cross domain message. If not entered, reverts.
    /// @return originContext_ Origin context of the current cross domain message.
    function _crossDomainMessageOriginContext() internal view returns (bytes memory originContext_) {
        uint8 encodingVersion;
        bytes32 originContentHash;
        assembly {
            encodingVersion := tload(ORIGIN_CONTEXT_VERSION_SLOT)
            originContentHash := tload(ORIGIN_CONTEXT_MESSAGE_PAYLOAD_HASH_SLOT)
        }

        originContext_ = abi.encode(encodingVersion, originContentHash);
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
        returns (SentMessagePayload memory decodedPayload_)
    {
        // Validate Selector (also reverts if LOG0 with no topics)
        bytes32 selector = abi.decode(_payload[:32], (bytes32));
        if (selector != SentMessage.selector) revert EventPayloadNotSentMessage();

        // Topics
        (uint256 dstChain_, address dstAddress_, uint256 nonce_) =
            abi.decode(_payload[32:128], (uint256, address, uint256));

        // Data
        (address srcSender_, bytes memory dstCallData_, bytes memory originContext_) =
            abi.decode(_payload[128:], (address, bytes, bytes));

        decodedPayload_ = SentMessagePayload({
            dstChain: dstChain_,
            dstAddress: dstAddress_,
            nonce: nonce_,
            srcSender: srcSender_,
            dstCallData: dstCallData_,
            originContext: originContext_
        });
    }
}
