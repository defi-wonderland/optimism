// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { ICrosschainERC20 } from "src/L2/interfaces/ICrosschainERC20.sol";
import { IERC20Solady } from "src/vendor/interfaces/IERC20Solady.sol";

/// @title ISuperchainERC20Errors
/// @notice Interface containing the errors added in the SuperchainERC20 implementation.
interface ISuperchainERC20Errors {
    /// @notice Thrown when attempting to mint or burn tokens and the function caller is not the SuperchainERC20Bridge.
    error OnlySuperchainERC20Bridge();
}

/// @title ISuperchainERC20Extension
/// @notice This interface is available on the SuperchainERC20 contract.
interface ISuperchainERC20Extension is ICrosschainERC20, ISuperchainERC20Errors { }

/// @title ISuperchainERC20
/// @notice Combines Solady's ERC20 interface with the SuperchainERC20Extension interface.
interface ISuperchainERC20 is IERC20Solady, ISuperchainERC20Extension {
    function __constructor__() external;
}
