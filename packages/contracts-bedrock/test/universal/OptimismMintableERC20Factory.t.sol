// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";
import { NextImpl } from "test/mocks/NextImpl.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";

// Contracts
import { OptimismMintableERC20 } from "src/universal/OptimismMintableERC20.sol";
import { L1OptimismMintableERC20Factory } from "src/L1/L1OptimismMintableERC20Factory.sol";
import { L2OptimismMintableERC20Factory } from "src/L2/L2OptimismMintableERC20Factory.sol";

// Interfaces
import { IStandardBridge } from "interfaces/universal/IStandardBridge.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { IOptimismMintableERC20Factory } from "interfaces/universal/IOptimismMintableERC20Factory.sol";

/// @notice Common test suite for both L1 and L2 OptimismMintableERC20Factory implementations.
abstract contract OptimismMintableTokenFactory_Test is CommonTest {
    event StandardL2TokenCreated(address indexed remoteToken, address indexed localToken);
    event OptimismMintableERC20Created(address indexed localToken, address indexed remoteToken, address deployer);

    /// @notice Tests that the constructor is initialized correctly.
    function test_constructor_succeeds() external virtual;

    /// @notice Returns the bridge implementation.
    function _bridge() internal view virtual returns (IStandardBridge);

    /// @notice Returns the factory implementation.
    function _factory() internal view virtual returns (IOptimismMintableERC20Factory);

    /// @notice Test that calling `createStandardL2Token` with valid parameters succeeds.
    function test_createStandardL2Token_succeeds(
        address _caller,
        address _remoteToken,
        string memory _name,
        string memory _symbol
    )
        external
    {
        // Assume
        vm.assume(_remoteToken != address(0));

        // Arrange
        // Defaults to 18 decimals
        address local = _calculateTokenAddress(_remoteToken, _name, _symbol, 18);

        vm.expectEmit(address(_factory()));
        emit StandardL2TokenCreated(_remoteToken, local);

        vm.expectEmit(address(_factory()));
        emit OptimismMintableERC20Created(local, _remoteToken, _caller);

        // Act
        vm.prank(_caller);
        address addr = _factory().createStandardL2Token(_remoteToken, _name, _symbol);

        // Assert
        assertTrue(addr == local);
        assertTrue(OptimismMintableERC20(local).decimals() == 18);
        assertEq(_factory().deployments(local), _remoteToken);
    }

    /// @notice Test that calling `createOptimismMintableERC20WithDecimals` with valid parameters succeeds.
    function test_createStandardL2TokenWithDecimals_succeeds(
        address _caller,
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        external
    {
        // Assume
        vm.assume(_remoteToken != address(0));

        // Arrange
        address local = _calculateTokenAddress(_remoteToken, _name, _symbol, _decimals);

        vm.expectEmit(address(_factory()));
        emit StandardL2TokenCreated(_remoteToken, local);

        vm.expectEmit(address(_factory()));
        emit OptimismMintableERC20Created(local, _remoteToken, _caller);

        // Act
        vm.prank(_caller);
        address addr = _factory().createOptimismMintableERC20WithDecimals(_remoteToken, _name, _symbol, _decimals);

        // Assert
        assertTrue(addr == local);
        assertTrue(OptimismMintableERC20(local).decimals() == _decimals);
        assertEq(_factory().deployments(local), _remoteToken);
    }

    /// @notice Test that calling `createStandardL2Token` with the same parameters twice reverts.
    function test_createStandardL2Token_sameTwice_reverts(
        address _caller,
        address _remoteToken,
        string memory _name,
        string memory _symbol
    )
        external
    {
        // Assume
        vm.assume(_remoteToken != address(0));

        vm.prank(_caller);
        _factory().createStandardL2Token(_remoteToken, _name, _symbol);

        // Arrange
        vm.expectRevert(bytes(""));

        // Act
        vm.prank(_caller);
        _factory().createStandardL2Token(_remoteToken, _name, _symbol);
    }

    /// @notice Test that calling `createStandardL2TokenWithDecimals` with the same parameters twice reverts.
    function test_createStandardL2TokenWithDecimals_sameTwice_reverts(
        address _caller,
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        external
    {
        // Assume
        vm.assume(_remoteToken != address(0));

        vm.prank(_caller);
        _factory().createOptimismMintableERC20WithDecimals(_remoteToken, _name, _symbol, _decimals);

        // Arrange
        vm.expectRevert(bytes(""));

        // Act
        vm.prank(_caller);
        _factory().createOptimismMintableERC20WithDecimals(_remoteToken, _name, _symbol, _decimals);
    }

    /// @notice Test that calling `createStandardL2Token` with a zero remote token address reverts.
    function test_createStandardL2Token_remoteIsZero_reverts(
        address _caller,
        string memory _name,
        string memory _symbol
    )
        external
    {
        // Arrange
        address remote = address(0);
        vm.expectRevert("OptimismMintableERC20Factory: must provide remote token address");

        // Act
        vm.prank(_caller);
        _factory().createStandardL2Token(remote, _name, _symbol);
    }

    /// @notice Test that calling `createStandardL2TokenWithDecimals` with a zero remote token address reverts.
    function test_createStandardL2TokenWithDecimals_remoteIsZero_reverts(
        address _caller,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        external
    {
        // Arrange
        address remote = address(0);
        vm.expectRevert("OptimismMintableERC20Factory: must provide remote token address");

        // Act
        vm.prank(_caller);
        _factory().createOptimismMintableERC20WithDecimals(remote, _name, _symbol, _decimals);
    }

    /// @notice Precalculates the address of the token contract.
    function _calculateTokenAddress(
        address _remote,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        internal
        view
        returns (address)
    {
        bytes memory constructorArgs = abi.encode(address(_bridge()), _remote, _name, _symbol, _decimals);
        bytes memory bytecode = abi.encodePacked(type(OptimismMintableERC20).creationCode, constructorArgs);
        bytes32 salt = keccak256(abi.encode(_remote, _name, _symbol, _decimals));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(_factory()), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }
}

contract L2OptimismMintableTokenFactory_Test is OptimismMintableTokenFactory_Test {
    /// @inheritdoc OptimismMintableTokenFactory_Test
    function test_constructor_succeeds() external virtual override {
        IOptimismMintableERC20Factory impl =
            IOptimismMintableERC20Factory(address(new L2OptimismMintableERC20Factory()));
        assertEq(address(impl.BRIDGE()), address(l2StandardBridge));
        assertEq(address(impl.bridge()), address(l2StandardBridge));
    }

    /// @inheritdoc OptimismMintableTokenFactory_Test
    function _bridge() internal view virtual override returns (IStandardBridge) {
        return l2StandardBridge;
    }

    /// @inheritdoc OptimismMintableTokenFactory_Test
    function _factory() internal view virtual override returns (IOptimismMintableERC20Factory) {
        return IOptimismMintableERC20Factory(address(l2OptimismMintableERC20Factory));
    }
}

contract L1OptimismMintableTokenFactory_Test is OptimismMintableTokenFactory_Test {
    /// @inheritdoc OptimismMintableTokenFactory_Test
    function test_constructor_succeeds() external virtual override {
        IOptimismMintableERC20Factory impl =
            IOptimismMintableERC20Factory(address(new L1OptimismMintableERC20Factory()));
        assertEq(address(impl.BRIDGE()), address(0));
        assertEq(address(impl.bridge()), address(0));
    }

    /// @notice Tests that the proxy is initialized correctly.
    function test_initialize_succeeds() external view {
        assertEq(address(l1OptimismMintableERC20Factory.BRIDGE()), address(l1StandardBridge));
        assertEq(address(l1OptimismMintableERC20Factory.bridge()), address(l1StandardBridge));
    }

    /// @notice Tests that the upgrade is successful.
    function test_upgrading_succeeds() external {
        IProxy proxy = IProxy(deploy.mustGetAddress("OptimismMintableERC20FactoryProxy"));
        // Check an unused slot before upgrading.
        bytes32 slot21Before = vm.load(address(l1OptimismMintableERC20Factory), bytes32(uint256(21)));
        assertEq(bytes32(0), slot21Before);

        NextImpl nextImpl = new NextImpl();
        vm.startPrank(EIP1967Helper.getAdmin(address(proxy)));
        // Reviewer note: the NextImpl() still uses reinitializer. If we want to remove that, we'll need to use a
        //   two step upgrade with the Storage lib.
        proxy.upgradeToAndCall(address(nextImpl), abi.encodeCall(NextImpl.initialize, (2)));
        assertEq(proxy.implementation(), address(nextImpl));

        // Verify that the NextImpl contract initialized its values according as expected
        bytes32 slot21After = vm.load(address(l1OptimismMintableERC20Factory), bytes32(uint256(21)));
        bytes32 slot21Expected = NextImpl(address(l1OptimismMintableERC20Factory)).slot21Init();
        assertEq(slot21Expected, slot21After);
    }

    /// @inheritdoc OptimismMintableTokenFactory_Test
    function _bridge() internal view virtual override returns (IStandardBridge) {
        return l1StandardBridge;
    }

    /// @inheritdoc OptimismMintableTokenFactory_Test
    function _factory() internal view virtual override returns (IOptimismMintableERC20Factory) {
        return IOptimismMintableERC20Factory(address(l1OptimismMintableERC20Factory));
    }
}
