// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IOPContractsManager {
    function systemConfigs(uint256 _chainId) external view returns (address);
}

interface ISystemConfigInterop {
    function addDependencies(uint256[] calldata _chainIds) external;

    function addDependency(uint256 _chainId) external;
}

contract DependencySetManager {
    using EnumerableSet for EnumerableSet.UintSet;

    event ChainAdded(uint256 indexed chainId);

    // The address of the DependencyManager contract
    address public dependencyManager;

    /// The OPContractsManager contract address
    IOPContractsManager public opContractsManager;

    // Mapping from chainId to SystemConfigInterop address
    mapping(uint256 _chainId => ISystemConfigInterop) public systemConfigInterops;

    /// @notice The interop dependency set, containing the chain IDs in it.
    EnumerableSet.UintSet internal _dependencySet;

    function addChain(uint256 _chainId) external {
        require(msg.sender == dependencyManager, "Unauthorized");

        // Add to the dependency set and check it is not already added (`add()` returns false if it already exists)
        require(_dependencySet.add(_chainId), "Chain already added");

        // Check is compatible
        address systemConfig = opContractsManager.systemConfigs(_chainId);
        require(systemConfig != address(0), "Chain not compatible");

        // Loop through the dependency set (except the newly added chain) and add it as a dependency for each chain
        for (uint256 i; i < _dependencySet.length() - 1; i++) {
            systemConfigInterops[_dependencySet.at(i)].addDependency(_chainId);
        }

        // Add all dependencies on the new chain
        systemConfigInterops[_chainId].addDependencies(_dependencySet.values());

        emit ChainAdded(_chainId);
    }

    function dependencySet() external view returns (uint256[] memory) {
        return _dependencySet.values();
    }

    function isInDependencySet(uint256 _chainId) public view returns (bool) {
        return _dependencySet.contains(_chainId);
    }
}
