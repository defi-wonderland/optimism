// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { IXERC20 } from "@xERC20/interfaces/IXERC20.sol";
import { IERC7802 } from "interfaces/L2/IERC7802.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @title IERC7802Adapter
/// @notice This interface is available on the ERC7802Adapter contract.
interface IERC7802Adapter is IERC7802, ISemver {
    error Unauthorized();

    function XERC20() external view returns (IXERC20);

    function BRIDGE() external view returns (address);

    function supportsInterface(bytes4 _interfaceId) external view returns (bool);

    function __constructor__(IXERC20 _xerc20, address _bridge) external;
}