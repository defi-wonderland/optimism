// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { L1Block } from "src/L2/L1Block.sol";

// Libraries
import { Constants } from "src/libraries/Constants.sol";
import { LibString } from "@solady/utils/LibString.sol";
import { Storage } from "src/libraries/Storage.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000015
/// @title L1BlockCGT
/// @notice The L1BlockCGT predeploy gives users access to information about the last known L1 block.
///         Values within this contract are updated once per epoch (every L1 block) and can only be
///         set by the "depositor" account, a special system address. Depositor account transactions
///         are created by the protocol whenever we move to a new epoch.
contract L1BlockCGT is L1Block {
    /// @notice Storage slot for the isCustomGasToken flag
    /// @dev bytes32(uint256(keccak256("l1block.isCustomGasToken")) - 1)
    bytes32 private constant IS_CUSTOM_GAS_TOKEN_SLOT =
        0xd2ff82c9b477ff6a09f530b1c627ffb4b0b81e2ae2ba427f824162e8dad020aa;

    /// @notice Storage slot for the gas paying token name
    /// @dev bytes32(uint256(keccak256("l1block.gasPayingTokenName")) - 1)
    bytes32 private constant GAS_PAYING_TOKEN_NAME_SLOT = bytes32(uint256(keccak256("l1block.gasPayingTokenName")) - 1);

    /// @notice Storage slot for the gas paying token symbol
    /// @dev bytes32(uint256(keccak256("l1block.gasPayingTokenSymbol")) - 1)
    bytes32 private constant GAS_PAYING_TOKEN_SYMBOL_SLOT =
        bytes32(uint256(keccak256("l1block.gasPayingTokenSymbol")) - 1);

    /// @custom:semver 1.7.0
    function version() public pure override returns (string memory) {
        return "1.7.0";
    }

    /// @notice Returns whether the gas paying token is custom.
    function isCustomGasToken() public view override returns (bool isCustom_) {
        bytes32 slot = IS_CUSTOM_GAS_TOKEN_SLOT;
        assembly {
            isCustom_ := sload(slot)
        }
    }

    /// @notice Returns the gas paying token, its decimals, name and symbol.
    function gasPayingToken() public pure override returns (address, uint8) {
        revert("L1BlockCGT: deprecated");
    }

    /// @notice Returns the gas paying token name.
    ///         If nothing is set in state, then it means ether is used.
    ///         This function cannot be removed because WETH depends on it.
    function gasPayingTokenName() public view override returns (string memory name_) {
        name_ = isCustomGasToken() ? LibString.fromSmallString(Storage.getBytes32(GAS_PAYING_TOKEN_NAME_SLOT)) : "Ether";
    }

    /// @notice Returns the gas paying token symbol.
    ///         If nothing is set in state, then it means ether is used.
    ///         This function cannot be removed because WETH depends on it.
    function gasPayingTokenSymbol() public view override returns (string memory symbol_) {
        symbol_ =
            isCustomGasToken() ? LibString.fromSmallString(Storage.getBytes32(GAS_PAYING_TOKEN_SYMBOL_SLOT)) : "ETH";
    }

    /// @notice Set chain to use custom gas token (callable by depositor account)
    function setCustomGasToken(bytes32 _gasPayingTokenName, bytes32 _gasPayingTokenSymbol) external {
        require(
            msg.sender == Constants.DEPOSITOR_ACCOUNT,
            "L1Block: only the depositor account can set isCustomGasToken flag"
        );
        require(isCustomGasToken() == false, "L1Block: CustomGasToken already active");

        Storage.setBool(IS_CUSTOM_GAS_TOKEN_SLOT, true);
        Storage.setBytes32(GAS_PAYING_TOKEN_NAME_SLOT, _gasPayingTokenName);
        Storage.setBytes32(GAS_PAYING_TOKEN_SYMBOL_SLOT, _gasPayingTokenSymbol);
    }
}
