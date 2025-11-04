// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { console } from "forge-std/console.sol";

interface ICreate2Deployer {
    function computeAddress(bytes32 salt, bytes32 codeHash) external view returns (address);
}

/// @title PredeployHelper
/// @notice Helper script for managing predeploy configurations
contract PredeployHelper is Script {
    address constant CREATE2_DEPLOYER = 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2;

    struct Predeploy {
        address proxy;
        string name;
        bytes initCode;
        address implementation;
    }

    Predeploy[] private changedPredeploys;
    uint256 private fork;
    bool private enableCrossL2Inbox;

    /// @notice Get all changed predeploys
    /// @param _fork Fork version
    /// @param _enableCrossL2Inbox Whether to enable CrossL2Inbox
    /// @return Array of changed predeploys
    function getChangedPredeploys(uint256 _fork, bool _enableCrossL2Inbox) external returns (Predeploy[] memory) {
        delete changedPredeploys;
        fork = _fork;
        enableCrossL2Inbox = _enableCrossL2Inbox;

        // Iterate through all predeploys (skip ones that need constructor args)
        address[] memory allPredeploys = Predeploys.getPredeploys();
        for (uint256 i = 0; i < allPredeploys.length; i++) {
            // Skip predeploys that need constructor arguments - they'll be added separately
            if (_needsConstructorArgs(allPredeploys[i])) {
                continue;
            }
            addPredeploy(allPredeploys[i], bytes(""));
        }

        // Copy storage array to memory for return
        Predeploy[] memory result = new Predeploy[](changedPredeploys.length);
        for (uint256 i = 0; i < changedPredeploys.length; i++) {
            result[i] = changedPredeploys[i];
        }
        return result;
    }

    /// @notice Check if a predeploy needs constructor arguments or special handling
    function _needsConstructorArgs(address _proxy) private pure returns (bool) {
        return _proxy == Predeploys.SEQUENCER_FEE_WALLET || _proxy == Predeploys.BASE_FEE_VAULT
            || _proxy == Predeploys.L1_FEE_VAULT || _proxy == Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY
            || _proxy == Predeploys.PROXY_ADMIN;
    }

    /// @notice Add a predeploy with constructor args
    function addPredeploy(address _proxy, bytes memory _args) public {
        // Skip if not supported
        if (!Predeploys.isSupportedPredeploy(_proxy, fork, enableCrossL2Inbox)) {
            return;
        }
        // Skip if not proxied
        if (Predeploys.notProxied(_proxy)) {
            return;
        }

        string memory _name = Predeploys.getName(_proxy);
        bytes memory initCode = abi.encodePacked(vm.getCode(_name), _args);
        bytes32 salt = keccak256(abi.encode(_name));
        address implementation = ICreate2Deployer(CREATE2_DEPLOYER).computeAddress(salt, keccak256(initCode));

        // Skip if already deployed
        if (implementation.code.length != 0) {
            return;
        }

        changedPredeploys.push(
            Predeploy({ proxy: _proxy, name: _name, initCode: initCode, implementation: implementation })
        );
    }

    /// @notice Get the final list of changed predeploys
    function finalizeChangedPredeploys() external view returns (Predeploy[] memory) {
        Predeploy[] memory result = new Predeploy[](changedPredeploys.length);
        for (uint256 i = 0; i < changedPredeploys.length; i++) {
            result[i] = changedPredeploys[i];
        }
        return result;
    }
}
