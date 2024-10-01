// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ISuperchainERC20Extension } from "src/L2/interfaces/ISuperchainERC20.sol";
import { ISemver } from "src/universal/interfaces/ISemver.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";

/// @title SuperchainERC20
/// @notice SuperchainERC20 is a standard extension of the base ERC20 token contract that unifies ERC20 token
///         bridging to make it fungible across the Superchain. This construction allows the L2StandardBridge to burn
///         and mint tokens. This makes it possible to convert a valid OptimismMintableERC20 token to a
///         SuperchainERC20 token, turning it fungible and interoperable across the superchain. Likewise, it
///         also enables the inverse conversion path.
///         Moreover, it builds on top of the L2ToL2CrossDomainMessenger for both replay protection and domain binding.
abstract contract SuperchainERC20 is ERC20, ISuperchainERC20Extension, ISemver {
    /// @notice A modifier that only allows the bridge to call
    modifier onlySuperchainERC20Bridge() {
        if (msg.sender != Predeploys.SUPERCHAIN_ERC20_BRIDGE) revert OnlySuperchainERC20Bridge();
        _;
    }

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-beta.6
    function version() external pure virtual returns (string memory) {
        return "1.0.0-beta.6";
    }

    /// @notice Allows the SuperchainERC20Bridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function __superchainMint(address _to, uint256 _amount) external virtual onlySuperchainERC20Bridge {
        if (_to == address(0)) revert ZeroAddress();

        _mint(_to, _amount);

        emit SuperchainMint(_to, _amount);
    }

    /// @notice Allows the SuperchainERC20Bridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function __superchainBurn(address _from, uint256 _amount) external virtual onlySuperchainERC20Bridge {
        if (_from == address(0)) revert ZeroAddress();

        _burn(_from, _amount);

        emit SuperchainBurn(_from, _amount);
    }
}
