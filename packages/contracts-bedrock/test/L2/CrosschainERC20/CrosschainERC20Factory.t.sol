// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Target contract
import { CrosschainERC20Factory } from "src/L2/CrosschainERC20/CrosschainERC20Factory.sol";
import { XERC20Lockbox } from "@xERC20/contracts/XERC20Lockbox.sol";

// Interfaces
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract CrosschainERC20FactoryTest is Test {
    CrosschainERC20Factory factory;

    function setUp() public {
        factory = new CrosschainERC20Factory();
    }

    function test_deployCrosschainERC20() public {
        address _crosschainERC20 = factory.deployCrosschainERC20("Test", "TEST");

        assertEq(IERC20Metadata(_crosschainERC20).name(), "Test");
        assertEq(IERC20Metadata(_crosschainERC20).symbol(), "TEST");
        assertEq(Ownable(_crosschainERC20).owner(), address(this));
    }

    function test_deployCrosschainERC20Lockbox() public {
        address _crosschainERC20;
        address _xERC20Lockbox;
        (_crosschainERC20, _xERC20Lockbox) = factory.deployXERC20Lockbox("Test", "TEST", address(makeAddr("ERC20")));

        assertEq(address(XERC20Lockbox(payable(_xERC20Lockbox)).XERC20()), _crosschainERC20);
    }
}
