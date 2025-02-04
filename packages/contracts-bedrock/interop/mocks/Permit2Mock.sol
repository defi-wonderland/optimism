// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mock of Permit2 for testing WETH transfers with Permit2 Preinstall address
contract Permit2Mock {
    using SafeERC20 for IERC20;

    /// @notice Transfers the given amount of WETH from the given address to the given address.
    /// @param src The address to transfer the WETH from.
    /// @param dst The address to transfer the WETH to.
    /// @param wad The amount of WETH to transfer.
    function permitTransferFrom(address token, address src, address dst, uint256 wad) external {
        IERC20(token).safeTransferFrom(src, dst, wad);
    }
}
