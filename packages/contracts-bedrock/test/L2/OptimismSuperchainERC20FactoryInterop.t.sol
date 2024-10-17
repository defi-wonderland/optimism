// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { Bridge_Initializer } from "test/setup/Bridge_Initializer.sol";

// Contracts
import { OptimismMintableERC20FactoryInterop } from "src/universal/OptimismMintableERC20FactoryInterop.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { IOptimismMintableERC20FactoryInterop } from "src/universal/interfaces/IOptimismMintableERC20FactoryInterop.sol";

// TODO: missing natspec over functions

contract OptimismMintableTokenFactoryInterop_Test is Bridge_Initializer {
    IOptimismMintableERC20FactoryInterop OpMintableERC20FactoryInterop;

    function setUp() public virtual override {
        super.enableInterop();
        super.setUp();

        OpMintableERC20FactoryInterop = IOptimismMintableERC20FactoryInterop(address(l2OptimismMintableERC20Factory));
    }

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    function testFuzz_setHashOnion_reverts_whenCallerNotProxyAdmin(address _caller, bytes32 _hashOnion) public {
        // Arrange
        vm.assume(_caller != Predeploys.PROXY_ADMIN);
        vm.startPrank(_caller);

        // Act and assert
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.Unauthorized.selector);
        OpMintableERC20FactoryInterop.setHashOnion(_hashOnion);
    }

    function testFuzz_setHashOnion_reverts_whenHashOnionAlreadySet(bytes32 _hashOnion) public {
        // Arrange
        vm.startPrank(Predeploys.PROXY_ADMIN);
        OpMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        // Act and assert
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.HashOnionAlreadySet.selector);
        OpMintableERC20FactoryInterop.setHashOnion(_hashOnion);
    }

    function testFuzz_setHashOnion_succeeds(bytes32 _hashOnion) public {
        // Arrange
        vm.prank(Predeploys.PROXY_ADMIN);

        // Act
        OpMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        // Assert
        assertEq(OpMintableERC20FactoryInterop.hashOnion(), _hashOnion);
    }

    function testFuzz_hashOnion_succeeds(bytes32 _hashOnion) public {
        // Expect hash onion value to be zero if not set
        assertEq(OpMintableERC20FactoryInterop.hashOnion(), 0);

        // Set hash onion
        vm.prank(Predeploys.PROXY_ADMIN);
        OpMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        // Expect hash onion value to be equal to the set value
        assertEq(OpMintableERC20FactoryInterop.hashOnion(), _hashOnion);
    }
}
