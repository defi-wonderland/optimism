// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Identifier, IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

struct CallbackContext {
    address to;
    bytes4 selector;
}

contract Greeter {
    /**
     * @notice Empty string for revert checks
     * @dev result of doing keccak256(bytes(''))
     */
    bytes32 internal constant _EMPTY_STRING = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    address public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;
    address public constant CALLBACK_ENTRYPOINT = address(0); // TODO: add setter

    address public immutable OWNER;

    string public greeting;

    address internal _remoteGreeter;

    // 4 bytes are reserved for the callback selector
    uint224 public returnContextNonce;
    // Holds the return context for the async remoteGreet call
    mapping(uint224 => CallbackContext) public callbackContexts;

    /**
     * @notice Reverts in case the function was not called by the owner of the contract
     */
    modifier onlyOwner() {
        if (msg.sender != OWNER) {
            revert("only owner");
        }
        _;
    }

    /**
     * @notice Defines the owner to the msg.sender and sets the initial greeting
     * @param _greeting Initial greeting
     */
    constructor(string memory _greeting) {
        OWNER = msg.sender;
        setGreeting(_greeting);
    }

    function greet() external view returns (string memory _greeting, uint256 _balance) {
        _greeting = greeting;
        _balance = address(msg.sender).balance;
    }

    function setGreeting(string memory _greeting) public onlyOwner {
        if (keccak256(bytes(_greeting)) == _EMPTY_STRING) {
            revert("Greeter_InvalidGreeting");
        }

        greeting = _greeting;
        // emit GreetingSet(_greeting);
    }

    /**
     * @notice Initiates a remote greeting call handled by the callback
     * @return contextNonce_
     */
    function remoteGreet(CallbackContext calldata _callbackContext) external returns (uint224 contextNonce_) {
        contextNonce_ = async(
            2, // TODO: receive param
            abi.encodeWithSelector(this.greeting.selector),
            this.remoteGreetCallback.selector,
            _callbackContext
        );
    }

    function remoteGreetCallback(
        uint224 _contextNonce,
        string memory _remoteGreeting
    )
        external
        returns (string memory _greeting, uint256 _balance)
    {
        _greeting = _remoteGreeting;
        _balance = address(msg.sender).balance;

        // obtain the return context
        CallbackContext memory _callbackContext = callbackContexts[_contextNonce];
        // delete the return context
        delete callbackContexts[_contextNonce];

        // call the callback (not sure if we should check for success...)
        _callbackContext.to.call(abi.encodeWithSelector(_callbackContext.selector, _greeting, _balance));
    }

    // builds the cdm call with the callback entrypoint
    function async(
        uint256 _chainid,
        bytes memory _data,
        bytes4 _callbackSelector,
        CallbackContext calldata _callbackContext
    )
        internal
        returns (uint224 contextNonce_)
    {
        // increment the nonce
        contextNonce_ = ++returnContextNonce;
        // store the return context
        callbackContexts[contextNonce_] = _callbackContext;

        IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).sendMessage(
            _chainid,
            _remoteGreeter,
            // data + callback selector
            abi.encodePacked(_data, _callbackSelector, contextNonce_),
            //abi.encodePacked(_data, _callbackSelector, contextNonce_, 32), // 32 bytes can be dynamic [IMPROVEMENT]
            CALLBACK_ENTRYPOINT
        );
    }

    // Setter for the remote greeter WIP without auth for now.
    function setRemoteGreeter(address __remoteGreeter) public {
        _remoteGreeter = __remoteGreeter;
    }
}

contract CallbackEntrypoint {
    address public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    function relayMessage(
        Identifier calldata _id,
        bytes calldata _sentMessage
    )
        external
        payable
        returns (bytes memory returnData_)
    {
        // Calls the CDM contract and get return value of the function call
        returnData_ = IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage(_id, _sentMessage);

        // 0 to 31 bytes: SentMessage selector
        // 32 to 127 bytes: destination (uint256), target (address), nonce (uint256)
        // 128 to end: sender (address), actual message (bytes), entrypoint (address)
        (address sender) = abi.decode(_sentMessage[128:160], (address));

        // the callback selector and params are in the last 32 bytes of the actual message, we need to take into
        // account the 32 bytes of the entrypoint.
        bytes32 _callbackSelectorAndParams =
            abi.decode(_sentMessage[_sentMessage.length - 64:_sentMessage.length - 32], (bytes32));

        // Creates new CDM message to _sentMessage origin, sender and _callbackSelector with the return value
        IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).sendMessage(
            _id.chainId, sender, abi.encodePacked(_callbackSelectorAndParams, returnData_)
        );
    }
}

// 1. Chain A: remoteGreet -> async -> sendMessage

// 2. Chain B:  entrypoint.relayMessage -> cdm.relayMessage -> greeting + remoteGreetCallback(nonce, ) ->
// sendMessage(chainA, greeterA, remoteGreetCallback)

// 3. Chain A: CDM.relayMessage -> remoteGreetCallback -> target call
