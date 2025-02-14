// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { XSuperchainERC20 } from "src/L2/XSuperchainERC20.sol";

/// @title XSuperchainERC20Implementation Mock contract
/// @notice Mock contract just to create tests over an implementation of the XSuperchainERC20 abstract contract.
contract MockXSuperchainERC20Implementation is XSuperchainERC20 {
    constructor(string memory _name, string memory _symbol, address _factory) XSuperchainERC20(_name, _symbol, _factory) {}

    function name() public pure override returns (string memory) {
        return "Test";
    }

    function symbol() public pure override returns (string memory) {
        return "TST";
    }
}
