// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { IERC7802 } from "interfaces/L2/IERC7802.sol";
import { IXERC20 } from "interfaces/L2/IXERC20.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IOwnable } from "interfaces/universal/IOwnable.sol";

/// @title IXSuperchainERC20
/// @notice This interface is available on the XSuperchainERC20 contract.
/// @dev This interface is needed for the abstract XSuperchainERC20 implementation but is not part of the standard
interface IXSuperchainERC20 is IERC7802, IXERC20, ISemver, IOwnable {
    error Unauthorized();

    function supportsInterface(bytes4 _interfaceId) external view returns (bool);

    function __constructor__(string memory _name, string memory _symbol, address _factory) external;
}
