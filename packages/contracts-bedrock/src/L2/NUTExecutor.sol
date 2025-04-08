// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

abstract contract NUTExecutor {
    function execute() external virtual returns (bytes memory);
}
