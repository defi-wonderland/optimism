// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Hashing } from "src/libraries/Hashing.sol";

// Target contract
import {
    L2ToL2CrossDomainMessenger,
    NotEntered,
    MessageDestinationSameChain,
    IdOriginNotL2ToL2CrossDomainMessenger,
    EventPayloadNotSentMessage,
    MessageDestinationNotRelayChain,
    MessageTargetL2ToL2CrossDomainMessenger,
    MessageAlreadyRelayed,
    ReentrantCall,
    InvalidMessage
} from "src/L2/L2ToL2CrossDomainMessenger.sol";

// Interfaces
import { ICrossL2Inbox, Identifier } from "interfaces/L2/ICrossL2Inbox.sol";

import { GasTank } from "src/L2/GasTank.sol";

/// @title L2ToL2CrossDomainMessengerWithModifiableTransientStorage
/// @dev L2ToL2CrossDomainMessenger contract with methods to modify the transient storage.
///      This is used to test the transient storage of L2ToL2CrossDomainMessenger.
contract L2ToL2CrossDomainMessengerWithModifiableTransientStorage is L2ToL2CrossDomainMessenger {
    /// @dev Returns the value of the entered slot in transient storage.
    /// @return Value of the entered slot.
    function entered() external view returns (bool) {
        return _entered();
    }

    /// @dev Sets the entered slot value in transient storage.
    /// @param _value Value to set.
    function setEntered(uint256 _value) external {
        assembly {
            tstore(ENTERED_SLOT, _value)
        }
    }

    /// @dev Sets the cross domain messenger sender in transient storage.
    /// @param _sender Sender address to set.
    function setCrossDomainMessageSender(address _sender) external {
        assembly {
            tstore(CROSS_DOMAIN_MESSAGE_SENDER_SLOT, _sender)
        }
    }

    /// @dev Sets the cross domain messenger source in transient storage.
    /// @param _source Source chain ID to set.
    function setCrossDomainMessageSource(uint256 _source) external {
        assembly {
            tstore(CROSS_DOMAIN_MESSAGE_SOURCE_SLOT, _source)
        }
    }

    /// @dev Sets the cross domain messenger context in transient storage.
    /// @param _originContext Context to set.

    function setCrossDomainMessageOriginContext(bytes memory _originContext) external {
        (uint8 encodingVersion, bytes32 messagePayloadHash, address txOrigin) = _parseOriginContext(_originContext);

        assembly {
            tstore(ORIGIN_CONTEXT_VERSION, encodingVersion)
            tstore(ORIGIN_CONTEXT_MESSAGE_PAYLOAD_HASH, messagePayloadHash)
            tstore(ORIGIN_CONTEXT_TX_ORIGIN, txOrigin)
        }
    }
}

/// @title L2ToL2CrossDomainMessengerTest
/// @dev Contract for testing the L2ToL2CrossDomainMessenger contract.
contract L2ToL2CrossDomainMessengerTest is Test {
    address internal foundryVMAddress = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    /// @dev L2ToL2CrossDomainMessenger contract instance with modifiable transient storage.
    L2ToL2CrossDomainMessengerWithModifiableTransientStorage l2ToL2CrossDomainMessenger;

    // PoC related
    uint256 public immutable origin = block.chainid;
    uint256 public immutable destination = block.chainid + 1;
    address public immutable originUser = makeAddr("originUser");
    address public immutable randomCaller = makeAddr("randomCaller");
    address public immutable relayer = makeAddr("relayer");
    uint256 public immutable A = 1;
    uint256 public immutable B = 2;
    uint256 public immutable C = 3;
    uint256 public immutable ID_TIMESTAMP = block.timestamp;
    uint256 public immutable ID_BLOCK_NUMBER = block.number;
    uint256 public baseFeeOnB = 10_000_000;
    uint256 public baseFeeOnC = 1_000_000;
    uint256 public nonceA;
    uint256 public logIndex;
    // PoC contracts
    GasTank public gasTank;
    ChainByPass public chainByPass;
    ReceiverOnC public receiverOnC;

    /// @dev Sets up the test suite.
    function setUp() public {
        // Deploy the L2ToL2CrossDomainMessenger contract
        vm.etch(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            address(new L2ToL2CrossDomainMessengerWithModifiableTransientStorage()).code
        );
        l2ToL2CrossDomainMessenger =
            L2ToL2CrossDomainMessengerWithModifiableTransientStorage(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        nonceA = l2ToL2CrossDomainMessenger.messageNonce();

        /* deploy contracts for PoC */
        gasTank = new GasTank();
        chainByPass = new ChainByPass();
        receiverOnC = new ReceiverOnC();
    }

    /// @dev Tests that `sendMessage` succeeds and emits the correct event.
    function testFuzz_sendMessage_succeeds(uint256 _destination, address _target, bytes calldata _message) external {
        // Ensure the destination is not the same as the source, otherwise the function will revert
        vm.assume(_destination != block.chainid);

        // Ensure that the target contract is not CrossL2Inbox or L2ToL2CrossDomainMessenger
        vm.assume(_target != Predeploys.CROSS_L2_INBOX && _target != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        // Get the current message nonce
        uint256 messageNonce = l2ToL2CrossDomainMessenger.messageNonce();

        // Look for correct emitted event
        vm.recordLogs();

        // Call the sendMessage function
        vm.prank(randomCaller, originUser);
        bytes32 msgHash = l2ToL2CrossDomainMessenger.sendMessage(_destination, _target, _message);
        bytes32 messagePayloadHash = Hashing.hashL2toL2CrossDomainMessage(
            _destination, block.chainid, messageNonce, randomCaller, _target, _message
        );
        bytes memory originContext =
            abi.encode(l2ToL2CrossDomainMessenger.ORIGIN_CONTEXT_ENCODING_VERSION(), messagePayloadHash, originUser);
        assertEq(msgHash, keccak256(abi.encodePacked(messagePayloadHash, originContext)));

        // Check that the event was emitted with the correct parameters
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);

        // topics
        assertEq(logs[0].topics[0], L2ToL2CrossDomainMessenger.SentMessage.selector);
        assertEq(logs[0].topics[1], bytes32(_destination));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(_target))));
        assertEq(logs[0].topics[3], bytes32(messageNonce));

        // data
        assertEq(logs[0].data, abi.encode(randomCaller, _message, originContext));

        // Check that the message nonce has been incremented and the message hash has been stored
        assertEq(l2ToL2CrossDomainMessenger.messageNonce(), messageNonce + 1);
        assertEq(l2ToL2CrossDomainMessenger.sentMessages(msgHash), true);
    }

    /// @dev Tests that the `sendMessage` function reverts when sending a ETH
    function testFuzz_sendMessage_nonPayable_reverts(
        uint256 _destination,
        address _target,
        bytes calldata _message,
        uint256 _value
    )
        external
    {
        // Ensure the destination is not the same as the source, otherwise the function will revert
        vm.assume(_destination != block.chainid);

        // Ensure that the target contract is not CrossL2Inbox or L2ToL2CrossDomainMessenger
        vm.assume(_target != Predeploys.CROSS_L2_INBOX && _target != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        // Ensure that _value is greater than 0
        _value = bound(_value, 1, type(uint256).max);

        // Add sufficient value to the contract to send the message with
        vm.deal(address(this), _value);

        // Call the sendMessage function with value to provoke revert
        (bool success,) = address(l2ToL2CrossDomainMessenger).call{ value: _value }(
            abi.encodeCall(l2ToL2CrossDomainMessenger.sendMessage, (_destination, _target, _message))
        );

        // Check that the function reverts
        assertFalse(success);
    }

    /// @dev Tests that the `sendMessage` function reverts when destination is the same as the source chain.
    function testFuzz_sendMessage_destinationSameChain_reverts(address _target, bytes calldata _message) external {
        // Expect a revert with the MessageDestinationSameChain selector
        vm.expectRevert(MessageDestinationSameChain.selector);

        // Call `sendMessage` with the current chain as the destination to prevent revert due to invalid destination
        l2ToL2CrossDomainMessenger.sendMessage({ _destination: block.chainid, _target: _target, _message: _message });
    }

    /// @dev Tests that the `sendMessage` function reverts when the target is L2ToL2CrossDomainMessenger.
    function testFuzz_sendMessage_targetL2ToL2CrossDomainMessenger_reverts(
        uint256 _destination,
        bytes calldata _message
    )
        external
    {
        // Ensure the destination is not the same as the source, otherwise the function will revert regardless of
        // target
        vm.assume(_destination != block.chainid);

        // Expect a revert with the MessageTargetL2ToL2CrossDomainMessenger selector
        vm.expectRevert(MessageTargetL2ToL2CrossDomainMessenger.selector);

        // Call `senderMessage` with the L2ToL2CrossDomainMessenger as the target to provoke revert
        l2ToL2CrossDomainMessenger.sendMessage({
            _destination: _destination,
            _target: Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            _message: _message
        });
    }

    /// @dev Tests that the `resendMessage` function reverts when the message hash does not correspond to
    ///      any previously sent message.
    function testFuzz_resendMessage_invalidMessage_reverts(
        uint256 _destination,
        uint256 _nonce,
        address _sender,
        address _target,
        bytes calldata _message,
        bytes calldata _originContext
    )
        external
    {
        // Get the message hash and ensure it has not been sent yet
        bytes32 msgHash =
            Hashing.hashL2toL2CrossDomainMessage(_destination, block.chainid, _nonce, _sender, _target, _message);
        vm.assume(l2ToL2CrossDomainMessenger.sentMessages(msgHash) == false);

        // Expect a revert with the InvalidMessage selector
        vm.expectRevert(InvalidMessage.selector);

        // Call the resendMessage function
        l2ToL2CrossDomainMessenger.resendMessage(_destination, _nonce, _sender, _target, _message, _originContext);
    }

    /// @dev Tests that `resendMessage` succeeds and emits the same SentMessage event as the one
    ///      emitted by `sendMessage`.
    function testFuzz_resendMessage_succeeds(
        address _sender,
        uint256 _destination,
        address _target,
        bytes calldata _message
    )
        external
    {
        // Ensure the destination is not the same as the source, otherwise the function will revert
        vm.assume(_destination != block.chainid);

        // Ensure that the target contract is not CrossL2Inbox or L2ToL2CrossDomainMessenger
        vm.assume(_target != Predeploys.CROSS_L2_INBOX && _target != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        // Get the current message nonce
        uint256 messageNonce = l2ToL2CrossDomainMessenger.messageNonce();

        // Look for correct emitted event
        vm.recordLogs();

        // Call the `sendMessage` function
        vm.prank(_sender, originUser);
        bytes32 msgHash = l2ToL2CrossDomainMessenger.sendMessage(_destination, _target, _message);
        bytes32 messagePayloadHash =
            Hashing.hashL2toL2CrossDomainMessage(_destination, block.chainid, messageNonce, _sender, _target, _message);

        bytes memory originContext =
            abi.encode(l2ToL2CrossDomainMessenger.ORIGIN_CONTEXT_ENCODING_VERSION(), messagePayloadHash, originUser);

        assertEq(msgHash, keccak256(abi.encodePacked(messagePayloadHash, originContext)));

        // Check that the event was emitted with the correct parameters
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);

        // topics
        assertEq(logs[0].topics[0], L2ToL2CrossDomainMessenger.SentMessage.selector);
        assertEq(logs[0].topics[1], bytes32(_destination));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(_target))));
        assertEq(logs[0].topics[3], bytes32(messageNonce));

        // data
        assertEq(logs[0].data, abi.encode(_sender, _message, originContext));

        // Check that the message nonce has been incremented and the message hash has been stored
        assertEq(l2ToL2CrossDomainMessenger.messageNonce(), messageNonce + 1);
        assertEq(l2ToL2CrossDomainMessenger.sentMessages(msgHash), true);

        // Call the `resendMessage` function
        bytes32 resendMsgHash = l2ToL2CrossDomainMessenger.resendMessage(
            _destination, messageNonce, _sender, _target, _message, originContext
        );

        // Check that the event was emitted with the correct parameters
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);

        // topics
        assertEq(logs[0].topics[0], L2ToL2CrossDomainMessenger.SentMessage.selector);
        assertEq(logs[0].topics[1], bytes32(_destination));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(_target))));
        assertEq(logs[0].topics[3], bytes32(messageNonce));

        // Check that the message hash returned by `sendMessage` is the same as the one returned by `resendMessage`
        assertEq(resendMsgHash, msgHash);
    }

    function testFuzz_relayMessage_eventPayloadNotSentMessage_reverts(
        uint256 _source,
        uint256 _nonce,
        bytes32 _msgHash,
        uint256 _value,
        uint64 _blockNum,
        uint32 _logIndex,
        uint64 _time
    )
        external
    {
        // Expect a revert with the EventPayloadNotSentMessage selector
        vm.expectRevert(EventPayloadNotSentMessage.selector);

        // Point to a different remote log that the inbox validates
        Identifier memory id =
            Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _blockNum, _logIndex, _time, _source);
        bytes memory sentMessage =
            abi.encode(L2ToL2CrossDomainMessenger.RelayedMessage.selector, _source, _nonce, _msgHash);

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: ""
        });

        // Call
        hoax(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _value);
        l2ToL2CrossDomainMessenger.relayMessage{ value: _value }(id, sentMessage);
    }

    /// @dev Mock target function that checks the source and sender of the message in transient storage.
    /// @param _source Source chain ID of the message.
    /// @param _sender Sender of the message.
    function mockTarget(uint256 _source, address _sender) external payable {
        // Ensure that the contract is entered
        assertEq(l2ToL2CrossDomainMessenger.entered(), true);

        // Ensure that the sender is correct
        assertEq(l2ToL2CrossDomainMessenger.crossDomainMessageSource(), _source);

        // Ensure that the source is correct
        assertEq(l2ToL2CrossDomainMessenger.crossDomainMessageSender(), _sender);
    }

    /// @dev Tests that the `relayMessage` function succeeds and stores the correct metadata in transient storage.
    function testFuzz_relayMessage_metadataStore_succeeds(
        uint256 _source,
        uint256 _nonce,
        address _sender,
        uint256 _value,
        uint64 _blockNum,
        uint32 _logIndex,
        uint64 _time
    )
        external
    {
        // Since the target is this contract, we want to ensure the payment doesn't lead to overflow, since this
        // contract has a non-zero balance. Thus, we set this contract's balance to zero and we hoax afterwards.
        vm.deal(address(this), 0);

        // Set the target and message for the reentrant call
        address target = address(this);
        bytes memory message = abi.encodeCall(this.mockTarget, (_source, _sender));

        bytes32 messagePayloadHash = keccak256(abi.encode(block.chainid, _source, _nonce, _sender, target, message));

        bytes memory originContext =
            abi.encode(l2ToL2CrossDomainMessenger.ORIGIN_CONTEXT_ENCODING_VERSION(), messagePayloadHash, originUser);

        bytes32 msgHash = keccak256(abi.encodePacked(messagePayloadHash, originContext));

        // Look for correct emitted event
        vm.expectEmit(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        emit L2ToL2CrossDomainMessenger.RelayedMessage(_source, _nonce, msgHash, keccak256(""));

        // Ensure the target contract is called with the correct parameters
        vm.expectCall({ callee: target, msgValue: _value, data: message });

        // Construct and relay the message
        Identifier memory id =
            Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _blockNum, _logIndex, _time, _source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, target, _nonce), // topics
            abi.encode(_sender, message, originContext) // data
        );

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: ""
        });

        hoax(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _value);
        l2ToL2CrossDomainMessenger.relayMessage{ value: _value }(id, sentMessage);

        // Check that successfulMessages mapping updates the message hash correctly
        assertEq(l2ToL2CrossDomainMessenger.successfulMessages(msgHash), true);

        // Check that entered slot is cleared after the function call
        assertEq(l2ToL2CrossDomainMessenger.entered(), false);

        // Check that metadata is cleared after the function call. We need to set the `entered` slot to non-zero
        // value
        // to prevent NotEntered revert when calling the crossDomainMessageSender and crossDomainMessageSource
        // functions
        l2ToL2CrossDomainMessenger.setEntered(1);
        assertEq(l2ToL2CrossDomainMessenger.crossDomainMessageSource(), 0);
        assertEq(l2ToL2CrossDomainMessenger.crossDomainMessageSender(), address(0));
    }

    /// @dev Tests the `relayMessage` function returns the expected return data from the call to the target contract.
    function testFuzz_relayMessage_returnData_succeeds(
        uint256 _source,
        uint256 _nonce,
        address _sender,
        uint256 _value,
        uint64 _blockNum,
        uint32 _logIndex,
        uint64 _time,
        address _target,
        bytes memory _mockedReturnData
    )
        public
    {
        // Ensure the target is not CrossL2Inbox or L2ToL2CrossDomainMessenger or the foundry VM
        vm.assume(
            _target != Predeploys.CROSS_L2_INBOX && _target != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER
                && _target != foundryVMAddress
        );

        // ensure the target has 0 balance to avoid an overflow
        vm.deal(_target, 0);

        // Declare a random call to be made over the target
        bytes memory message = abi.encodePacked("randomCall()");

        bytes memory originContext = abi.encode(uint8(0), keccak256(""), address(0));

        // Construct the message
        Identifier memory id =
            Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _blockNum, _logIndex, _time, _source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, _target, _nonce), // topics
            abi.encode(_sender, message, originContext) // data
        );

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(message))),
            returnData: ""
        });

        // Mock the random call over the target with the expected return data
        vm.mockCall({ callee: _target, data: message, returnData: _mockedReturnData });

        hoax(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _value);
        bytes memory returnData = l2ToL2CrossDomainMessenger.relayMessage{ value: _value }(id, sentMessage);

        // Check that the return data is the mocked one
        assertEq(returnData, _mockedReturnData);
    }

    /// @dev Mock reentrant function that calls the `relayMessage` function.
    /// @param _source Source chain ID of the message.
    /// @param _nonce Nonce of the message.
    /// @param _sender Sender of the message.
    function mockTargetReentrant(uint256 _source, uint256 _nonce, address _sender) external payable {
        // Ensure caller is CrossL2Inbox to prevent a revert from the caller check
        vm.prank(Predeploys.CROSS_L2_INBOX);

        // Ensure that the contract is entered
        assertEq(l2ToL2CrossDomainMessenger.entered(), true);

        vm.expectRevert(ReentrantCall.selector);

        Identifier memory id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, 1, 1, 1, _source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, address(0), _nonce), // topics
            abi.encode(_sender, "", "") // data
        );

        l2ToL2CrossDomainMessenger.relayMessage(id, sentMessage);

        // Ensure the function still reverts if `expectRevert` succeeds
        revert();
    }

    /// @dev Tests that the `relayMessage` function reverts when reentrancy is attempted.
    function testFuzz_relayMessage_reentrant_reverts(
        uint256 _source1, // source passed to `relayMessage` by the initial call.
        address _sender1, // sender passed to `relayMessage` by the initial call.
        uint256 _source2, // sender passed to `relayMessage` by the reentrant call.
        address _sender2, // sender passed to `relayMessage` by the reentrant call.
        uint256 _nonce,
        uint256 _value,
        uint64 _blockNum,
        uint32 _logIndex,
        uint64 _time
    )
        external
    {
        // Since the target is this contract, we want to ensure the payment doesn't lead to overflow, since this
        // contract has a non-zero balance. Thus, we set this contract's balance to zero and we hoax afterwards.
        vm.deal(address(this), 0);

        // Set the target and message for the reentrant call
        address target = address(this);
        bytes memory message = abi.encodeCall(this.mockTargetReentrant, (_source2, _nonce, _sender2));

        // Ensure the target contract is called with the correct parameters
        vm.expectCall({ callee: target, msgValue: _value, data: message });

        // Construct and relay the message
        Identifier memory id =
            Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _blockNum, _logIndex, _time, _source1);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, target, _nonce), // topics
            abi.encode(_sender1, message, "") // data
        );

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: ""
        });

        // Expect the target call to revert
        vm.expectRevert(1);
        hoax(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _value);
        l2ToL2CrossDomainMessenger.relayMessage{ value: _value }(id, sentMessage);

        // Check that entered slot is cleared after the function call
        assertEq(l2ToL2CrossDomainMessenger.entered(), false);

        // Check that metadata is cleared after the function call. We need to set the `entered` slot to non-zero
        // value
        // to prevent NotEntered revert when calling the crossDomainMessageSender and crossDomainMessageSource
        // functions
        l2ToL2CrossDomainMessenger.setEntered(1);
        assertEq(l2ToL2CrossDomainMessenger.crossDomainMessageSource(), 0);
        assertEq(l2ToL2CrossDomainMessenger.crossDomainMessageSender(), address(0));
    }

    /// @dev Tests that the `relayMessage` function reverts when log identifier is not the cdm
    function testFuzz_relayMessage_idOriginNotL2ToL2CrossDomainMessenger_reverts(
        uint256 _source,
        uint256 _nonce,
        address _sender,
        address _target,
        bytes calldata _message,
        uint256 _value,
        address _origin,
        uint64 _blockNum,
        uint32 _logIndex,
        uint64 _time
    )
        external
    {
        // Incorrect identifier origin
        vm.assume(_origin != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        // Expect a revert with the IdOriginNotL2ToL2CrossDomainMessenger
        vm.expectRevert(IdOriginNotL2ToL2CrossDomainMessenger.selector);

        Identifier memory id = Identifier(_origin, _blockNum, _logIndex, _time, _source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, _target, _nonce), // topics
            abi.encode(_sender, _message, "") // data
        );

        // Call
        hoax(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _value);
        l2ToL2CrossDomainMessenger.relayMessage{ value: _value }(id, sentMessage);
    }

    /// @dev Tests that the `relayMessage` function reverts when the destination is not the relay chain.
    function testFuzz_relayMessage_destinationNotRelayChain_reverts(
        uint256 _destination,
        uint256 _source,
        uint256 _nonce,
        address _sender,
        address _target,
        bytes calldata _message,
        uint256 _value,
        uint64 _blockNum,
        uint32 _logIndex,
        uint64 _time
    )
        external
    {
        // Ensure the destination is not this chain
        vm.assume(_destination != block.chainid);

        // Expect a revert with the MessageDestinationNotRelayChain selector
        vm.expectRevert(MessageDestinationNotRelayChain.selector);

        Identifier memory id =
            Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _blockNum, _logIndex, _time, _source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _destination, _target, _nonce), // topics
            abi.encode(_sender, _message, "") // data
        );

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: ""
        });

        // Call `relayMessage`
        hoax(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _value);
        l2ToL2CrossDomainMessenger.relayMessage{ value: _value }(id, sentMessage);
    }

    /// @dev Tests that the `relayMessage` function reverts when the message has already been relayed.
    function testFuzz_relayMessage_alreadyRelayed_reverts(
        uint256 _source,
        uint256 _nonce,
        address _sender,
        address _target,
        bytes calldata _message,
        uint256 _value,
        uint64 _blockNum,
        uint32 _logIndex,
        uint64 _time
    )
        external
    {
        // Ensure that payment doesn't overflow since we send value to L2ToL2CrossDomainMessenger twice
        _value = bound(_value, 0, type(uint256).max / 2);

        // Ensure that the target call is payable if value is sent
        if (_value > 0) assumePayable(_target);

        // Ensure that the target contract is not CrossL2Inbox or L2ToL2CrossDomainMessenger or the foundry VM
        vm.assume(
            _target != Predeploys.CROSS_L2_INBOX && _target != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER
                && _target != foundryVMAddress
        );

        // Ensure that the target contract does not revert (using the message also as the return data)
        vm.mockCall({ callee: _target, msgValue: _value, data: _message, returnData: _message });

        bytes memory originContext = abi.encode(uint8(0), keccak256(""), address(0));

        // Look for correct emitted event for first call.
        vm.expectEmit(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        emit L2ToL2CrossDomainMessenger.RelayedMessage(
            _source,
            _nonce,
            // message payload hash + context
            keccak256(
                abi.encodePacked(
                    keccak256(abi.encode(block.chainid, _source, _nonce, _sender, _target, _message)), originContext
                )
            ),
            keccak256(_message)
        );

        Identifier memory id =
            Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _blockNum, _logIndex, _time, _source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, _target, _nonce), // topics
            abi.encode(_sender, _message, originContext) // data
        );

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: ""
        });

        // First call to `relayMessage` should succeed. The current chain is the destination to prevent revert due to
        // invalid destination
        hoax(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _value);
        l2ToL2CrossDomainMessenger.relayMessage{ value: _value }(id, sentMessage);

        // Second call should fail with MessageAlreadyRelayed selector
        vm.expectRevert(MessageAlreadyRelayed.selector);

        // Call `relayMessage` again. The current chain is the destination to prevent revert due to invalid
        // destination
        hoax(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _value);
        l2ToL2CrossDomainMessenger.relayMessage{ value: _value }(id, sentMessage);
    }

    /// @dev Tests that the `relayMessage` function reverts when the target call fails.
    function testFuzz_relayMessage_targetCallFails_reverts(
        uint256 _source,
        uint256 _nonce,
        address _sender,
        address _target,
        bytes calldata _message,
        uint256 _value,
        bytes calldata _revertData
    )
        external
    {
        // Ensure that the target contract is not CrossL2Inbox or L2ToL2CrossDomainMessenger
        vm.assume(_target != Predeploys.CROSS_L2_INBOX && _target != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        // Ensure that the target call is payable if value is sent
        if (_value > 0) assumePayable(_target);

        // Ensure that the target contract reverts
        vm.mockCallRevert({ callee: _target, msgValue: _value, data: _message, revertData: _revertData });

        // Construct the identifier -- using some hardcoded values for the block number, log index, and time to avoid
        // stack too deep errors.
        Identifier memory id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, 1, 1, 1, _source);

        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, _target, _nonce), // topics
            abi.encode(_sender, _message, "") // data
        );

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: ""
        });

        // Expect the target call to revert with the proper return data.
        vm.expectRevert(_revertData);
        hoax(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _value);
        l2ToL2CrossDomainMessenger.relayMessage{ value: _value }(id, sentMessage);
    }

    /// @dev Tests that the `crossDomainMessageSender` function returns the correct value.
    function testFuzz_crossDomainMessageSender_succeeds(address _sender) external {
        // Set `entered` to non-zero value to prevent NotEntered revert
        l2ToL2CrossDomainMessenger.setEntered(1);
        // Ensure that the contract is now entered
        assertEq(l2ToL2CrossDomainMessenger.entered(), true);
        // Set cross domain message sender in the transient storage
        l2ToL2CrossDomainMessenger.setCrossDomainMessageSender(_sender);
        // Check that the `crossDomainMessageSender` function returns the correct value
        assertEq(l2ToL2CrossDomainMessenger.crossDomainMessageSender(), _sender);
    }

    /// @dev Tests that the `crossDomainMessageSender` function reverts when not entered.
    function test_crossDomainMessageSender_notEntered_reverts() external {
        // Ensure that the contract is not entered
        assertEq(l2ToL2CrossDomainMessenger.entered(), false);

        // Expect a revert with the NotEntered selector
        vm.expectRevert(NotEntered.selector);

        // Call `crossDomainMessageSender` to provoke revert
        l2ToL2CrossDomainMessenger.crossDomainMessageSender();
    }

    /// @dev Tests that the `crossDomainMessageSource` function returns the correct value.
    function testFuzz_crossDomainMessageSource_succeeds(uint256 _source) external {
        // Set `entered` to non-zero value to prevent NotEntered revert
        l2ToL2CrossDomainMessenger.setEntered(1);
        // Ensure that the contract is now entered
        assertEq(l2ToL2CrossDomainMessenger.entered(), true);
        // Set cross domain message source in the transient storage
        l2ToL2CrossDomainMessenger.setCrossDomainMessageSource(_source);
        // Check that the `crossDomainMessageSource` function returns the correct value
        assertEq(l2ToL2CrossDomainMessenger.crossDomainMessageSource(), _source);
    }

    /// @dev Tests that the `crossDomainMessageSource` function reverts when not entered.
    function test_crossDomainMessageSource_notEntered_reverts() external {
        // Ensure that the contract is not entered
        assertEq(l2ToL2CrossDomainMessenger.entered(), false);

        // Expect a revert with the NotEntered selector
        vm.expectRevert(NotEntered.selector);

        // Call `crossDomainMessageSource` to provoke revert
        l2ToL2CrossDomainMessenger.crossDomainMessageSource();
    }

    /// @dev Tests that the `crossDomainMessageContext` function returns the correct value.
    function testFuzz_crossDomainMessageContext_succeeds(
        address _sender,
        uint256 _source,
        uint8 _contextEncodingVersion,
        bytes32 _messagePayloadHash,
        address _txOrigin
    )
        external
    {
        bytes memory originContext = abi.encode(_contextEncodingVersion, _messagePayloadHash, _txOrigin);

        // Set `entered` to non-zero value to prevent NotEntered revert
        l2ToL2CrossDomainMessenger.setEntered(1);
        // Ensure that the contract is now entered
        assertEq(l2ToL2CrossDomainMessenger.entered(), true);

        // Set cross domain message source in the transient storage
        l2ToL2CrossDomainMessenger.setCrossDomainMessageSender(_sender);
        l2ToL2CrossDomainMessenger.setCrossDomainMessageSource(_source);
        l2ToL2CrossDomainMessenger.setCrossDomainMessageOriginContext(originContext);

        // Check that the `crossDomainMessageContext` function returns the correct value
        (address crossDomainContextSender, uint256 crossDomainContextSource, bytes memory crossDomainOriginContext) =
            l2ToL2CrossDomainMessenger.crossDomainMessageContext();
        assertEq(crossDomainContextSender, _sender);
        assertEq(crossDomainContextSource, _source);
        assertEq(crossDomainOriginContext, originContext);
    }

    /// @dev Tests that the `crossDomainMessageContext` function reverts when not entered.
    function test_crossDomainMessageContext_notEntered_reverts() external {
        // Ensure that the contract is not entered
        assertEq(l2ToL2CrossDomainMessenger.entered(), false);

        // Expect a revert with the NotEntered selector
        vm.expectRevert(NotEntered.selector);

        // Call `crossDomainMessageContext` to provoke revert
        l2ToL2CrossDomainMessenger.crossDomainMessageContext();
    }

    // 1. send message on A
    // 2. relay message on B
    // 3. relay message on C
    // 4. claim chain B on A
    // 4. claim chain C on A
    function test_primitivesAndGasTankIntegration_multipleMessages_succeeds() external {
        /* 0. send funds to gas tank from the user originating the messages */
        hoax(originUser, 0.01 ether);
        gasTank.deposit{ value: 0.01 ether }();

        /* 1. send message and flag it into the gas tank */
        vm.chainId(A);

        // Nest message for C on message for B
        bytes memory messageForC = abi.encodeCall(receiverOnC.receiveMessage, ());
        bytes memory messageForB = abi.encodeCall(chainByPass.sendMessage, (C, address(receiverOnC), messageForC));

        // Send message on A to B
        vm.startPrank(randomCaller, originUser);
        // rootMessageHash on the origin chain is the same as the message hash of the first Sent Message.
        bytes32 rootMessageHash = l2ToL2CrossDomainMessenger.sendMessage(B, address(chainByPass), messageForB);

        // Flag the message into the gas tank
        gasTank.flag(rootMessageHash);

        // Calculate the values
        bytes32 messageAPayloadHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: B,
            _source: A,
            _nonce: nonceA,
            _sender: randomCaller,
            _target: address(chainByPass),
            _message: messageForB
        });
        // This origin context must persist through the nested messages.
        bytes memory originContext =
            abi.encode(l2ToL2CrossDomainMessenger.ORIGIN_CONTEXT_ENCODING_VERSION(), messageAPayloadHash, originUser);

        assertEq(rootMessageHash, keccak256(abi.encodePacked(messageAPayloadHash, originContext)), "1");

        /* 2. relay message on B */
        vm.chainId(B);
        vm.fee(baseFeeOnB);

        uint256 nonceB = l2ToL2CrossDomainMessenger.messageNonce();
        bytes32 messageBPayloadHashOnSend = Hashing.hashL2toL2CrossDomainMessage({
            _destination: C,
            _source: B,
            _nonce: nonceB,
            _sender: address(chainByPass),
            _target: address(receiverOnC),
            _message: messageForC
        });

        // Check this matches on the event (Checked with vm.expectEmit in the relayMessage call on Step 3)
        bytes32 messageSentOnBHash = keccak256(abi.encodePacked(messageBPayloadHashOnSend, originContext));

        // Construct and relay the message
        Identifier memory id =
            Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, ID_BLOCK_NUMBER, logIndex++, ID_TIMESTAMP, A);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, B, address(chainByPass), nonceA), // topics
            abi.encode(randomCaller, messageForB, originContext) // data
        );

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: abi.encode("")
        });

        vm.expectEmit(address(chainByPass));
        emit ChainByPass.MessageHash(messageSentOnBHash);

        // Check only that emitted root hash and message hash on the gas receipt event are the same
        vm.expectEmit(address(l2ToL2CrossDomainMessenger));
        emit L2ToL2CrossDomainMessenger.RelayedMessageGasReceipt(
            rootMessageHash, rootMessageHash, relayer, originUser, 957390000000
        );

        changePrank(relayer);
        l2ToL2CrossDomainMessenger.relayMessage(id, sentMessage);

        /* 3. relay message */
        vm.chainId(C);
        vm.fee(baseFeeOnC);

        // Construct and relay the message
        id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, ID_BLOCK_NUMBER, logIndex++, ID_TIMESTAMP, B);
        sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, C, address(receiverOnC), nonceB), // topics
            abi.encode(address(chainByPass), messageForC, originContext) // data
        );

        // Ensure the CrossL2Inbox validates this message
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: abi.encode("")
        });

        vm.expectEmit(address(receiverOnC));
        emit ReceiverOnC.Received();

        vm.expectEmit(address(l2ToL2CrossDomainMessenger));
        emit L2ToL2CrossDomainMessenger.RelayedMessageGasReceipt(
            messageSentOnBHash, rootMessageHash, relayer, originUser, 64119000000
        );

        l2ToL2CrossDomainMessenger.relayMessage(id, sentMessage);

        /* 4. claim chain B on A */
        vm.chainId(A);

        id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, ID_BLOCK_NUMBER, logIndex++, ID_TIMESTAMP, B);
        bytes32 relayMessageOnBHash = keccak256(abi.encodePacked(messageAPayloadHash, originContext));

        assertEq(rootMessageHash, relayMessageOnBHash, "3");

        uint256 cost = 957390000000; // (with manually hardcoded cost obtained from the event)
        bytes memory gasReceiptPayload = abi.encodePacked(
            abi.encode(
                L2ToL2CrossDomainMessenger.RelayedMessageGasReceipt.selector,
                relayMessageOnBHash,
                rootMessageHash,
                relayer
            ), // topics
            abi.encode(originUser, cost) // data
        );

        // Mock crossl2inbox call
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(gasReceiptPayload))),
            returnData: abi.encode("")
        });

        uint256 relayerBalanceBefore = relayer.balance;
        uint256 userFundsBefore = gasTank.balanceOf(originUser);

        // Claim
        gasTank.claim(id, gasReceiptPayload);
        // Shouldn't be claimable 2 times
        vm.expectRevert(GasTank.AlreadyClaimed.selector);
        gasTank.claim(id, gasReceiptPayload);

        uint256 expectedRepayment = cost + (gasTank.CLAIM_OVERHEAD() * block.basefee);
        assertEq(relayer.balance, relayerBalanceBefore + expectedRepayment, "4");
        assertEq(gasTank.balanceOf(originUser), userFundsBefore - expectedRepayment, "5");

        /* 5. claim chain C on A */
        id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, ID_BLOCK_NUMBER, logIndex++, ID_TIMESTAMP, C);

        cost = 64119000000; // (with manually hardcoded cost obtained from the event)
        gasReceiptPayload = abi.encodePacked(
            abi.encode(
                L2ToL2CrossDomainMessenger.RelayedMessageGasReceipt.selector,
                messageSentOnBHash,
                rootMessageHash,
                relayer
            ), // topics
            abi.encode(originUser, cost) // data (with manually hardcoded cost obtained from the event)
        );

        assertNotEq(rootMessageHash, messageSentOnBHash, "6");

        userFundsBefore = gasTank.balanceOf(originUser);
        relayerBalanceBefore = relayer.balance;

        // Claim
        gasTank.claim(id, gasReceiptPayload);
        // Shouldn't be claimable 2 times
        vm.expectRevert(GasTank.AlreadyClaimed.selector);
        gasTank.claim(id, gasReceiptPayload);

        // Assert proper updates
        expectedRepayment = cost + (gasTank.CLAIM_OVERHEAD() * block.basefee);
        assertEq(relayer.balance, relayerBalanceBefore + expectedRepayment, "7");
        assertEq(gasTank.balanceOf(originUser), userFundsBefore - expectedRepayment, "8");
    }
}

contract ChainByPass {
    event MessageHash(bytes32);

    function sendMessage(
        uint256 _destination,
        address _target,
        bytes memory _message
    )
        external
        returns (bytes32 messageHash_)
    {
        messageHash_ = L2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).sendMessage(
            _destination, _target, _message
        );
        emit MessageHash(messageHash_);
    }
}

contract ReceiverOnC {
    event Received();

    function receiveMessage() external {
        emit Received();
    }
}
