// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { L1Block } from "src/L2/L1Block.sol";

// Libraries
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { GasPayingToken } from "src/libraries/GasPayingToken.sol";
import { StaticConfig } from "src/libraries/StaticConfig.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import {
    NotDepositor,
    NotCrossL2Inbox,
    DependencySetSizeTooLarge,
    AlreadyDependency
} from "src/libraries/L1BlockErrors.sol";
import { Unauthorized } from "src/libraries/errors/CommonErrors.sol";

/// @notice Enum representing different types of configurations that can be set on L1BlockInterop.
/// @custom:value SET_GAS_PAYING_TOKEN  Represents the config type for setting the gas paying token.
enum ConfigType {
    SET_GAS_PAYING_TOKEN
}

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000015
/// @title L1BlockInterop
/// @notice Interop extenstions of L1Block.
contract L1BlockInterop is L1Block {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice Event emitted when a new dependency is added to the interop dependency set.
    event DependencyAdded(uint256 indexed chainId);

    /// @notice The interop dependency set, containing the chain IDs in it.
    EnumerableSet.UintSet dependencySet;

    /// @notice Storage slot that the isDeposit is stored at.
    ///         This is a custom slot that is not part of the standard storage layout.
    /// keccak256(abi.encode(uint256(keccak256("l1Block.identifier.isDeposit")) - 1)) & ~bytes32(uint256(0xff))
    uint256 internal constant IS_DEPOSIT_SLOT = 0x921bd3a089295c6e5540e8fba8195448d253efd6f2e3e495b499b627dc36a300;

    /// @custom:semver +interop-beta.4
    function version() public pure override returns (string memory) {
        return string.concat(super.version(), "+interop-beta.4");
    }

    /// @notice Returns whether the call was triggered from a a deposit or not.
    /// @notice This function is only callable by the CrossL2Inbox contract.
    function isDeposit() external view returns (bool isDeposit_) {
        if (msg.sender != Predeploys.CROSS_L2_INBOX) revert NotCrossL2Inbox();
        assembly {
            isDeposit_ := sload(IS_DEPOSIT_SLOT)
        }
    }

    /// @notice Returns true if a chain ID is in the interop dependency set and false otherwise.
    ///         The chain's chain ID is always considered to be in the dependency set.
    /// @param _chainId The chain ID to check.
    /// @return True if the chain ID to check is in the interop dependency set. False otherwise.
    function isInDependencySet(uint256 _chainId) public view returns (bool) {
        return _chainId == block.chainid || dependencySet.contains(_chainId);
    }

    /// @notice Returns the size of the interop dependency set.
    /// @return The size of the interop dependency set.
    function dependencySetSize() external view returns (uint8) {
        return uint8(dependencySet.length());
    }

    /// @notice Updates the `isDeposit` flag and sets the L1 block values for an Interop upgraded chain.
    ///         It updates the L1 block values through the `setL1BlockValuesEcotone` function.
    ///         It forwards the calldata to the internally-used `setL1BlockValuesEcotone` function.
    function setL1BlockValuesInterop() external {
        // Set the isDeposit flag to true.
        assembly {
            sstore(IS_DEPOSIT_SLOT, 1)
        }

        _setL1BlockValuesEcotone();
    }

    /// @notice Resets the isDeposit flag.
    ///         Should only be called by the depositor account after the deposits are complete.
    function depositsComplete() external {
        if (msg.sender != DEPOSITOR_ACCOUNT()) revert NotDepositor();

        // Set the isDeposit flag to false.
        assembly {
            sstore(IS_DEPOSIT_SLOT, 0)
        }
    }

    /// @notice Sets static configuration options for the L2 system. Can only be called by the special
    ///         depositor account.
    /// @param _type  The type of configuration to set.
    /// @param _value The encoded value with which to set the configuration.
    function setConfig(ConfigType _type, bytes calldata _value) external {
        if (msg.sender != DEPOSITOR_ACCOUNT()) revert NotDepositor();

        if (_type == ConfigType.SET_GAS_PAYING_TOKEN) {
            _setGasPayingToken(_value);
        }
    }

    /// @notice Internal method to set the gas paying token.
    /// @param _value The encoded value with which to set the gas paying token.
    function _setGasPayingToken(bytes calldata _value) internal {
        (address token, uint8 decimals, bytes32 name, bytes32 symbol) = StaticConfig.decodeSetGasPayingToken(_value);

        GasPayingToken.set({ _token: token, _decimals: decimals, _name: name, _symbol: symbol });

        emit GasPayingTokenSet({ token: token, decimals: decimals, name: name, symbol: symbol });
    }

    /// @notice Add a dependency to the interop dependency set.
    /// @param _chainId The chain ID to add to the dependency set.
    function addDependency(uint256 _chainId) external {
        if (msg.sender != Predeploys.UPGRADE_HANDLER) revert Unauthorized();

        if (dependencySet.length() == type(uint8).max) revert DependencySetSizeTooLarge();

        if (_chainId == block.chainid || !dependencySet.add(_chainId)) revert AlreadyDependency();

        emit DependencyAdded(_chainId);
    }
}
