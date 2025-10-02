// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISemver } from "interfaces/universal/ISemver.sol";

interface IMintingAuth is ISemver {
    error MintingAuth_Unauthorized();

    function lock() external;
    function unlock() external;
}
