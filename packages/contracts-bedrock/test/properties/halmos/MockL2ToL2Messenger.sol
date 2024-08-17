// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "src/L2/L2ToL2CrossDomainMessenger.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";

// TODO: Try to merge to a single mocked contract used by fuzzing and symbolic invariant tests - only if possible
// and is a low priorty
contract MockL2ToL2Messenger is IL2ToL2CrossDomainMessenger {
    /// NOTE: Setting everything as immutable bc the storage layour is ignored when etching.
    address internal immutable SOURCE_TOKEN;
    address internal immutable DESTINATION_TOKEN;
    uint256 public immutable DESTINATION_CHAIN_ID;
    // Custom cross domain sender to be used when neither the source nor destination token are the callers
    address internal immutable CUSTOM_CROSS_DOMAIN_SENDER;

    constructor(
        address _sourceToken,
        address _destinationToken,
        uint256 _destinationChainId,
        address _customCrossDomainSender
    ) {
        SOURCE_TOKEN = _sourceToken;
        DESTINATION_TOKEN = _destinationToken;
        DESTINATION_CHAIN_ID = _destinationChainId;
        CUSTOM_CROSS_DOMAIN_SENDER = _customCrossDomainSender;
    }

    function sendMessage(uint256 _destination, address, bytes calldata _message) external payable {
        // Mocking the environment to allow atomicity by executing the message call
        if (_destination == DESTINATION_CHAIN_ID) {
            (bool _success) = SafeCall.call(DESTINATION_TOKEN, 0, _message);
            if (!_success) revert("MockL2ToL2Messenger: sendMessage failed");
        }
    }

    function relayMessage(
        uint256,
        uint256,
        uint256,
        address,
        address _target,
        bytes calldata _message
    )
        external
        payable
    {
        (bool succ, bytes memory ret) = _target.call{ value: msg.value }(_message);
        if (!succ) revert(string(ret));

        // TODO: Add more logic? Like replacing the (unsupported) `TSTORE` updates with `SSTORE` - or add the checks
    }

    function crossDomainMessageSource() external view returns (uint256 _source) {
        _source = block.chainid + 1;
    }

    // Mock this function so it just always returns the expected if called by the supertoken, or otherwise defaults to
    // the custom cross domain sender
    function crossDomainMessageSender() external view returns (address _sender) {
        if (msg.sender == SOURCE_TOKEN) _sender = SOURCE_TOKEN;
        else if (msg.sender == DESTINATION_TOKEN) _sender = DESTINATION_TOKEN;
        else _sender = CUSTOM_CROSS_DOMAIN_SENDER;
    }
}
