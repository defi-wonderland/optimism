// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Target contract is imported by the `Bridge_Initializer`
import { Bridge_Initializer } from "test/setup/Bridge_Initializer.sol";
import { console2 } from "forge-std/console2.sol";

// Target contract dependencies
import {
    L2StandardBridgeInterop,
    InvalidDecimals,
    InvalidLegacyAddress,
    InvalidSuperchainAddress,
    InvalidTokenPair,
    IOptimismERC20Factory,
    MintableAndBurnable
} from "src/L2/L2StandardBridgeInterop.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IOptimismMintableERC20 } from "src/universal/IOptimismMintableERC20.sol";

// TODO: Replace Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY with optimismSuperchainERC20Factory
import { Predeploys } from "src/libraries/Predeploys.sol";

contract L2StandardBridgeInterop_Test is Bridge_Initializer {
    /// @notice Emitted when a conversion is made.
    event Converted(address indexed from, address indexed to, address indexed caller, uint256 amount);

    /// @notice Mock ERC20 decimals
    function _mockDecimals(address _token, uint8 _decimals) internal {
        vm.mockCall(_token, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(_decimals));
    }

    /// @notice Mock ERC165 interface
    function _mockInterface(address _token, bytes4 _interfaceId, bool _supported) internal {
        vm.mockCall(
            _token, abi.encodeWithSelector(IERC165.supportsInterface.selector, _interfaceId), abi.encode(_supported)
        );
    }

    /// @notice Mock factory deployment
    function _mockDeployments(address _factory, address _token, address _deployed) internal {
        vm.mockCall(
            _factory, abi.encodeWithSelector(IOptimismERC20Factory.deployments.selector, _token), abi.encode(_deployed)
        );
    }
}

/// @notice Test when converting from a legacy token to a SuperchainERC20 token
contract L2StandardBridgeInterop_LegacyToSuper_Test is L2StandardBridgeInterop_Test {
    function _setUpLegacyToSuper(address _from, address _to) internal {
        // Assume
        vm.assume(_from != console2.CONSOLE_ADDRESS);
        vm.assume(_to != console2.CONSOLE_ADDRESS);

        // Mock same decimals
        _mockDecimals(_from, 18);
        _mockDecimals(_to, 18);

        // Mock `_from` to be a legacy address
        _mockInterface(_from, type(IERC165).interfaceId, true);
        _mockInterface(_from, type(IOptimismMintableERC20).interfaceId, true);
    }

    /// @notice Test that the `convert` function with different decimals reverts
    function testFuzz_convert_differenteDecimals_reverts(
        address _from,
        uint8 _decimalsFrom,
        address _to,
        uint8 _decimalsTo,
        uint256 _amount
    )
        public
    {
        // Assume
        vm.assume(_from != console2.CONSOLE_ADDRESS);
        vm.assume(_to != console2.CONSOLE_ADDRESS);
        vm.assume(_decimalsFrom != _decimalsTo);
        vm.assume(_from != _to);

        // Arrange
        // Mock the tokens to have different decimals
        _mockDecimals(_from, _decimalsFrom);
        _mockDecimals(_to, _decimalsTo);

        // Expect the revert with `InvalidDecimals` selector
        vm.expectRevert(InvalidDecimals.selector);

        // Act
        l2StandardBridge.convert(_from, _to, _amount);
    }

    /// @notice Test that the `convert` function with an invalid legacy address reverts
    function testFuzz_convert_invalidLegacyAddress_reverts(address _from, address _to, uint256 _amount) public {
        // Arrange
        _setUpLegacyToSuper(_from, _to);

        // Mock the legacy factory to return address(0)
        _mockDeployments(address(l2OptimismMintableERC20Factory), _from, address(0));

        // Expect the revert with `InvalidLegacyAddress` selector
        vm.expectRevert(InvalidLegacyAddress.selector);

        // Act
        l2StandardBridge.convert(_from, _to, _amount);
    }

    /// @notice Test that the `convert` function with an invalid superchain address reverts
    function testFuzz_convert_invalidSuperchainAddress_reverts(
        address _from,
        address _to,
        uint256 _amount,
        address _remoteToken
    )
        public
    {
        // Assume
        vm.assume(_remoteToken != address(0));

        // Arrange
        _setUpLegacyToSuper(_from, _to);

        // Mock the legacy factory to return `_remoteToken`
        _mockDeployments(address(l2OptimismMintableERC20Factory), _from, _remoteToken);

        // Mock the superchain factory to return address(0)
        _mockDeployments(Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY, _to, address(0));

        // Expect the revert with `InvalidSuperchainAddress` selector
        vm.expectRevert(InvalidSuperchainAddress.selector);

        // Act
        l2StandardBridge.convert(_from, _to, _amount);
    }

    /// @notice Test that the `convert` function with different remote tokens reverts
    function testFuzz_convert_differentRemoteAddresses_reverts(
        address _from,
        address _to,
        uint256 _amount,
        address _fromRemoteToken,
        address _toRemoteToken
    )
        public
    {
        // Assume
        vm.assume(_fromRemoteToken != address(0));
        vm.assume(_toRemoteToken != address(0));
        vm.assume(_fromRemoteToken != _toRemoteToken);

        // Arrange
        _setUpLegacyToSuper(_from, _to);

        // Mock the legacy factory to return `_fromRemoteToken`
        _mockDeployments(address(l2OptimismMintableERC20Factory), _from, _fromRemoteToken);

        // Mock the superchain factory to return `_toRemoteToken`
        _mockDeployments(Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY, _to, _toRemoteToken);

        // Expect the revert with `InvalidTokenPair` selector
        vm.expectRevert(InvalidTokenPair.selector);

        // Act
        l2StandardBridge.convert(_from, _to, _amount);
    }

    /// @notice Test that the `convert` function succeeds
    function testFuzz_convert_succeeds(
        address _caller,
        address _from,
        address _to,
        uint256 _amount,
        address _remoteToken
    )
        public
    {
        // Assume
        vm.assume(_remoteToken != address(0));

        // Arrange
        _setUpLegacyToSuper(_from, _to);

        // Mock the legacy and superchain factory to return `_remoteToken`
        _mockDeployments(address(l2OptimismMintableERC20Factory), _from, _remoteToken);
        _mockDeployments(Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY, _to, _remoteToken);

        // Mock the `burn` and `mint` functions
        vm.mockCall(_from, abi.encodeWithSelector(MintableAndBurnable.burn.selector, _caller, _amount), abi.encode());
        vm.mockCall(_to, abi.encodeWithSelector(MintableAndBurnable.mint.selector, _caller, _amount), abi.encode());

        // Expect the `Converted` event to be emitted
        vm.expectEmit(true, true, true, true, address(l2StandardBridge));
        emit Converted(_from, _to, _caller, _amount);

        // Expect the `mint` and `burn` functions to be called
        vm.expectCall(_from, abi.encodeWithSelector(MintableAndBurnable.burn.selector, _caller, _amount), 1);
        vm.expectCall(_to, abi.encodeWithSelector(MintableAndBurnable.mint.selector, _caller, _amount), 1);

        // Act
        vm.prank(_caller);
        l2StandardBridge.convert(_from, _to, _amount);
    }
}

/// @notice Test when converting from a SuperchainERC20 token to a legacy token
contract L2StandardBridgeInterop_SuperToLegacy_Test is L2StandardBridgeInterop_Test {
    function _setUpSuperToLegacy(address _from, address _to) internal {
        // Assume
        vm.assume(_from != console2.CONSOLE_ADDRESS);
        vm.assume(_to != console2.CONSOLE_ADDRESS);

        // Mock same decimals
        _mockDecimals(_from, 18);
        _mockDecimals(_to, 18);

        // Mock `_to` to be a legacy address
        _mockInterface(_to, type(IERC165).interfaceId, true);
        _mockInterface(_to, type(IOptimismMintableERC20).interfaceId, true);
    }

    /// @notice Test that the `convert` function with different decimals reverts
    function testFuzz_convert_differenteDecimals_reverts(
        address _from,
        uint8 _decimalsFrom,
        address _to,
        uint8 _decimalsTo,
        uint256 _amount
    )
        public
    {
        // Assume
        vm.assume(_from != console2.CONSOLE_ADDRESS);
        vm.assume(_to != console2.CONSOLE_ADDRESS);
        vm.assume(_decimalsFrom != _decimalsTo);
        vm.assume(_from != _to);

        // Arrange
        // Mock the tokens to have different decimals
        _mockDecimals(_from, _decimalsFrom);
        _mockDecimals(_to, _decimalsTo);

        // Expect the revert with `InvalidDecimals` selector
        vm.expectRevert(InvalidDecimals.selector);

        // Act
        l2StandardBridge.convert(_from, _to, _amount);
    }

    /// @notice Test that the `convert` function with an invalid legacy address reverts
    function testFuzz_convert_invalidLegacyAddress_reverts(address _from, address _to, uint256 _amount) public {
        // Arrange
        _setUpSuperToLegacy(_from, _to);

        // Mock the legacy factory to return address(0)
        _mockDeployments(address(l2OptimismMintableERC20Factory), _to, address(0));

        // Expect the revert with `InvalidLegacyAddress` selector
        vm.expectRevert(InvalidLegacyAddress.selector);

        // Act
        l2StandardBridge.convert(_from, _to, _amount);
    }

    /// @notice Test that the `convert` function with an invalid superchain address reverts
    function testFuzz_convert_invalidSuperchainAddress_reverts(
        address _from,
        address _to,
        uint256 _amount,
        address _remoteToken
    )
        public
    {
        // Assume
        vm.assume(_remoteToken != address(0));

        // Arrange
        _setUpSuperToLegacy(_from, _to);

        // Mock the legacy factory to return `_remoteToken`
        _mockDeployments(address(l2OptimismMintableERC20Factory), _to, _remoteToken);

        // Mock the superchain factory to return address(0)
        _mockDeployments(Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY, _from, address(0));

        // Expect the revert with `InvalidSuperchainAddress` selector
        vm.expectRevert(InvalidSuperchainAddress.selector);

        // Act
        l2StandardBridge.convert(_from, _to, _amount);
    }

    /// @notice Test that the `convert` function with different remote tokens reverts
    function testFuzz_convert_differentRemoteAddresses_reverts(
        address _from,
        address _to,
        uint256 _amount,
        address _fromRemoteToken,
        address _toRemoteToken
    )
        public
    {
        // Assume
        vm.assume(_fromRemoteToken != address(0));
        vm.assume(_toRemoteToken != address(0));
        vm.assume(_fromRemoteToken != _toRemoteToken);

        // Arrange
        _setUpSuperToLegacy(_from, _to);

        // Mock the legacy factory to return `_fromRemoteToken`
        _mockDeployments(address(l2OptimismMintableERC20Factory), _to, _fromRemoteToken);

        // Mock the superchain factory to return `_toRemoteToken`
        _mockDeployments(Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY, _from, _toRemoteToken);

        // Expect the revert with `InvalidTokenPair` selector
        vm.expectRevert(InvalidTokenPair.selector);

        // Act
        l2StandardBridge.convert(_from, _to, _amount);
    }

    /// @notice Test that the `convert` function succeeds
    function testFuzz_convert_succeeds(
        address _caller,
        address _from,
        address _to,
        uint256 _amount,
        address _remoteToken
    )
        public
    {
        // Assume
        vm.assume(_remoteToken != address(0));

        // Arrange
        _setUpSuperToLegacy(_from, _to);

        // Mock the legacy and superchain factory to return `_remoteToken`
        _mockDeployments(address(l2OptimismMintableERC20Factory), _to, _remoteToken);
        _mockDeployments(Predeploys.OPTIMISM_SUPERCHAIN_ERC20_FACTORY, _from, _remoteToken);

        // Mock the `burn` and `mint` functions
        vm.mockCall(_from, abi.encodeWithSelector(MintableAndBurnable.burn.selector, _caller, _amount), abi.encode());
        vm.mockCall(_to, abi.encodeWithSelector(MintableAndBurnable.mint.selector, _caller, _amount), abi.encode());

        // Expect the `Converted` event to be emitted
        vm.expectEmit(true, true, true, true, address(l2StandardBridge));
        emit Converted(_from, _to, _caller, _amount);

        // Expect the `mint` and `burn` functions to be called
        vm.expectCall(_from, abi.encodeWithSelector(MintableAndBurnable.burn.selector, _caller, _amount), 1);
        vm.expectCall(_to, abi.encodeWithSelector(MintableAndBurnable.mint.selector, _caller, _amount), 1);

        // Act
        vm.prank(_caller);
        l2StandardBridge.convert(_from, _to, _amount);
    }
}