// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Base, UnitDeploy, XERC20FactoryForTest } from '@xERC20/test/unit/XERC20Factory.t.sol';
import { XSuperchainERC20Factory } from 'src/L2/XSuperchainERC20Factory.sol';
import {CREATE3} from 'isolmate/utils/CREATE3.sol';

contract XSuperchainERC20FactoryForTest is XSuperchainERC20Factory {
  function getDeployed(bytes32 _salt) public view returns (address _precomputedAddress) {
    _precomputedAddress = CREATE3.getDeployed(_salt);
  }
}

/// @title XSuperchainERC20FactoryTest
/// @notice Contract for testing the XSuperchainERC20Factory contract.
contract XSuperchainERC20FactoryTest is UnitDeploy {
    XSuperchainERC20FactoryForTest public _xSuperchainERC20Factory;

    /// @notice Sets up the test suite.
    /// @dev We need to override the `setUp` function to use the `XSuperchainERC20Factory` contract
    /// instead of the `xERC20` and `SuperchainERC20` contracts.
    function setUp() public override(Base) {
        _xSuperchainERC20Factory = new XSuperchainERC20FactoryForTest();
        _xerc20Factory = XERC20FactoryForTest(_xSuperchainERC20Factory);
    }
}
