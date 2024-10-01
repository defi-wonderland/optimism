// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { ISuperchainERC20, ISuperchainERC20Extension } from "src/L2/interfaces/ISuperchainERC20.sol";
import { IERC20Solady } from "src/vendor/interfaces/IERC20Solady.sol";

/// @title ISuperchainERC20Errors
/// @notice Interface containing the errors added in the SuperchainERC20 implementation.
interface IOptimismSuperchainERC20Errors {
    /// @notice Thrown when attempting to mint or burn tokens and the function caller is not the L2StandardBridge
    error OnlyL2StandardBridge();
}

/// @title ISuperchainERC20Extension
/// @notice This interface is available on the SuperchainERC20 contract.
interface IOptimismSuperchainERC20Extension is ISuperchainERC20Extension, IOptimismSuperchainERC20Errors {
    /// @notice Allows the L2StandardBridge and SuperchainERC20Bridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function mint(address _to, uint256 _amount) external;

    /// @notice Allows the L2StandardBridge and SuperchainERC20Bridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function burn(address _from, uint256 _amount) external;

    /// @notice Returns the address of the corresponding version of this token on the remote chain.
    function remoteToken() external view returns (address);
}

/// @title ISuperchainERC20
/// @notice Combines Solady's ERC20 interface with the SuperchainERC20Extension interface.
interface IOptimismSuperchainERC20 is IERC20Solady, IOptimismSuperchainERC20Extension { }
