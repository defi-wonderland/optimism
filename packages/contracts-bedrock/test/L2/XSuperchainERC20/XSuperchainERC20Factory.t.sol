// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Target contract
import { XSuperchainERC20Factory } from "src/L2/XSuperchainERC20/XSuperchainERC20Factory.sol";
import { XERC20Lockbox } from "@xERC20/contracts/XERC20Lockbox.sol";

// Interfaces
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract XSuperchainERC20FactoryTest is Test {
    XSuperchainERC20Factory factory;

    function setUp() public {
        factory = new XSuperchainERC20Factory();
    }

    function test_deployXSuperchainERC20() public {
        address _xSuperchainERC20 = factory.deployXSuperchainERC20("Test", "TEST");

        assertEq(IERC20Metadata(_xSuperchainERC20).name(), "Test");
        assertEq(IERC20Metadata(_xSuperchainERC20).symbol(), "TEST");
        assertEq(Ownable(_xSuperchainERC20).owner(), address(this));
    }

    function test_deploySuperchainXERC20Lockbox() public {
        address _xSuperchainERC20;
        address _xERC20Lockbox;
        (_xSuperchainERC20, _xERC20Lockbox) = factory.deployXERC20Lockbox("Test", "TEST", address(makeAddr("ERC20")));

        assertEq(address(XERC20Lockbox(payable(_xERC20Lockbox)).XERC20()), _xSuperchainERC20);
    }
}
