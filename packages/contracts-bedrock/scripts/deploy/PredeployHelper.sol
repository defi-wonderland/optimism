// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { console } from "forge-std/console.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";
import { ICreate2Deployer } from "interfaces/preinstalls/ICreate2Deployer.sol";
import { TransactionGeneration } from "scripts/deploy/TransactionGeneration.s.sol";

/// @title PredeployHelper
/// @notice Helper script for managing predeploy configurations during network upgrades.
///         This contract collects all predeploys that need to be deployed, computes their
///         CREATE2 addresses, and handles special cases requiring constructor arguments.
contract PredeployHelper is Script {
    /// @notice Address of the Create2Deployer predeploy.
    address payable immutable CREATE2_DEPLOYER = payable(Preinstalls.Create2Deployer);

    /// @notice Represents a predeploy contract to be deployed during a network upgrade.
    /// @param proxy The address of the proxy contract that will be upgraded.
    /// @param name The name of the predeploy contract.
    /// @param initCode The initialization code (bytecode + constructor args) for deployment.
    /// @param implementation The computed CREATE2 address where the implementation will be deployed.
    struct Predeploy {
        address proxy;
        string name;
        bytes initCode;
        address implementation;
    }

    /// @notice Array storing all predeploys to be deployed.
    Predeploy[] private predeploys;

    /// @notice The fork version being deployed.
    uint256 private fork;

    /// @notice Whether the CrossL2Inbox predeploy should be enabled.
    bool private enableCrossL2Inbox;

    /// @notice Constructs a new PredeployHelper with the specified fork configuration.
    /// @param _fork The fork version to deploy predeploys for.
    /// @param _enableCrossL2Inbox Whether to enable the CrossL2Inbox predeploy.
    constructor(uint256 _fork, bool _enableCrossL2Inbox) {
        fork = _fork;
        enableCrossL2Inbox = _enableCrossL2Inbox;
    }

    /// @notice Collects all predeploys that need to be deployed for the configured fork.
    /// @param _input The input struct containing chain configuration and deployment parameters.
    /// @return Array of Predeploy structs containing deployment information for each predeploy.
    function getPredeploys(TransactionGeneration.Input memory _input) external returns (Predeploy[] memory) {
        uint160 prefix = uint160(0x420) << 148;

        for (uint256 i = 0; i < Predeploys.PREDEPLOY_COUNT; i++) {
            address addr = address(prefix | uint160(i));
            // Skip if not supported or not proxied or needs constructor args
            if (_needsConstructorArgs(addr)) {
                continue;
            }
            _addPredeploy(addr, bytes(""));
        }

        _addSequencerFeeVault(_input);
        _addBaseFeeVault(_input);
        _addL1FeeVault(_input);
        _addOptimismMintableERC721Factory(_input);

        // Copy storage array to memory for return
        Predeploy[] memory result = new Predeploy[](predeploys.length);
        for (uint256 i = 0; i < predeploys.length; i++) {
            result[i] = predeploys[i];
        }
        return result;
    }

    /// @notice Checks if a predeploy requires constructor arguments or special handling.
    /// @param _proxy The address of the proxy contract to check.
    /// @return True if the predeploy requires constructor arguments, false otherwise.
    function _needsConstructorArgs(address _proxy) private pure returns (bool) {
        return _proxy == Predeploys.SEQUENCER_FEE_WALLET || _proxy == Predeploys.BASE_FEE_VAULT
            || _proxy == Predeploys.L1_FEE_VAULT || _proxy == Predeploys.OPTIMISM_MINTABLE_ERC721_FACTORY
            || _proxy == Predeploys.PROXY_ADMIN;
    }

    /// @notice Adds a predeploy to the deployment list with optional constructor arguments.
    /// @param _addr The proxy address of the predeploy contract.
    /// @param _args ABI-encoded constructor arguments (empty bytes for no-arg constructors).
    function _addPredeploy(address _addr, bytes memory _args) internal {
        if (!Predeploys.isSupportedPredeploy(_addr, fork, enableCrossL2Inbox) || Predeploys.notProxied(_addr)) {
            return;
        }
        string memory _name = Predeploys.getName(_addr);
        bytes memory initCode = abi.encodePacked(vm.getCode(_name), _args);
        bytes32 salt = keccak256(abi.encode(_name));
        address implementation = ICreate2Deployer(CREATE2_DEPLOYER).computeAddress(salt, keccak256(initCode));

        predeploys.push(Predeploy({ proxy: _addr, name: _name, initCode: initCode, implementation: implementation }));
    }

    /// @notice Adds the SequencerFeeVault predeploy with its constructor arguments.
    /// @param _input The input struct containing configuration parameters.
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

    /// @notice Adds the BaseFeeVault predeploy with its constructor arguments.
    /// @param _input The input struct containing configuration parameters.
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
