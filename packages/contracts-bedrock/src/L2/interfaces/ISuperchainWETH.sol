// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IWETH } from "src/universal/interfaces/IWETH.sol";

interface ISuperchainWETH {
    error NotCustomGasToken();

    /// @notice Thrown when attempting to relay a message and the function caller (msg.sender) is not
    /// L2ToL2CrossDomainMessenger.
    error CallerNotL2ToL2CrossDomainMessenger();

    /// @notice Thrown when attempting to relay a message and the cross domain message sender is not `address(this)`
    error InvalidCrossDomainSender();

    event RelayERC20(address indexed from, address indexed to, uint256 amount, uint256 source);
    event SendERC20(address indexed from, address indexed to, uint256 amount, uint256 destination);

    function relayERC20(address from, address dst, uint256 wad) external;
    function sendERC20(address dst, uint256 wad, uint256 chainId) external;
}

interface ISuperchainWETHERC20 is IWETH, ISuperchainWETH { }
