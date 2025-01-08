// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Setup } from "../Setup.sol";
import { Actors } from "./Actors.t.sol";

contract Handler is Setup, Actors {
    uint256 internal constant _ZERO_VALUE = 0;

    // /// @notice Mint SUPER_TOKEN to an actor
    // /// @param _amount Amount to mint
    // function handler_mintSuperchainERC20(uint256 _amount) public {
    //     _amount = clampLte(_amount, type(uint256).max - SUPER_TOKEN.totalSupply());

    //     // direct call instead
    //     Actors actor = currentActor();

    //     try actor.directCall(
    //         address(SUPER_TOKEN),
    //         _ZERO_VALUE,
    //         abi.encodeWithSelector(SUPER_TOKEN.mint.selector, address(actor), _amount)
    //     ) { } catch {
    //         assert(false);
    //     }
    // }

    function handler_depositSuperchainWETH(uint256 _value) public {
        _value = clampLte(_value, type(uint256).max - SUPER_WETH.totalSupply());

        Actors actor = currentActor();
        vm.deal(address(actor), _value);

        try actor.directCall(address(SUPER_WETH), _value, abi.encodeWithSelector(SUPER_WETH.deposit.selector)) { }
        catch {
            assert(false);
        }
    }

    function handler_withdrawSuperchainWETH(uint256 _value) public {
        Actors actor = currentActor();
        _value = clampLte(_value, SUPER_WETH.balanceOf(address(actor)));

        try actor.directCall(
            address(SUPER_WETH), _ZERO_VALUE, abi.encodeWithSelector(SUPER_WETH.withdraw.selector, _value)
        ) { } catch {
            assert(false);
        }
    }

    // TODO: Add relayETH and sendETH functions
}
