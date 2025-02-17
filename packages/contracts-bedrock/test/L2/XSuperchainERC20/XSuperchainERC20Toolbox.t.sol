// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Target contract
import { XSuperchainERC20Toolbox } from "src/L2/XSuperchainERC20/XSuperchainERC20Toolbox.sol";
import { SuperchainXERC20Lockbox } from "src/L2/XSuperchainERC20/SuperchainXERC20Lockbox.sol";
// Interfaces
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract XSuperchainERC20ToolboxTest is Test {
    XSuperchainERC20Toolbox toolbox;

    function setUp() public {
        toolbox = new XSuperchainERC20Toolbox();
    }

    function test_deployXSuperchainERC20() public {
        address _xSuperchainERC20 = toolbox.deployXSuperchainERC20("Test", "TEST");

        assertEq(IERC20Metadata(_xSuperchainERC20).name(), "Test");
        assertEq(IERC20Metadata(_xSuperchainERC20).symbol(), "TEST");
        assertEq(Ownable(_xSuperchainERC20).owner(), address(this));
    }

    function test_deployXSuperchainERC20Lockbox() public {
        address _XERC20 = makeAddr("XERC20");
        (address _xSuperchainERC20, address _xSuperchainERC20Lockbox) =
            toolbox.deploySuperchainXERC20Lockbox("Test", "TEST", _XERC20);

        assertEq(address(SuperchainXERC20Lockbox(_xSuperchainERC20Lockbox).XSUPERCHAINERC20()), _xSuperchainERC20);
    }
}
