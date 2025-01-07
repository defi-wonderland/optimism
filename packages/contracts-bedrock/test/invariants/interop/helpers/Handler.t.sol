// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Setup } from "../Setup.sol";
import { Actors } from "./Actors.t.sol";

contract Handler is Setup, Actors {
    /// @notice Mint SUPER_TOKEN to an actor
    /// @param _amount Amount to mint
    function handler_mintSuperchainERC20(uint256 _amount) external {
        _amount = clampLte(_amount, type(uint256).max - SUPER_TOKEN.totalSupply());
        SUPER_TOKEN.mint(address(currentActor()), _amount);
    }
}
