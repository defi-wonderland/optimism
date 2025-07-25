// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { WETH98 } from "src/universal/WETH98.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IL1Block } from "interfaces/L2/IL1Block.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

/// @title WETH contract that reads the name and symbol from the L1Block contract.
///        Allows for nice rendering of token names for chains using custom gas token.
///        This contract is not proxied and contains calls to the custom gas token methods.
contract WETH is WETH98, ISemver {
    /// @custom:semver 1.1.2
    string public constant version = "1.1.2";

    /// @notice Returns the name of the wrapped native asset. Will be "Wrapped Ether"
    ///         if the native asset is Ether.
    function name() external view override returns (string memory name_) {
        if (IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).isCustomGasToken()) {
            name_ =
                string.concat("Wrapped ", ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER).gasPayingTokenName());
        } else {
            name_ = "Wrapped Ether";
        }
    }

    /// @notice Returns the symbol of the wrapped native asset. Will be "WETH" if the
    ///         native asset is Ether.
    function symbol() external view override returns (string memory symbol_) {
        if (IL1Block(Predeploys.L1_BLOCK_ATTRIBUTES).isCustomGasToken()) {
            symbol_ = string.concat("W", ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER).gasPayingTokenSymbol());
        } else {
            symbol_ = "WETH";
        }
    }
}
