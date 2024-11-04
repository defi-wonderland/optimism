// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Ownable } from "@openzeppelin/contracts-v5/access/Ownable.sol";

interface IOPContractsManager {
    function systemConfigs(uint256 _chainId) external view returns (address);
}

interface ISystemConfigInterop {
    function addDependencies(uint256[] calldata _chainIds) external;

    function addDependency(uint256 _chainId) external;
}

// contract DependencySetManager is Ownable {
contract DependencySetManager is Ownable {
    enum Status {
        Pristine,
        Registered,
        Active
    }

    /// The OPContractsManager contract address
    IOPContractsManager public opContractsManager;

    // Mapping from chainId to SystemConfigInterop address
    mapping(uint256 _chainId => address systemConfigInterop_) public systemConfigInterops; // si esta aca

    // Mapping to check if a chainId is in the dependency set
    mapping(uint256 _chainId => Stats status_) public chainsStatus;

    // Current dependency set list
    uint256[] public dependencySet; // no esta aca

    function registerChain(uint256 _chainId) external {
        // Check is not alredy registered
        require(systemConfigInterops[_chainId] == address(0), "Chain already registered");

        // Check is compatible
        address systemConfig = opContractsManager.systemConfigs(_chainId);
        require(systemConfig != address(0), "Chain not compatible");

        chainsStatus[_chainId] = Status.Registered;
        systemConfigInterops[_chainId] = systemConfig;

        emit ChainRegistered(_chainId);
    }

    function addChain(uint256 _chainId) external onlyOwner {
        require(chainsStatus[_chainId] == Status.Registered, "Chain status needs to be on registered status");
        chainsStatus[_chainId] = Status.Active;

        for (uint256 i; i < _dependencySet.length; i++) {
            // Check that the dependency wasn't removed from the dependency set before calling its systemConfigInterop
            if (chainsStatus[_chainId] == Status.Active) {
                systemConfigInterops[_dependencySet[i]].addChain(_chainId);
            }
        }

        ISystemConfigInterop(systemConfigInterops[_chainId]).addDependencies(dependencySet);
        dependencySet.push(_chainId);

        emit ChainAdded(chainId);
    }

    function removeChain(uint256 _chainId) external onlyOwner {
        require(chainsStatus[_chainId] == Status.Active, "Chain status needs to be on active status");
        chainsStatus[_chainId] = Status.Registered;

        // Remove chain from dependencies
        for (uint256 i; i < _dependencySet.length; i++) {
            // Check that the dependency wasn't removed from the dependency set before calling its systemConfigInterop
            if (chainsStatus[_chainId] == Status.Active) {
                systemConfigInterops[_dependencySet[i]].removeChain(_chainId);
            }
        }

        // Remove all dependencies from the removing chain
        ISystemConfigInterop(systemConfigInterops[_chainId]).removeDependencies(dependencySet);

        emit ChainRemoved(_chainId, _status);
    }

    function isRegistered(uint256 _chainId) external view returns (bool) { }

    function isActive(uint256 _chainId) external view returns (bool) { }
}
