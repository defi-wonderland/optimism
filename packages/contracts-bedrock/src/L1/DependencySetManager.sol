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
        Pending,
        Active,
        Inactive,
        Removed
    }

    /// The OPContractsManager contract address
    IOPContractsManager public opContractsManager;

    // Mapping from chainId to SystemConfigInterop address
    mapping(uint256 _chainId => address systemConfigInterop_) public systemConfigInterops;

    // Mapping to check if a chainId is in the dependency set
    mapping(uint256 _chainId => Stats status_) public chainsStatus;

    // Current dependency set list
    uint256[] public dependencySet;

    function registerChain(uint256 _chainId) external {
        // Check is not alredy registered
        require(systemConfigInterops[_chainId] == address(0), "Chain already registered");

        // Check is compatible
        require(opContractsManager.systemConfigs(_chainId) != address(0), "Chain not compatible");

        // TODO: chainIdToBatchInboxAddress? --> think
        // TODO: Superchain Registry? -> probably not needed

        chainsStatus[_chainId] = Status.Pending;

        emit ChainRegistered(_chainId);
    }

    function addChain(uint256 _chainId) external onlyOwner {
        require(systemConfigInterops[_chainId] == address(0), "Chain already added");
        require(chainsStatus[_chainId] == Status.Pending, "Chain status needs to be pending");
        chainsStatus[_chainId] = Status.Active;

        for (uint256 i; i < _dependencySet.length; i++) {
            // Check that the dependency wasn't removed from the dependency set before calling its systemConfigInterop
            if (chainsStatus[_chainId] != Status.Active) {
                systemConfigInterops[_dependencySet[i]].addChain(_chainId);
            }
        }

        ISystemConfigInterop(systemConfigInterops[_chainId]).addDependencies(dependencySet);
        dependencySet.push(_chainId);

        emit ChainAdded(chainId);
    }

    function updateChainStatus(Status _status) external onlyOwner {
        chainsStatus[_chainId] = _status;
        emit ChainStatusUpdated(_chainId, _status);
    }
}
