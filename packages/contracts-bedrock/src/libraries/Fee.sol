// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// Libraries
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/// @title Fee
/// @notice A library for calculating fees on any 18 decimals asset.
library Fee {
    using FixedPointMathLib for uint256;

    /// @notice Calculates the fee for the given amount.
    /// @param amount The amount to calculate the fee for.
    /// @param maxPermittedAmount The maximum permitted amount.
    /// @param curveExponent The curve exponent.
    /// @param maxFeePercentage The maximum fee percentage.
    /// @param baseFee The base fee.
    /// @return fee The fee for the given amount.
    function calculateFee(
        uint256 amount,
        uint256 maxPermittedAmount,
        uint256 curveExponent,
        uint256 maxFeePercentage,
        uint256 baseFee
    )
        internal
        pure
        returns (uint256)
    {
        // Normalize amount to [0, 1] in 18 decimals
        uint256 normalized = amount.divWad(maxPermittedAmount);

        // Raise to the exponent (e.g., x^3)
        uint256 powered = normalized.rpow(curveExponent, 1e18);

        // Calculate the percentage of the amount
        uint256 percentageFee = amount.mulWad(powered.mulWad(maxFeePercentage));

        // Add base fee
        return percentageFee + baseFee;
    }
}
