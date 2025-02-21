// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing
import { Test } from "forge-std/Test.sol";

// Target contract
import { CrosschainERC20Factory } from "src/L2/CrosschainERC20/CrosschainERC20Factory.sol";
import { XERC20Lockbox } from "@xERC20/contracts/XERC20Lockbox.sol";
import { CrosschainERC20 } from "src/L2/CrosschainERC20/CrosschainERC20.sol";

// Interfaces
import { ICrosschainERC20 } from "interfaces/L2/CrosschainERC20/ICrosschainERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title CrosschainERC20FactoryTest
/// @notice Contract for testing the CrosschainERC20Factory contract.
contract CrosschainERC20Factory_Test is Test {
    CrosschainERC20Factory factory;

    address _owner = makeAddr("owner");
    address _bridge = makeAddr("bridge");
    address _bridge2 = makeAddr("bridge2");

    /// @notice Test setup.
    function setUp() public {
        factory = new CrosschainERC20Factory();
    }

    /// @notice Helper function to get the bridges with limits.
    /// @param _minterLimit The minter limit.
    /// @param _burnerLimit The burner limit.
    /// @return _bridges The bridges.
    /// @return _minterLimits The minter limits.
    /// @return _burnerLimits The burner limits.
    function _getBridgesWithLimits(
        uint256 _minterLimit,
        uint256 _burnerLimit
    )
        internal
        view
        returns (address[] memory _bridges, uint256[] memory _minterLimits, uint256[] memory _burnerLimits)
    {
        // Create the arrays
        _bridges = new address[](2);
        _minterLimits = new uint256[](2);
        _burnerLimits = new uint256[](2);

        // Set the values for the first bridge
        _bridges[0] = _bridge;
        _minterLimits[0] = _minterLimit;
        _burnerLimits[0] = _burnerLimit;

        // Set the values for the second bridge
        _bridges[1] = _bridge2;
        _minterLimits[1] = _minterLimit;
        _burnerLimits[1] = _burnerLimit;
    }

    /// @notice Test that the deployCrosschainERC20 function reverts if the minter limits and burner limits arrays are of different lengths.
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
        factory.deployCrosschainERC20("Test", "TEST", _minterLimits, _burnerLimits, _bridges);
    }

    /// @notice Test that the deployCrosschainERC20 function succeeds.
    /// @param _minterLimit The minter limit.
    /// @param _burnerLimit The burner limit.
    function test_deployCrosschainERC20_deployment_succeds(uint256 _minterLimit, uint256 _burnerLimit) public {
        string memory _name = unicode"🐧 Test 🐧";
        string memory _symbol = "TST";

        // Bound limits in allowed range
        _minterLimit = bound(_minterLimit, 1, type(uint256).max >> 1);
        _burnerLimit = bound(_burnerLimit, 1, type(uint256).max >> 1);

        // Get the bridges with limits
        (address[] memory _bridges, uint256[] memory _minterLimits, uint256[] memory _burnerLimits) =
            _getBridgesWithLimits(_minterLimit, _burnerLimit);

        // Deploy the CrosschainERC20
        vm.prank(_owner);
        address _crosschainERC20 = factory.deployCrosschainERC20(_name, _symbol, _minterLimits, _burnerLimits, _bridges);

        // Assert the CrosschainERC20 is deployed
        assertGt(_crosschainERC20.code.length, 0);

        // Assert the token name and symbol are correct
        assertEq(IERC20Metadata(_crosschainERC20).name(), _name);
        assertEq(IERC20Metadata(_crosschainERC20).symbol(), _symbol);
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
        vm.prank(_owner);
        address _crosschainERC20 = factory.deployCrosschainERC20("Test", "TEST", _minterLimits, _burnerLimits, _bridges);

        // Assert the limits are set correctly
        for (uint256 _i; _i < _bridges.length; ++_i) {
            (ICrosschainERC20.BridgeParameters memory _minterParams, ICrosschainERC20.BridgeParameters memory _burnerParams) =
                CrosschainERC20(_crosschainERC20).bridges(_bridges[_i]);
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
        vm.prank(_owner);
        address _crosschainERC20 = factory.deployCrosschainERC20("Test", "TEST", _minterLimits, _burnerLimits, _bridges);
        
        // Assert the owner is the deployer
        assertEq(Ownable(_crosschainERC20).owner(), _owner);
    }

    /// @notice Test that the deployCrosschainERC20WithLockbox function succeeds.
    function test_deployCrosschainERC20WithLockbox_deployment_succeeds(uint256 _minterLimit, uint256 _burnerLimit) public {
        // Bound limits in allowed range
        _minterLimit = bound(_minterLimit, 1, type(uint256).max >> 1);
        _burnerLimit = bound(_burnerLimit, 1, type(uint256).max >> 1);

        // Get the bridges with limits
        (address[] memory _bridges, uint256[] memory _minterLimits, uint256[] memory _burnerLimits) =
            _getBridgesWithLimits(_minterLimit, _burnerLimit);

        string memory _name = unicode"🐧 Test 🐧";
        string memory _symbol = "TST";

        // Declare contract addresses
        address _crosschainERC20;
        address _crosschainERC20Lockbox;
        address _baseToken = address(makeAddr("ERC20"));

        // Deploy the CrosschainERC20 with Lockbox
        vm.prank(_owner);
        (_crosschainERC20, _crosschainERC20Lockbox) = factory.deployCrosschainERC20WithLockbox(_name, _symbol, _minterLimits, _burnerLimits, _bridges, _baseToken);

        // Assert the CrosschainERC20 is deployed
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

        string memory _name = unicode"🐧 Test 🐧";
        string memory _symbol = "TST";

        // Declare contract addresses
        address _crosschainERC20;
        address _crosschainERC20Lockbox;
        address _baseToken = address(makeAddr("ERC20"));

        // Deploy the CrosschainERC20 with Lockbox
        vm.prank(_owner);
        (_crosschainERC20, _crosschainERC20Lockbox) = factory.deployCrosschainERC20WithLockbox(_name, _symbol, _minterLimits, _burnerLimits, _bridges, _baseToken);

        // Assert the CrosschainERC20Lockbox is set
        assertEq(address(XERC20Lockbox(payable(_crosschainERC20Lockbox)).XERC20()), _crosschainERC20);
    }
}
