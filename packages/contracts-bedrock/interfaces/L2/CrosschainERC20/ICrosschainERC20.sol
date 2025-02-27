// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { IERC7802 } from "interfaces/L2/IERC7802.sol";
import { IXERC20 } from "@xERC20/interfaces/IXERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts-v5/token/ERC20/extensions/IERC20Permit.sol";
import { IERC5267 } from "@openzeppelin/contracts-v5/interfaces/IERC5267.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @title ICrosschainERC20
/// @notice This interface is available on the CrosschainERC20 contract.
interface ICrosschainERC20 is IERC20Metadata, IERC20Permit, IERC5267, IXERC20, IERC7802, ISemver {
    // External dependencies events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // External dependencies errors
    error InvalidShortString();
    error StringTooLong(string str);

    // ERC20 functions
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    // XERC20 functions
    function FACTORY() external view returns (address);
    function bridges(address) external view returns (BridgeParameters memory minterParams, BridgeParameters memory burnerParams);
    function lockbox() external view returns (address);
    function mintingCurrentLimitOf(address _bridge) external view returns (uint256 _limit);
    function mintingMaxLimitOf(address _bridge) external view returns (uint256 _limit);

    // Ownable functions
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function renounceOwnership() external;

    // Contract functions
    function supportsInterface(bytes4 _interfaceId) external view returns (bool);

    function __constructor__(string memory _name, string memory _symbol, address _factory) external;
}
