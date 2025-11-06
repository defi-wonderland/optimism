// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { console } from "forge-std/console.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";
import { ICreate2Deployer } from "interfaces/preinstalls/ICreate2Deployer.sol";
import { TransactionGeneration } from "scripts/deploy/TransactionGeneration.s.sol";

/// @title PredeployHelper
/// @notice Helper script for managing predeploy configurations
contract PredeployHelper is Script {
    /// @notice Address of the Create2Deployer predeploy.
    address payable immutable CREATE2_DEPLOYER = payable(Preinstalls.Create2Deployer);

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
    function getChangedPredeploys(
        uint256 _fork,
        bool _enableCrossL2Inbox,
        TransactionGeneration.Input memory _input
    )
        external
        returns (Predeploy[] memory)
    {
        delete changedPredeploys;
        fork = _fork;
        enableCrossL2Inbox = _enableCrossL2Inbox;

        uint160 prefix = uint160(0x420) << 148;

        for (uint256 i = 0; i < Predeploys.PREDEPLOY_COUNT; i++) {
            address addr = address(prefix | uint160(i));
            // Skip if not supported or not proxied or needs constructor args
            if (
                !Predeploys.isSupportedPredeploy(addr, fork, enableCrossL2Inbox) || Predeploys.notProxied(addr)
                    || _needsConstructorArgs(addr)
            ) {
                continue;
            }
            _addPredeploy(addr, bytes(""));
        }

        _addSequencerFeeVault(_input);
        _addBaseFeeVault(_input);
        _addL1FeeVault(_input);
        _addOptimismMintableERC721Factory(_input);

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
    function _addPredeploy(address _addr, bytes memory _args) internal {
        string memory _name = Predeploys.getName(_addr);
        bytes memory initCode = abi.encodePacked(vm.getCode(_name), _args);
        bytes32 salt = keccak256(abi.encode(_name));
        address implementation = ICreate2Deployer(CREATE2_DEPLOYER).computeAddress(salt, keccak256(initCode));

        // Skip if already deployed
        if (implementation.code.length != 0) {
            return;
        }

        changedPredeploys.push(
            Predeploy({ proxy: _addr, name: _name, initCode: initCode, implementation: implementation })
        );
    }

    /// @notice Adds the SequencerFeeVault predeploy with its constructor arguments
    /// @param _input The input struct containing configuration parameters
    function _addSequencerFeeVault(TransactionGeneration.Input memory _input) internal {
        _addPredeploy(
            Predeploys.SEQUENCER_FEE_WALLET,
            abi.encode(
                _input.sequencerFeeVaultRecipient,
                _input.sequencerFeeVaultMinimumWithdrawalAmount,
                _input.sequencerFeeVaultWithdrawalNetwork
            )
        );
    }

    /// @notice Adds the BaseFeeVault predeploy with its constructor arguments
    /// @param _input The input struct containing configuration parameters
    function _addBaseFeeVault(TransactionGeneration.Input memory _input) internal {
        _addPredeploy(
            Predeploys.BASE_FEE_VAULT,
            abi.encode(
                _input.baseFeeVaultRecipient,
                _input.baseFeeVaultMinimumWithdrawalAmount,
                _input.baseFeeVaultWithdrawalNetwork
            )
        );
    }

    /// @notice Adds the L1FeeVault predeploy with its constructor arguments
    /// @param _input The input struct containing configuration parameters
    function _addL1FeeVault(TransactionGeneration.Input memory _input) internal {
        _addPredeploy(
            Predeploys.L1_FEE_VAULT,
            abi.encode(
                _input.l1FeeVaultRecipient, _input.l1FeeVaultMinimumWithdrawalAmount, _input.l1FeeVaultWithdrawalNetwork
            )
        );
    }

    /// @notice Adds the OptimismMintableERC721Factory predeploy with its constructor arguments
    /// @param _input The input struct containing configuration parameters
    function _addOptimismMintableERC721Factory(TransactionGeneration.Input memory _input) internal {
        _addPredeploy(
            Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY, abi.encode(_input.l1ERC721BridgeProxy, _input.l2ChainID)
        );
    }
}
