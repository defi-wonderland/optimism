// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISuperchainERC20 } from "../../interfaces/L2/ISuperchainERC20.sol";

interface ISuperToken is ISuperchainERC20 {
    function mint(address _to, uint256 _amount) external;
}
