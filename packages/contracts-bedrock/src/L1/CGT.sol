// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC20 } from "lib/solady-v0.0.245/src/tokens/ERC20.sol";
import { Ownable } from "lib/solady-v0.0.245/src/auth/Ownable.sol";

/// @title CGT
/// @notice Custom Gas Token implementation using Solady's ERC20 and Ownable
contract CGT is ERC20, Ownable {
    /// @dev Constructor sets the deployer as the owner
    constructor() {
        _initializeOwner(msg.sender);
    }

    /// @dev Returns the name of the token
    function name() public pure override returns (string memory) {
        return "Custom Gas Token";
    }

    /// @dev Returns the symbol of the token
    function symbol() public pure override returns (string memory) {
        return "CGT";
    }

    /// @dev Mint tokens to a specific address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}