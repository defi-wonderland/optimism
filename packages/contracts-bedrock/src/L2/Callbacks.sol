// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IGreeter } from "interfaces/IGreeter.sol";
import { Identifier, IL2ToL2CrossDomainMessenger } from "interfaces/IL2ToL2CrossDomainMessenger.sol";

struct CallbackContext {
    address to;
    bytes4 selector;
}

contract Greeter is IGreeter {
    /**
     * @notice Empty string for revert checks
     * @dev result of doing keccak256(bytes(''))
     */
    bytes32 internal constant _EMPTY_STRING = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    address public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = address(0);
    address public constant CALLBACK_ENTRYPOINT = address(0);

    /// @inheritdoc IGreeter
    address public immutable OWNER;

    /// @inheritdoc IGreeter
    string public greeting;

    /// @inheritdoc IGreeter
    IERC20 public token;

    // 4 bytes are reserved for the callback selector
    uint224 public returnContextNonce;
    // Holds the return context for the async remoteGreet call
    mapping(uint224 => CallbackContext) public callbackContexts;

    /**
     * @notice Reverts in case the function was not called by the owner of the contract
     */
    modifier onlyOwner() {
        if (msg.sender != OWNER) {
            revert Greeter_OnlyOwner();
        }
        _;
    }

    /**
     * @notice Defines the owner to the msg.sender and sets the initial greeting
     * @param _greeting Initial greeting
     * @param _token Initial token
     */
    constructor(string memory _greeting, IERC20 _token) {
        OWNER = msg.sender;
        token = _token;
        setGreeting(_greeting);
    }

    /// @inheritdoc IGreeter
    function greet() external view returns (string memory _greeting, uint256 _balance) {
        _greeting = greeting;
        _balance = token.balanceOf(msg.sender);
    }

    /// @inheritdoc IGreeter
    function setGreeting(string memory _greeting) public onlyOwner {
        if (keccak256(bytes(_greeting)) == _EMPTY_STRING) {
            revert Greeter_InvalidGreeting();
        }

        greeting = _greeting;
        emit GreetingSet(_greeting);
    }

    /**
     * @notice Initiates a remote greeting call handled by the callback
     * @return contextNonce_
     */
    function remoteGreet(CallbackContext calldata _callbackContext) external returns (uint224 contextNonce_) {
        contextNonce_ = async(
            1, abi.encodeWithSelector(this.greeting.selector), this.remoteGreetCallback.selector, _callbackContext
        );
    }

    function remoteGreetCallback(
        uint224 _contextNonce,
        string memory _remoteGreeting
    )
        external
        view
        returns (string memory _greeting, uint256 _balance)
    {
        _greeting = _remoteGreeting;
        _balance = token.balanceOf(msg.sender);

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
        contextNonce_ = returnContextNonce++;
        // store the return context
        callbackContexts[nonce] = _callbackContext;

        _messageHash = IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).sendMessage(
            _chainid,
            address(this),
            // data + callback selector
            abi.encodePacked(_data, _callbackSelector, contextNonce_),
            //abi.encodePacked(_data, _callbackSelector, contextNonce_, 32), // 32 bytes can be dynamic [IMPROVEMENT]
            CALLBACK_ENTRYPOINT
        );
    }
}

contract CallbackEntrypoint {
    address public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = address(0);

    function relayMessage(Identifier calldata _id, bytes calldata _sentMessage) external payable {
        // Calls the CDM contract and get return value of the function call
        bytes _data = IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage(_id, _sentMessage);

        // get the last 32 bytes of _sentMessage (4 bytes for the callback selector and 28 bytes for the contextNonce)
        bytes32 _callbackSelectorAndParams = abi.decode(_sentMessage[_sentMessage.length - 32:], (bytes32));
        // Creates new CDM message to _sentMessage origin, sender and _callbackSelector with the return value
        IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).sendMessage(
            _id.chainId, _id.origin, abi.encodePacked(_callbackSelectorAndParams, _data)
        );
    }
}
