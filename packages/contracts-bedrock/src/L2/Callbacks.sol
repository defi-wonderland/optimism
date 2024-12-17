// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Identifier, IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

interface ICallbackGreeterMetadata {
    /// @notice Callback context to be executed (along with params if any) once the callback is received
    /// @param to Target address
    /// @param selector Function selector
    struct CallbackContext {
        address to;
        bytes4 selector;
    }

    /// @notice Emitted when the greeting is set
    /// @param greeting New greeting
    event GreetingSet(string greeting);

    /// @notice Emitted when an async call is sent
    /// @param contextNonce Nonce of the context
    event AsyncCallSent(uint224 contextNonce);

    /// @notice Emitted when the remote greeter is set
    /// @param remoteGreeter Address of the remote greeter
    event RemoteGreeterSet(address remoteGreeter);

    /// @notice Emitted when the callback is executed
    /// @param contextNonce Nonce of the context
    event CallbackExecuted(uint224 contextNonce);

    /// @notice Thrown when caller is not the owner
    error OnlyOwner();

    /// @notice Thrown when the callback fails
    error CallbackFailed();
}

contract CallbackGreeter is ICallbackGreeterMetadata {
    /// @notice Address of the L2ToL2CrossDomainMessenger contract
    address public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    /// @notice Address of the callback entrypoint
    address public immutable CALLBACK_ENTRYPOINT;

    /// @notice Owner of the contract
    address public immutable OWNER;

    /// @notice Nonce for the return context to be used as an identifier for the callback.
    ///         4 bytes are reserved for the callback selector.
    uint224 public returnContextNonce;

    /// @notice Greeting string
    string public greeting;

    /// @notice Remote greeter contract address
    address internal _remoteGreeter;

    /// @notice Contains the return context by nonce for the call to be made once the callback is received
    mapping(uint224 _nonce => CallbackContext) public callbackContexts;

    /**
     * @notice Reverts when the caller is not the owner.
     */
    modifier onlyOwner() {
        if (msg.sender != OWNER) revert OnlyOwner();
        _;
    }

    /**
     * @notice Constructs the CallbackGreeter contract.
     * @param _greeting Initial greeting.
     * @param _callbackEntrypoint Address of the callback entrypoint.
     */
    constructor(string memory _greeting, address _callbackEntrypoint) {
        OWNER = msg.sender;
        CALLBACK_ENTRYPOINT = _callbackEntrypoint;
        setGreeting(_greeting);
    }

    /**
     * @notice Sets the greeting.
     * @param _greeting New greeting.
     */
    function setGreeting(string memory _greeting) public onlyOwner {
        greeting = _greeting;
        emit GreetingSet(_greeting);
    }

    /**
     * @notice Initiates a remote greeting call handled by the callback.
     * @param _chainId Chain ID of the destination chain.
     * @param _callbackContext Target and selector to call once the callback is received on origin chain.
     * @return contextNonce_ Nonce of the context.
     */
    function remoteGreet(
        uint64 _chainId,
        CallbackContext calldata _callbackContext
    )
        external
        returns (uint224 contextNonce_)
    {
        bytes memory _targetCalldata = abi.encodeWithSelector(this.greeting.selector);
        bytes4 _callbackSelector = this.remoteGreetCallback.selector;
        contextNonce_ = async(_chainId, _targetCalldata, _callbackSelector, _callbackContext);
    }

    /// @notice Callback function for the remote greeting
    /// @param _contextNonce Nonce of the context
    /// @param _remoteData Data received from the remote greeter
    /// @return greeting_ The greeting
    /// @return balance_ The ETH balance of the caller
    function remoteGreetCallback(
        uint224 _contextNonce,
        bytes calldata _remoteData
    )
        external
        returns (string memory greeting_, uint256 balance_)
    {
        greeting_ = abi.decode(_remoteData, (string));

        balance_ = address(msg.sender).balance;

        // Obtain the return context
        CallbackContext memory _callbackContext = callbackContexts[_contextNonce];
        // Delete the return context
        delete callbackContexts[_contextNonce];

        // Call the callback
        (bool success,) =
            _callbackContext.to.call(abi.encodeWithSelector(_callbackContext.selector, greeting_, balance_));
        if (!success) revert CallbackFailed();

        emit CallbackExecuted(_contextNonce);
    }

    /// @notice Initiates an async call to the remote greeter through the CallbackEntrypoint.
    /// @param _chainid Chain ID of the destination chain.
    /// @param _targetCalldata Calldata to be sent to the target contract on destination.
    /// @param _callbackSelector Callback selector.
    /// @param _callbackContext Context to be executed once the callback is received.
    /// @return contextNonce_ Nonce of the context.
    function async(
        uint64 _chainid,
        bytes memory _targetCalldata,
        bytes4 _callbackSelector,
        CallbackContext calldata _callbackContext
    )
        internal
        returns (uint224 contextNonce_)
    {
        // Increment the nonce
        contextNonce_ = ++returnContextNonce;
        // Store the return context
        callbackContexts[contextNonce_] = _callbackContext;

        // Encode the target call along with the callback selector and the context nonce as the message and send it.
        bytes memory message = abi.encodePacked(_targetCalldata, _callbackSelector, contextNonce_);

        IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).sendMessage(
            _chainid, _remoteGreeter, message, CALLBACK_ENTRYPOINT
        );

        emit AsyncCallSent(contextNonce_);
    }

    /// @notice Setter for the remote greeter
    /// @param __remoteGreeter Address of the remote greeter
    function setRemoteGreeter(address __remoteGreeter) public onlyOwner {
        _remoteGreeter = __remoteGreeter;
        emit RemoteGreeterSet(__remoteGreeter);
    }
}

contract CallbackEntrypoint {
    /// @notice Address of the L2ToL2CrossDomainMessenger contract
    address public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    /// @notice Relays a message that was sent by the other CrossDomainMessenger contract.
    /// @param _id Identifier of the SentMessage event to be relayed.
    /// @param _sentMessage Message payload of the `SentMessage` event.
    /// @return returnData_ Return data from the target contract call.
    function relayMessage(
        Identifier calldata _id,
        bytes calldata _sentMessage
    )
        external
        payable
        returns (bytes memory returnData_)
    {
        // Call the CDM contract and get return value of the target call
        returnData_ = IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage(_id, _sentMessage);

        // 0 to 32 bytes: SentMessage selector
        // 32 to 128 bytes: destination (uint256), target (address), nonce (uint256)
        // 128 to end: sender (address), actual message (bytes), entrypoint (address)
        (address originSender,, bytes memory inputMessage) = abi.decode(_sentMessage[128:], (address, address, bytes));

        // The callback selector and params are in the last 32 bytes of the actual message, we need to substract 32
        // taking into account the 32 bytes of the entrypoint.
        uint256 totalLen = 128 + 32 + 32 + 32 + 32 + inputMessage.length;

        bytes4 selector = bytes4(_sentMessage[totalLen - 32:totalLen - 28]);
        uint224 nonce = uint224(bytes28(_sentMessage[totalLen - 28:totalLen]));

        // Encode the callback selector, params and returned data as the message, and sent back to the origin sender
        bytes memory messageToSend = abi.encodeWithSelector(bytes4(selector), nonce, returnData_);

        IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).sendMessage(
            _id.chainId, originSender, messageToSend
        );
    }
}
