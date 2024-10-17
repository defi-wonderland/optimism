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
    bytes32 internal constant INITIAL_ONION_LAYER = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;
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

    function testFuzz_hashOnion_succeeds(bytes32 _hashOnion) public {
        // Expect hash onion value to be zero if not set
        assertEq(OpMintableERC20FactoryInterop.hashOnion(), 0);

        // Set hash onion
        vm.prank(Predeploys.PROXY_ADMIN);
        OpMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        // Expect hash onion value to be equal to the set value
        assertEq(OpMintableERC20FactoryInterop.hashOnion(), _hashOnion);
    }

    function testFuzz_verifyAndStore_reverts_whenHashOnionNotSet(
        address[] memory _localTokens,
        address[] memory _remoteTokens,
        bytes32 _startingInnerLayer
    )
        public
    {
        // Act and assert
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.HashOnionNotSet.selector);
        OpMintableERC20FactoryInterop.verifyAndStore(_localTokens, _remoteTokens, _startingInnerLayer);
    }

    function testFuzz_verifyAndStore_reverts_whenOnionAlreadyPeeled(
        address _caller,
        address[] memory _localTokens,
        address[] memory _remoteTokens,
        bytes32 _startingInnerLayer
    )
        public
    {
        // Arrange - set hash onion to initial layer
        vm.prank(Predeploys.PROXY_ADMIN);
        OpMintableERC20FactoryInterop.setHashOnion(INITIAL_ONION_LAYER);

        // Act and assert
        vm.prank(_caller);
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.OnionAlreadyPeeled.selector);
        OpMintableERC20FactoryInterop.verifyAndStore(_localTokens, _remoteTokens, _startingInnerLayer);
    }

    function testFuzz_verifyAndStore_reverts_whenTokensLengthMismatch(
        address _caller,
        address[] memory _localTokens,
        address[] memory _remoteTokens,
        bytes32 _startingInnerLayer,
        bytes32 _hashOnion
    )
        public
    {
        // Arrange
        vm.assume(_hashOnion != INITIAL_ONION_LAYER);
        vm.assume(_localTokens.length != _remoteTokens.length);

        vm.prank(Predeploys.PROXY_ADMIN);
        OpMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        // Act and assert
        vm.prank(_caller);
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.TokensLengthMismatch.selector);
        OpMintableERC20FactoryInterop.verifyAndStore(_localTokens, _remoteTokens, _startingInnerLayer);
    }

    function testFuzz_verifyAndStore_succeeds() public { }

    // TODO: Add test checking that the `verifyAndStore` function doesn't revert with a very large number of tokens due
    // to OOG.

    function testFuzz_verifyAndStore_reverts_whenInvalidComputedHashOnion() public { }

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
}
