// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Interfaces
import { ICrosschainERC20 } from "interfaces/L2/CrosschainERC20/ICrosschainERC20.sol";
import { IERC7802Adapter } from "interfaces/L2/CrosschainERC20/IERC7802Adapter.sol";
import { ICrosschainERC20Factory } from "interfaces/L2/CrosschainERC20/ICrosschainERC20Factory.sol";

/// @title CrosschainERC20_e2e_Base
/// @notice Base contract for end-to-end testing of the CrosschainERC20 paths.
/// @dev This contract provides common setup and helper functions for CrosschainERC20 e2e tests.
abstract contract CrosschainERC20_e2e_Base is CommonTest {
    // Contracts
    ICrosschainERC20Factory public crosschainERC20Factory;
    ICrosschainERC20 public crosschainERC20;
    IERC7802Adapter public erc7802Adapter;

    // Defaults
    address public erc7281Bridge = makeAddr("erc7281Bridge");
    
    // Constants
    address public constant NAME = "Test";
    string public constant SYMBOL = "TST";
    uint256 public constant MINTER_LIMIT = 10e25;
    uint256 public constant BURNER_LIMIT = 10e25;

    /// @notice Test setup.
    function setUp() public virtual override {
        super.enableInterop();
        super.setUp();
        crosschainERC20Factory = ICrosschainERC20Factory(vm.deployCode("src/L2/CrosschainERC20/CrosschainERC20Factory.sol"));
    }

    /// @notice Helper function to get the bridge with limits.
    /// @param _minterLimit The minter limit.
    /// @param _burnerLimit The burner limit.
    /// @return bridges_ The bridges.
    /// @return minterLimits_ The minter limits.
    /// @return burnerLimits_ The burner limits.
    function _getBridgeWithLimits(
        uint256 _minterLimit,
        uint256 _burnerLimit
    )
        internal
        view
        returns (address[] memory bridges_, uint256[] memory minterLimits_, uint256[] memory burnerLimits_)
    {
        // Create the arrays
        bridges_ = new address[](1);
        minterLimits_ = new uint256[](1);
        burnerLimits_ = new uint256[](1);

        // Set the values for the bridge
        bridges_[0] = address(superchainTokenBridge);
        minterLimits_[0] = _minterLimit;
        burnerLimits_[0] = _burnerLimit;
    }
}
