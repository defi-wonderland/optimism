// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { Bridge_Initializer } from "test/setup/Bridge_Initializer.sol";

// Contracts
import { OptimismMintableERC20FactoryInterop } from "src/universal/OptimismMintableERC20FactoryInterop.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { IOptimismMintableERC20FactoryInterop } from "src/universal/interfaces/IOptimismMintableERC20FactoryInterop.sol";

contract OptimismMintableTokenFactoryInterop_Test is Bridge_Initializer {
    bytes32 internal constant INITIAL_ONION_LAYER = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;
    IOptimismMintableERC20FactoryInterop opMintableERC20FactoryInterop;

    function setUp() public virtual override {
        super.enableInterop();
        super.setUp();

        opMintableERC20FactoryInterop = IOptimismMintableERC20FactoryInterop(address(l2OptimismMintableERC20Factory));
    }

    /// @notice Helper function to setup a mock and expect a call to it.
    function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
        vm.mockCall(_receiver, _calldata, _returned);
        vm.expectCall(_receiver, _calldata);
    }

    /// @notice Helper function to calculate the hash onion by the given arrays of local and remote tokens.
    function _calculateHashOnion(
        address[] memory _localTokens,
        address[] memory _remoteTokens,
        bytes32 _startingInnerLayer
    )
        internal
        pure
        returns (bytes32 _hashOnion)
    {
        bytes32 _innerLayer = _startingInnerLayer;
        for (uint256 _i; _i < _localTokens.length; _i++) {
            _innerLayer =
                keccak256(abi.encodePacked(_innerLayer, abi.encodePacked(_localTokens[_i], _remoteTokens[_i])));
        }
        _hashOnion = _innerLayer;
    }

    /// @notice Helper function to set a different remote token address per local token address.
    function _setRemoteTokensArray(address[] memory _localTokens)
        internal
        pure
        returns (address[] memory _remoteTokens)
    {
        _remoteTokens = new address[](_localTokens.length);
        for (uint256 _i; _i < _localTokens.length; _i++) {
            _remoteTokens[_i] = address(uint160(uint256(keccak256(abi.encode(_localTokens[_i])))));
        }
    }

    /// @notice Test that the `hashOnion` getter returns the expected value.
    /// @notice Asumming `setHashOnion` is working as expected - it's be tested in other tests.
    function testFuzz_hashOnion_succeeds(bytes32 _hashOnion) public {
        // Expect hash onion value to be zero if not set
        assertEq(opMintableERC20FactoryInterop.hashOnion(), 0);

        // Set hash onion
        vm.prank(Predeploys.PROXY_ADMIN);
        opMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        // Expect hash onion value to be equal to the set value
        assertEq(opMintableERC20FactoryInterop.hashOnion(), _hashOnion);
    }

    /// @notice Test that `verifyAndStore` reverts when the hash onion is not set.
    function testFuzz_verifyAndStore_reverts_whenHashOnionNotSet(
        address[] memory _localTokens,
        address[] memory _remoteTokens,
        bytes32 _startingInnerLayer
    )
        public
    {
        /* Act and Assert */
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.HashOnionNotSet.selector);
        opMintableERC20FactoryInterop.verifyAndStore(_localTokens, _remoteTokens, _startingInnerLayer);
    }

    /// @notice Test that `verifyAndStore` reverts when the hash onion is already peeled.
    function testFuzz_verifyAndStore_reverts_whenOnionAlreadyPeeled(
        address _caller,
        address[] memory _localTokens,
        address[] memory _remoteTokens,
        bytes32 _startingInnerLayer
    )
        public
    {
        /* Arrange - set hash onion to initial layer */
        vm.prank(Predeploys.PROXY_ADMIN);
        opMintableERC20FactoryInterop.setHashOnion(INITIAL_ONION_LAYER);

        /* Act and Assert */
        vm.prank(_caller);
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.OnionAlreadyPeeled.selector);
        opMintableERC20FactoryInterop.verifyAndStore(_localTokens, _remoteTokens, _startingInnerLayer);
    }

    /// @notice Test that `verifyAndStore` reverts when the tokens length mismatch.
    function testFuzz_verifyAndStore_reverts_whenTokensLengthMismatch(
        address _caller,
        address[] memory _localTokens,
        address[] memory _remoteTokens,
        bytes32 _startingInnerLayer,
        bytes32 _hashOnion
    )
        public
    {
        /* Arrange */
        vm.assume(_hashOnion != INITIAL_ONION_LAYER);
        vm.assume(_localTokens.length != _remoteTokens.length);

        vm.prank(Predeploys.PROXY_ADMIN);
        opMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        /* Act and Assert */
        vm.prank(_caller);
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.TokensLengthMismatch.selector);
        opMintableERC20FactoryInterop.verifyAndStore(_localTokens, _remoteTokens, _startingInnerLayer);
    }

    /// @notice Test that `verifyAndStore` succeeds when the hash onion is fully unpeeled at once with valid inputs.
    function testFuzz_verifyAndStore_succeeds_fullOnionUnpeeledAtOnce(address[] memory _localTokens) public {
        vm.assume(_localTokens.length > 0);

        /* Arrange */
        address[] memory _remoteTokens = _setRemoteTokensArray(_localTokens);

        // Calculate hash onion
        bytes32 _hashOnion = _calculateHashOnion(_localTokens, _remoteTokens, INITIAL_ONION_LAYER);

        // Set hash onion
        vm.prank(Predeploys.PROXY_ADMIN);
        opMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        /* Act */
        opMintableERC20FactoryInterop.verifyAndStore(_localTokens, _remoteTokens, INITIAL_ONION_LAYER);
    }

    /// @notice Test that `verifyAndStore` succeeds when the hash onion is fully unpeeled in 2 steps with valid inputs.
    function testFuzz_verifyAndStore_succeeds_multipleUnpeels(address[] memory _localTokensFirstHalf) public {
        /* Arrange */
        vm.assume(_localTokensFirstHalf.length > 0);

        address[] memory _remoteTokensFirstHalf = new address[](_localTokensFirstHalf.length);
        address[] memory _localTokensSecondHalf = new address[](_localTokensFirstHalf.length);
        address[] memory _remoteTokensSecondHalf = new address[](_localTokensFirstHalf.length);

        // Set a remote token address per local token address
        // Not using the `_setRemoteTokensArray` helper function so both arrays items are updated on the same loop.
        // This logic was only used here so no need to create a helper function for it.
        for (uint256 _i; _i < _localTokensFirstHalf.length; _i++) {
            _remoteTokensFirstHalf[_i] = address(uint160(uint256(keccak256(abi.encode(_localTokensFirstHalf[_i])))));
            _localTokensSecondHalf[_i] = address(uint160(uint256(keccak256(abi.encode(_remoteTokensFirstHalf[_i])))));
            _remoteTokensSecondHalf[_i] = address(uint160(uint256(keccak256(abi.encode(_localTokensSecondHalf[_i])))));
        }

        // Calculate the half inner layer
        bytes32 _halfInnerLayer =
            _calculateHashOnion(_localTokensFirstHalf, _remoteTokensFirstHalf, INITIAL_ONION_LAYER);

        // Calculate the full hash onion, starting from the half inner layer and computing the second half
        bytes32 _hashOnion = _calculateHashOnion(_localTokensSecondHalf, _remoteTokensSecondHalf, _halfInnerLayer);

        // Set hash onion
        vm.prank(Predeploys.PROXY_ADMIN);
        opMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        /* Act */
        // Unpeel the second half of the hash onion
        opMintableERC20FactoryInterop.verifyAndStore(_localTokensSecondHalf, _remoteTokensSecondHalf, _halfInnerLayer);

        // Unpeel the remaining first half of the hash onion
        opMintableERC20FactoryInterop.verifyAndStore(_localTokensFirstHalf, _remoteTokensFirstHalf, INITIAL_ONION_LAYER);
    }

    /// @notice Test that `verifyAndStore` reverts when the computed hash onion is invalid.
    ///         Testing the cases where the computed hash onion is invalid due to:
    ///         - Invalid local token address
    ///         - Invalid remote token address
    ///         - Empty arrays
    function testFuzz_verifyAndStore_reverts_whenInvalidComputedHashOnion(address[] memory _localTokens) public {
        vm.assume(_localTokens.length > 0);

        /* Arrange */
        address[] memory _remoteTokens = _setRemoteTokensArray(_localTokens);

        // Calculate hash onion
        bytes32 _hashOnion = _calculateHashOnion(_localTokens, _remoteTokens, INITIAL_ONION_LAYER);

        // Set hash onion
        vm.prank(Predeploys.PROXY_ADMIN);
        opMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        // Modify the first local token address to make the computed hash onion invalid
        address[] memory _badLocalTokens = new address[](_localTokens.length);
        _badLocalTokens = _localTokens;
        _badLocalTokens[0] = address(uint160(uint256(keccak256(abi.encode(_localTokens[0])))));

        /* Act and Assert */
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.InvalidHashOnion.selector);
        opMintableERC20FactoryInterop.verifyAndStore(_badLocalTokens, _remoteTokens, INITIAL_ONION_LAYER);

        // Expect to revert when remote tokens have invalid values as well
        address[] memory _badRemoteTokens = new address[](_remoteTokens.length);
        _badRemoteTokens = _remoteTokens;
        _badRemoteTokens[0] = address(uint160(uint256(keccak256(abi.encode(_remoteTokens[0])))));

        vm.expectRevert(IOptimismMintableERC20FactoryInterop.InvalidHashOnion.selector);
        opMintableERC20FactoryInterop.verifyAndStore(_localTokens, _badRemoteTokens, INITIAL_ONION_LAYER);

        // Expect revert if sending empty arrays
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.InvalidHashOnion.selector);
        opMintableERC20FactoryInterop.verifyAndStore(new address[](0), new address[](0), INITIAL_ONION_LAYER);
    }

    /// @notice Test that `verifyAndStore` doesn't revert due OOG when the input tokens array length is very long.
    function test_verifyAndStore_succeeds_withLongTokensArray() public {
        uint256 _arraysLength = 100_000;
        address[] memory _localTokens = new address[](_arraysLength);
        address[] memory _remoteTokens = new address[](_arraysLength);
        // Not using the `_setRemoteTokensArray` helper function so both arrays items are updated on the same loop.
        // This logic was only used here so no need to create a helper function for it.
        for (uint256 _i; _i < _arraysLength; _i++) {
            _localTokens[_i] = address(uint160(uint256(keccak256(abi.encode(_i)))));
            _remoteTokens[_i] = address(uint160(uint256(keccak256(abi.encode(_localTokens[_i])))));
        }

        // Calculate hash onion
        bytes32 _innerLayer = INITIAL_ONION_LAYER;
        for (uint256 _i; _i < _arraysLength; _i++) {
            _innerLayer =
                keccak256(abi.encodePacked(_innerLayer, abi.encodePacked(_localTokens[_i], _remoteTokens[_i])));
        }

        // Set hash onion
        vm.prank(Predeploys.PROXY_ADMIN);
        opMintableERC20FactoryInterop.setHashOnion(_innerLayer);

        /* Act */
        (bool _success,) = address(opMintableERC20FactoryInterop).call(
            abi.encodeWithSelector(
                opMintableERC20FactoryInterop.verifyAndStore.selector, _localTokens, _remoteTokens, INITIAL_ONION_LAYER
            )
        );

        // Assert
        assertTrue(_success);
    }

    /// @notice Test that `setHashOnion` reverts when the caller is not the ProxyAdmin.
    function testFuzz_setHashOnion_reverts_whenCallerNotProxyAdmin(address _caller, bytes32 _hashOnion) public {
        /* Arrange */
        vm.assume(_caller != Predeploys.PROXY_ADMIN);
        vm.startPrank(_caller);

        /* Act and Assert */
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.Unauthorized.selector);
        opMintableERC20FactoryInterop.setHashOnion(_hashOnion);
    }

    /// @notice Test that `setHashOnion` reverts when the hash onion is already set.
    function testFuzz_setHashOnion_reverts_whenHashOnionAlreadySet(bytes32 _hashOnion) public {
        /* Arrange */
        vm.startPrank(Predeploys.PROXY_ADMIN);
        opMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        /* Act and Assert */
        vm.expectRevert(IOptimismMintableERC20FactoryInterop.HashOnionAlreadySet.selector);
        opMintableERC20FactoryInterop.setHashOnion(_hashOnion);
    }

    /// @notice Test that `setHashOnion` succeeds when the caller is the ProxyAdmin and the hash onion is not set.
    function testFuzz_setHashOnion_succeeds(bytes32 _hashOnion) public {
        /* Arrange */
        vm.prank(Predeploys.PROXY_ADMIN);

        /* Act */
        opMintableERC20FactoryInterop.setHashOnion(_hashOnion);

        // Assert
        assertEq(opMintableERC20FactoryInterop.hashOnion(), _hashOnion);
    }
}
