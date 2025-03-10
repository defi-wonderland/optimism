// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing
import { Test } from "forge-std/Test.sol";

// Target contract
import { CrosschainERC20Factory } from "src/L2/CrosschainERC20/CrosschainERC20Factory.sol";
import { XERC20Lockbox } from "@xERC20/contracts/XERC20Lockbox.sol";
import { CrosschainERC20 } from "src/L2/CrosschainERC20/CrosschainERC20.sol";
import { ERC7802Adapter } from "src/L2/CrosschainERC20/ERC7802Adapter.sol";

// Interfaces
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Libraries
import { CREATE3 } from "isolmate/utils/CREATE3.sol";

/// @title CrosschainERC20FactoryForTest
/// @notice Contract for testing the CrosschainERC20Factory contract.
contract CrosschainERC20FactoryForTest is CrosschainERC20Factory {
    function getDeployed(bytes32 _salt) public view returns (address) {
        return CREATE3.getDeployed(_salt);
    }
}

/// @title CrosschainERC20FactoryTest
/// @notice Contract for testing the CrosschainERC20Factory contract.
contract CrosschainERC20Factory_Test is Test {
    CrosschainERC20FactoryForTest factory;

    address owner = makeAddr("owner");
    address bridge = makeAddr("bridge");
    address bridge2 = makeAddr("bridge2");

    string name = "Test";
    string symbol = "TST";

    /// @notice Test setup.
    function setUp() public {
        factory = new CrosschainERC20FactoryForTest();
    }

    /// @notice Helper function to get the bridges with limits.
    /// @param _minterLimit The minter limit.
    /// @param _burnerLimit The burner limit.
    /// @return bridges_ The bridges.
    /// @return minterLimits_ The minter limits.
    /// @return burnerLimits_ The burner limits.
    function _getBridgesWithLimits(
        uint256 _minterLimit,
        uint256 _burnerLimit
    )
        internal
        view
        returns (address[] memory bridges_, uint256[] memory minterLimits_, uint256[] memory burnerLimits_)
    {
        // Create the arrays
        bridges_ = new address[](2);
        minterLimits_ = new uint256[](2);
        burnerLimits_ = new uint256[](2);

        // Set the values for the first bridge
        bridges_[0] = bridge;
        minterLimits_[0] = _minterLimit;
        burnerLimits_[0] = _burnerLimit;

        // Set the values for the second bridge
        bridges_[1] = bridge2;
        minterLimits_[1] = _minterLimit;
        burnerLimits_[1] = _burnerLimit;
    }

    /// @notice Test that the deployCrosschainERC20 function reverts if the minter limits and burner limits arrays are
    /// of different lengths.
    /// @param _minterLimit The minter limit.
    /// @param _burnerLimit The burner limit.
    function test_deployCrosschainERC20_mismatchedLengths_reverts(uint256 _minterLimit, uint256 _burnerLimit) public {
        // Bound limits in allowed range
        _minterLimit = bound(_minterLimit, 1, type(uint256).max >> 1);
        _burnerLimit = bound(_burnerLimit, 1, type(uint256).max >> 1);

        // Get the bridges with limits
        (address[] memory _bridges,, uint256[] memory _burnerLimits) = _getBridgesWithLimits(_minterLimit, _burnerLimit);

        // Use shorter array for minter limits
        uint256[] memory _minterLimits = new uint256[](1);
        _minterLimits[0] = _minterLimit;

        // Deploy the CrosschainERC20
        vm.expectRevert(CrosschainERC20Factory.InvalidLength.selector);
        factory.deployCrosschainERC20(name, symbol, _minterLimits, _burnerLimits, _bridges, owner);
    }

    /// @notice Test that the deployCrosschainERC20 function succeeds.
    /// @param _minterLimit The minter limit.
    /// @param _burnerLimit The burner limit.
    function test_deployCrosschainERC20_deployment_succeeds(uint256 _minterLimit, uint256 _burnerLimit) public {
        // Bound limits in allowed range
        _minterLimit = bound(_minterLimit, 1, type(uint256).max >> 1);
        _burnerLimit = bound(_burnerLimit, 1, type(uint256).max >> 1);

        // Get the bridges with limits
        (address[] memory _bridges, uint256[] memory _minterLimits, uint256[] memory _burnerLimits) =
            _getBridgesWithLimits(_minterLimit, _burnerLimit);

        // Calculate the salt and expected address
        bytes32 salt = keccak256(abi.encodePacked(name, symbol, address(this)));
        address expectedAddress = factory.getDeployed(salt);

        // Expect the CrosschainERC20Deployed event
        vm.expectEmit(address(factory));
        emit CrosschainERC20Factory.CrosschainERC20Deployed(expectedAddress, name, symbol, owner);

        // Deploy the CrosschainERC20
        address _crosschainERC20 =
            factory.deployCrosschainERC20(name, symbol, _minterLimits, _burnerLimits, _bridges, owner);

        // Assert the CrosschainERC20 is deployed
        assertGt(_crosschainERC20.code.length, 0);
        assertEq(_crosschainERC20, expectedAddress);

        // Assert the token name and symbol are correct
        assertEq(IERC20Metadata(_crosschainERC20).name(), name);
        assertEq(IERC20Metadata(_crosschainERC20).symbol(), symbol);
    }

    /// @notice Test that the deployCrosschainERC20 function sets the limits correctly.
    /// @param _minterLimit The minter limit.
    /// @param _burnerLimit The burner limit.
    function test_deployCrosschainERC20_setLimits_succeeds(uint256 _minterLimit, uint256 _burnerLimit) public {
        // Bound limits in allowed range
        _minterLimit = bound(_minterLimit, 1, type(uint256).max >> 1);
        _burnerLimit = bound(_burnerLimit, 1, type(uint256).max >> 1);

        // Get the bridges with limits
        (address[] memory _bridges, uint256[] memory _minterLimits, uint256[] memory _burnerLimits) =
            _getBridgesWithLimits(_minterLimit, _burnerLimit);

        // Deploy the CrosschainERC20
        address _crosschainERC20 =
            factory.deployCrosschainERC20(name, symbol, _minterLimits, _burnerLimits, _bridges, owner);

        // Assert the limits are set correctly
        for (uint256 _i; _i < _bridges.length; ++_i) {
            (
                CrosschainERC20.BridgeParameters memory _minterParams,
                CrosschainERC20.BridgeParameters memory _burnerParams
            ) = CrosschainERC20(_crosschainERC20).bridges(_bridges[_i]);
            assertEq(_minterParams.maxLimit, _minterLimits[_i]);
            assertEq(_burnerParams.maxLimit, _burnerLimits[_i]);
        }
    }

    /// @notice Test that the deployCrosschainERC20 function transfers the ownership to the deployer.
    function test_deployCrosschainERC20_transferOwnership_succeeds() public {
        // Get the bridges with limits
        (address[] memory _bridges, uint256[] memory _minterLimits, uint256[] memory _burnerLimits) =
            _getBridgesWithLimits(1, 1);

        // Deploy the CrosschainERC20
        address _crosschainERC20 =
            factory.deployCrosschainERC20(name, symbol, _minterLimits, _burnerLimits, _bridges, owner);

        // Assert the owner was correctly set
        assertEq(Ownable(_crosschainERC20).owner(), owner);
    }

    /// @notice Test that the deployCrosschainERC20WithLockbox function succeeds.
    function test_deployCrosschainERC20WithLockbox_deployment_succeeds(
        uint256 _minterLimit,
        uint256 _burnerLimit
    )
        public
    {
        // Bound limits in allowed range
        _minterLimit = bound(_minterLimit, 1, type(uint256).max >> 1);
        _burnerLimit = bound(_burnerLimit, 1, type(uint256).max >> 1);

        // Get the bridges with limits
        (address[] memory _bridges, uint256[] memory _minterLimits, uint256[] memory _burnerLimits) =
            _getBridgesWithLimits(_minterLimit, _burnerLimit);

        address _baseToken = address(makeAddr("ERC20"));

        // Calculate expected addresses
        bytes32 tokenSalt = keccak256(abi.encodePacked(name, symbol, address(this)));
        address expectedTokenAddress = factory.getDeployed(tokenSalt);

        bytes32 lockboxSalt = keccak256(abi.encodePacked(expectedTokenAddress, _baseToken, address(this)));
        address expectedLockboxAddress = factory.getDeployed(lockboxSalt);

        // Expect deployment events
        vm.expectEmit(address(factory));
        emit CrosschainERC20Factory.CrosschainERC20Deployed(expectedTokenAddress, name, symbol, owner);

        vm.expectEmit(address(factory));
        emit CrosschainERC20Factory.LockboxDeployed(expectedLockboxAddress, expectedTokenAddress, _baseToken);

        // Deploy the CrosschainERC20 with Lockbox
        (address _crosschainERC20, address _crosschainERC20Lockbox) = factory.deployCrosschainERC20WithLockbox(
            name, symbol, _minterLimits, _burnerLimits, _bridges, _baseToken, owner
        );

        // Assert addresses match precomputed ones
        assertEq(_crosschainERC20, expectedTokenAddress);
        assertEq(_crosschainERC20Lockbox, expectedLockboxAddress);

        // Rest of the assertions...
        assertGt(_crosschainERC20.code.length, 0);

        // Assert the CrosschainERC20Lockbox is deployed
        assertGt(_crosschainERC20Lockbox.code.length, 0);

        // Assert the Base Token is set
        assertEq(address(XERC20Lockbox(payable(_crosschainERC20Lockbox)).ERC20()), _baseToken);

        // Assert the CrosschainERC20 is set
        assertEq(address(XERC20Lockbox(payable(_crosschainERC20Lockbox)).XERC20()), _crosschainERC20);

        // Assert the IS_NATIVE flag is set to false
        assertEq(XERC20Lockbox(payable(_crosschainERC20Lockbox)).IS_NATIVE(), false);
    }

    /// @notice Test that the deployCrosschainERC20WithLockbox function sets the lockbox correctly.
    function test_deployCrosschainERC20WithLockbox_setLockbox_succeeds() public {
        // Get the bridges with limits
        (address[] memory _bridges, uint256[] memory _minterLimits, uint256[] memory _burnerLimits) =
            _getBridgesWithLimits(1, 1);

        // Declare contract addresses
        address _crosschainERC20;
        address _crosschainERC20Lockbox;
        address _baseToken = address(makeAddr("ERC20"));

        // Deploy the CrosschainERC20 with Lockbox
        (_crosschainERC20, _crosschainERC20Lockbox) = factory.deployCrosschainERC20WithLockbox(
            name, symbol, _minterLimits, _burnerLimits, _bridges, _baseToken, owner
        );

        // Assert the CrosschainERC20Lockbox is set
        assertEq(address(XERC20Lockbox(payable(_crosschainERC20Lockbox)).XERC20()), _crosschainERC20);
    }

    /// @notice Test that the deployERC7802Adapter function succeeds.
    function test_deployERC7802Adapter_deployment_succeeds() public {
        address _xerc20 = address(makeAddr("xERC20"));

        // Calculate expected adapter address
        bytes32 salt = keccak256(abi.encodePacked(_crosschainERC20, bridge, address(this)));
        address adapterAddress = factory.getDeployed(salt);

        // Expect the deployment event
        vm.expectEmit(address(factory));
        emit CrosschainERC20Factory.ERC7802AdapterDeployed(adapterAddress, _crosschainERC20, bridge);

        // Deploy the ERC7802Adapter
        vm.prank(owner);
        address _erc7802Adapter = factory.deployERC7802Adapter(_xerc20, bridge);

        // Assert address matches precomputed one
        assertEq(_erc7802Adapter, adapterAddress);

        // Assert the ERC7802Adapter is deployed
        assertGt(_erc7802Adapter.code.length, 0);

        // Assert the xERC20 is set
        assertEq(address(ERC7802Adapter(_erc7802Adapter).XERC20()), _xerc20);

        // Assert the Bridge is set
        assertEq(address(ERC7802Adapter(_erc7802Adapter).BRIDGE()), bridge);
    }
}
