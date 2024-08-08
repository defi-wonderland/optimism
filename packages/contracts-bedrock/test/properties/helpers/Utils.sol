// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MockERC20 } from "forge-std/mocks/MockERC20.sol";

contract FuzzERC20 is MockERC20 {
    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) public {
        _burn(_from, _amount);
    }
}
