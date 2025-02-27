// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @title ICrosschainERC20Factory
/// @notice This interface is available on the CrosschainERC20Factory contract.
interface ICrosschainERC20Factory is ISemver {
    error InvalidLength();

    function deployCrosschainERC20(string memory _name, string memory _symbol, uint256[] memory _minterLimits, uint256[] memory _burnerLimits, address[] memory _bridges) external returns (address crosschainERC20_);

    function deployCrosschainERC20WithLockbox(string memory _name, string memory _symbol, uint256[] memory _minterLimits, uint256[] memory _burnerLimits, address[] memory _bridges, address _baseToken) external returns (address crosschainERC20_, address crosschainERC20Lockbox_);

    function deployERC7802Adapter(address _xerc20, address _bridge) external returns (address erc7802Adapter_);
}