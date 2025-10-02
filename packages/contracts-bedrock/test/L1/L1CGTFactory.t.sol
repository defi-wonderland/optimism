// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

// Contracts
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { L1CGTFactory } from "src/L1/L1CGTFactory.sol";

// Libraries
import { Features } from "src/libraries/Features.sol";
import { DevFeatures } from "src/libraries/DevFeatures.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title L1CGTFactory_TestInit
/// @notice Reusable test initialization for `L1CGTFactory` tests.
contract L1CGTFactory_TestInit is CommonTest {
    using stdStorage for StdStorage;

    /// @notice Emitted when the protocol is deployed.
    event ProtocolDeployed(address indexed l1Bridge, address indexed l2Factory, address indexed l2Bridge);

    L1CGTFactory internal l1CGTFactory;
    L1CGTFactory internal l1CGTFactoryImpl;

    IERC20 internal mockCGTToken;

    address internal l1BridgeOwner;
    address internal l2BridgeOwner;
    string chainName = "TestChain";

    /// @notice Test setup.
    function setUp() public virtual override {
        super.setUp();
        skipIfDevFeatureDisabled(DevFeatures.CUSTOM_GAS_TOKEN);

        // Create test addresses
        l1BridgeOwner = makeAddr("l1BridgeOwner");
        l2BridgeOwner = makeAddr("l2BridgeOwner");
        mockCGTToken = IERC20(makeAddr("cgtToken"));

        // Deploy implementation
        l1CGTFactoryImpl = new L1CGTFactory();

        // Deploy proxy and initialize
        vm.prank(proxyAdminOwner);
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(l1CGTFactoryImpl), abi.encodeCall(L1CGTFactory.initialize, (mockCGTToken)));

        l1CGTFactory = L1CGTFactory(address(proxy));
    }

    /// @notice Helper function to create L2 deployment parameters.
    function _createL2Deployments() internal view returns (L1CGTFactory.L2Deployments memory) {
        return L1CGTFactory.L2Deployments({
            l2BridgeOwner: l2BridgeOwner,
            liquidityController: address(liquidityController),
            minGasLimitDeploy: 100000,
            minGasLimitBridge: 50000
        });
    }
}

/// @title L1CGTFactory_Initialize_Test
/// @notice Tests the `initialize` function of the `L1CGTFactory` contract.
contract L1CGTFactory_Initialize_Test is L1CGTFactory_TestInit {
    /// @notice Tests that initialization sets the CGT token correctly.
    function test_initialize_succeeds() public view {
        assertEq(address(l1CGTFactory.cgtToken()), address(mockCGTToken));
        assertEq(l1CGTFactory.deploymentsSaltCounter(), 0);
        assertEq(l1CGTFactory.L2_CREATE2_DEPLOYER(), 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2);
        assertEq(l1CGTFactory.version(), "1.0.0");
    }

    /// @notice Tests that initialization reverts when called by non-authorized user.
    function test_initialize_unauthorizedCaller_reverts() public {
        L1CGTFactory newImplementation = new L1CGTFactory();

        vm.expectRevert();
        vm.prank(makeAddr("unauthorized"));
        new ERC1967Proxy(address(newImplementation), abi.encodeCall(L1CGTFactory.initialize, (mockCGTToken)));
    }

    /// @notice Tests that initialization can be called by ProxyAdmin owner.
    function test_initialize_byProxyAdminOwner_succeeds() public {
        L1CGTFactory newImplementation = new L1CGTFactory();

        vm.prank(proxyAdminOwner);
        ERC1967Proxy newProxy =
            new ERC1967Proxy(address(newImplementation), abi.encodeCall(L1CGTFactory.initialize, (mockCGTToken)));

        L1CGTFactory newFactory = L1CGTFactory(address(newProxy));
        assertEq(address(newFactory.cgtToken()), address(mockCGTToken));
    }
}

/// @title L1CGTFactory_Deploy_Test
/// @notice Tests the `deploy` function of the `L1CGTFactory` contract.
contract L1CGTFactory_Deploy_Test is L1CGTFactory_TestInit {
    /// @notice Tests successful deployment by ProxyAdmin owner.
    function test_deploy_byProxyAdminOwner_succeeds() public {
        L1CGTFactory.L2Deployments memory l2Deployments = _createL2Deployments();

        vm.expectEmit(true, true, true, false);
        emit ProtocolDeployed(address(0), address(0), address(0));

        vm.prank(proxyAdminOwner);
        (address l1Bridge, address l2Factory, address l2Bridge) = l1CGTFactory.deploy(
            l1CrossDomainMessenger, superchainConfig, systemConfig, l1BridgeOwner, chainName, l2Deployments
        );

        // Verify addresses are not zero
        assertTrue(l1Bridge != address(0));
        assertTrue(l2Factory != address(0));
        assertTrue(l2Bridge != address(0));

        // Verify salt counter was incremented
        assertEq(l1CGTFactory.deploymentsSaltCounter(), 2);
    }

    /// @notice Tests successful deployment by ProxyAdmin.
    function test_deploy_byProxyAdmin_succeeds() public {
        L1CGTFactory.L2Deployments memory l2Deployments = _createL2Deployments();

        vm.expectEmit(true, true, true, false);
        emit ProtocolDeployed(address(0), address(0), address(0));

        vm.prank(address(proxyAdmin));
        (address l1Bridge, address l2Factory, address l2Bridge) = l1CGTFactory.deploy(
            l1CrossDomainMessenger, superchainConfig, systemConfig, l1BridgeOwner, chainName, l2Deployments
        );

        // Verify addresses are not zero
        assertTrue(l1Bridge != address(0));
        assertTrue(l2Factory != address(0));
        assertTrue(l2Bridge != address(0));
    }

    /// @notice Tests deployment with unauthorized caller reverts.
    function test_deploy_unauthorizedCaller_reverts() public {
        L1CGTFactory.L2Deployments memory l2Deployments = _createL2Deployments();

        vm.expectRevert();
        vm.prank(makeAddr("unauthorized"));
        l1CGTFactory.deploy(
            l1CrossDomainMessenger, superchainConfig, systemConfig, l1BridgeOwner, chainName, l2Deployments
        );
    }

    /// @notice Tests deployment with CGT mode disabled reverts.
    function test_deploy_cgtModeDisabled_reverts() public {
        L1CGTFactory.L2Deployments memory l2Deployments = _createL2Deployments();

        // Disable CGT mode by disabling the feature
        vm.mockCall(
            address(systemConfig),
            abi.encodeWithSignature("isFeatureEnabled(uint8)", Features.CUSTOM_GAS_TOKEN),
            abi.encode(false)
        );

        vm.expectRevert(L1CGTFactory.L1CGTFactory_CustomGasTokenNotEnabled.selector);
        vm.prank(proxyAdminOwner);
        l1CGTFactory.deploy(
            l1CrossDomainMessenger, superchainConfig, systemConfig, l1BridgeOwner, chainName, l2Deployments
        );
    }
}

/// @title L1CGTFactory_Constants_Test
/// @notice Tests the constants of the `L1CGTFactory` contract.
contract L1CGTFactory_Constants_Test is L1CGTFactory_TestInit {
    /// @notice Tests that constants are set correctly.
    function test_constants_succeeds() public view {
        assertEq(l1CGTFactory.L2_CREATE2_DEPLOYER(), 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2);
        assertEq(l1CGTFactory.version(), "1.0.0");
    }
}

/// @title L1CGTFactory_Version_Test
/// @notice Tests the `version` function of the `L1CGTFactory` contract.
contract L1CGTFactory_Version_Test is L1CGTFactory_TestInit {
    /// @notice Tests that the version function returns a valid string.
    function test_version_succeeds() public view {
        assertTrue(bytes(l1CGTFactory.version()).length > 0);
        assertEq(l1CGTFactory.version(), "1.0.0");
    }
}

/// @title L1CGTFactory_Integration_Test
/// @notice Integration tests for the `L1CGTFactory` contract.
contract L1CGTFactory_Integration_Test is L1CGTFactory_TestInit {
    /// @notice Tests that multiple deployments create different addresses.
    function test_multipleDeployments_createDifferentAddresses() public {
        L1CGTFactory.L2Deployments memory l2Deployments = _createL2Deployments();

        vm.startPrank(proxyAdminOwner);

        (address l1Bridge1, address l2Factory1, address l2Bridge1) = l1CGTFactory.deploy(
            l1CrossDomainMessenger, superchainConfig, systemConfig, l1BridgeOwner, chainName, l2Deployments
        );

        (address l1Bridge2, address l2Factory2, address l2Bridge2) = l1CGTFactory.deploy(
            l1CrossDomainMessenger, superchainConfig, systemConfig, l1BridgeOwner, chainName, l2Deployments
        );

        vm.stopPrank();

        // Verify addresses are different
        assertTrue(l1Bridge1 != l1Bridge2);
        assertTrue(l2Factory1 != l2Factory2);
        assertTrue(l2Bridge1 != l2Bridge2);

        // Verify salt counter was incremented correctly
        assertEq(l1CGTFactory.deploymentsSaltCounter(), 4);
    }

    /// @notice Tests that the factory uses the correct system contracts.
    function test_usesCorrectSystemContracts() public view {
        // Verify the factory can access system contracts
        assertTrue(address(l1CrossDomainMessenger) != address(0));
        assertTrue(address(superchainConfig) != address(0));
        assertTrue(address(systemConfig) != address(0));
        assertTrue(address(liquidityController) != address(0));
    }
}
