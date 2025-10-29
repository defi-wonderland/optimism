// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { FeeSplitter } from "src/L2/FeeSplitter.sol";

contract FeeSplitterForTest is FeeSplitter {
    function setTransientDisbursingAddress(address _allowedCaller) external {
        _setTransientDisbursingAddress(_allowedCaller);
    }
}
