// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IBeacon } from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

/// @title SuperchainERC20Beacon
/// @notice SuperchainERC20Beacon is the beacon proxy for the SuperchainERC20 implementation.
contract SuperchainERC20Beacon is IBeacon {
    /// TODO: Replace with real implementation address
    /// @notice Address of the SuperchainERC20 implementation.
    address internal constant IMPLEMENTATION_ADDRESS = 0x0000000000000000000000000000000000000000;

    /// @inheritdoc IBeacon
    function implementation() external pure override returns (address) {
        return IMPLEMENTATION_ADDRESS;
    }
}
