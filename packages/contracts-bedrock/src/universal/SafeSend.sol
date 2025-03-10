// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title  SafeSend
/// @notice Sends ETH to a recipient account without triggering any code.
contract SafeSend {
    /// @param _recipient Account to send ETH to.
    constructor(address payable _recipient) payable {
        /// NOTE: Send any ETH leftover to zero address, to avoid any potential issues derived from
        ///       a mismatch between the expected and actual ETH amount sent to the recipient.
        uint256 diff = address(this).balance - msg.value;
        if (diff != 0) payable(address(0)).transfer(diff);

        selfdestruct(_recipient);
    }
}
