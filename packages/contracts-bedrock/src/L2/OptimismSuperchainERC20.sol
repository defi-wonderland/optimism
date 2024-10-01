// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Predeploys } from "src/libraries/Predeploys.sol";
import { SuperchainERC20 } from "src/L2/SuperchainERC20.sol";
import { IOptimismSuperchainERC20Extension } from "src/L2/interfaces/IOptimismSuperchainERC20.sol";

/// @custom:proxied true
/// @title OptimismSuperchainERC20
/// @notice OptimismSuperchainERC20 is a standard extension of the base ERC20 token contract that unifies ERC20 token
///         bridging to make it fungible across the Superchain. This construction allows the L2StandardBridge to burn
///         and mint tokens. This makes it possible to convert a valid OptimismMintableERC20 token to a
///         OptimismSuperchainERC20 token, turning it fungible and interoperable across the superchain. Likewise, it
///         also enables the inverse conversion path.
///         Moreover, it builds on top of the L2ToL2CrossDomainMessenger for both replay protection and domain binding.
contract OptimismSuperchainERC20 is SuperchainERC20, IOptimismSuperchainERC20Extension {
    /// @notice Semantic version.
    /// @custom:semver 1.0.0-beta
    string public constant override version = "1.0.0-beta";

    modifier onlyL2StandardBridge() {
        if (msg.sender != Predeploys.L2_STANDARD_BRIDGE) revert OnlyL2StandardBridge();
        _;
    }

    /// @notice Allows the L2StandardBridge and SuperchainERC20Bridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function mint(address _to, uint256 _amount) external virtual onlyL2StandardBridge {
        if (_to == address(0)) revert ZeroAddress();

        _mint(_to, _amount);

        emit Burn(_to, _amount);
    }

    /// @notice Allows the L2StandardBridge and SuperchainERC20Bridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function burn(address _from, uint256 _amount) external virtual onlyL2StandardBridge {
        if (_from == address(0)) revert ZeroAddress();

        _burn(_from, _amount);

        emit Burn(_from, _amount);
    }
}
