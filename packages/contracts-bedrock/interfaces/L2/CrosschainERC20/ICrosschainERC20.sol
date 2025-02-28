// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { IERC7802 } from "interfaces/L2/IERC7802.sol";
import { IXERC20 } from "@xERC20/interfaces/IXERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @title ICrosschainERC20
/// @notice This interface is available on the CrosschainERC20 contract.
interface ICrosschainERC20 is IERC20Metadata, IXERC20, IERC7802, ISemver {
    // External dependencies events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event EIP712DomainChanged();

    // External dependencies errors
    error InvalidShortString();
    error StringTooLong(string str);

    // ERC20 functions
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    // ERC20Permit functions
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    // ERC5267 functions
        function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );

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
