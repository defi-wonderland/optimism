// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";
import {
    L1Block_SetL1BlockValues_Test,
    L1Block_SetL1BlockValuesEcotone_Test,
    L1Block_SetL1BlockValuesIsthmus_Test
} from "test/L2/L1Block.t.sol";

// Libraries
import "src/libraries/L1BlockErrors.sol";

/// @title L1Block_CGT_TestInit
/// @notice Reusable test initialization for `L1Block` tests with custom gas token enabled.
contract L1Block_CGT_TestInit is CommonTest {
    address depositor;

    /// @notice Sets up the test suite.
    function setUp() public virtual override {
        super.enableCustomGasToken();
        super.setUp();
        depositor = l1Block.DEPOSITOR_ACCOUNT();
    }
}

/// @title L1Block_CGT_GasPayingTokenName_Test
/// @notice Tests the `gasPayingTokenName` function of the `L1Block` contract with custom gas
///         token enabled.
contract L1Block_CGT_GasPayingTokenName_Test is L1Block_CGT_TestInit {
    /// @notice Tests that the `gasPayingTokenName` function returns the correct token name.
    function test_gasPayingTokenName_succeeds() external view {
        assertEq(liquidityController.gasPayingTokenName(), l1Block.gasPayingTokenName());
    }
}

/// @title L1Block_CGT_GasPayingTokenSymbol_Test
/// @notice Tests the `gasPayingTokenSymbol` function of the `L1Block` contract with custom gas
///         token enabled.
contract L1Block_CGT_GasPayingTokenSymbol_Test is L1Block_CGT_TestInit {
    /// @notice Tests that the `gasPayingTokenSymbol` function returns the correct token symbol.
    function test_gasPayingTokenSymbol_succeeds() external view {
        assertEq(liquidityController.gasPayingTokenSymbol(), l1Block.gasPayingTokenSymbol());
    }
}

/// @title L1Block_CGT_IsCustomGasToken_Test
/// @notice Tests the `isCustomGasToken` function of the `L1Block` contract with custom gas token
///         enabled.
contract L1Block_CGT_IsCustomGasToken_Test is L1Block_CGT_TestInit {
    /// @notice Tests that the `isCustomGasToken` function returns false when no custom gas token
    ///         is used.
    function test_isCustomGasToken_succeeds() external view {
        assertTrue(l1Block.isCustomGasToken());
    }
}

/// @title L1Block_CGT_SetL1BlockValues_Test
/// @notice Tests the `setL1BlockValues` function of the `L1Block` contract with custom gas token
///         enabled.
contract L1Block_CGT_SetL1BlockValues_Test is L1Block_SetL1BlockValues_Test {
    // Override setUp to enable custom gas token
    // Re-use the test from L1Block.t.sol
    function setUp() public override {
        super.enableCustomGasToken();
        super.setUp();
        assertTrue(l1Block.isCustomGasToken());
    }
}

/// @title L1Block_CGT_SetL1BlockValuesEcotone_Test
/// @notice Tests the `setL1BlockValuesEcotone` function of the `L1Block` contract with custom gas
///         token enabled.
contract L1Block_CGT_SetL1BlockValuesEcotone_Test is L1Block_SetL1BlockValuesEcotone_Test {
    // Override setUp to enable custom gas token
    // Re-use the test from L1Block.t.sol
    function setUp() public override {
        super.enableCustomGasToken();
        super.setUp();
        assertTrue(l1Block.isCustomGasToken());
    }
}

/// @title L1Block_CGTSetL1BlockValuesIsthmus_Test
/// @notice Tests the `setL1BlockValuesIsthmus` function of the `L1Block` contract with custom gas
///         token enabled.
contract L1Block_CGT_SetL1BlockValuesIsthmus_Test is L1Block_SetL1BlockValuesIsthmus_Test {
    // Override setUp to enable custom gas token
    // Re-use the test from L1Block.t.sols
    function setUp() public override {
        super.enableCustomGasToken();
        super.setUp();
        assertTrue(l1Block.isCustomGasToken());
    }
}
