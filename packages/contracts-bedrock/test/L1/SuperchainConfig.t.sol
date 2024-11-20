// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";

// Target contract dependencies
import { IProxy } from "src/universal/interfaces/IProxy.sol";
import { Unauthorized } from "src/libraries/errors/CommonErrors.sol";

// Target contract
import { ISuperchainConfig } from "src/L1/interfaces/ISuperchainConfig.sol";
import { SuperchainConfig, ISharedLockbox, ISystemConfigInterop } from "src/L1/SuperchainConfig.sol";

import { DeployUtils } from "scripts/libraries/DeployUtils.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// TODO: Update for the real address once is merged
address constant LOCKBOX = address(uint160(uint256(bytes32("SharedLockbox"))));

contract SuperchainConfigForTest is SuperchainConfig {
    using EnumerableSet for EnumerableSet.UintSet;

    function forTest_addChainOnDependencySet(uint256 _chainId) external {
        _dependencySet.add(_chainId);
    }
}

contract SuperchainConfig_Init_Test is CommonTest {
    /// @dev Tests that initialization sets the correct values. These are defined in CommonTest.sol.
    function test_initialize_unpaused_succeeds() external view {
        assertFalse(superchainConfig.paused());
        assertEq(superchainConfig.guardian(), deploy.cfg().superchainConfigGuardian());
    }

    /// @dev Tests that it can be intialized as paused.
    function test_initialize_paused_succeeds() external {
        IProxy newProxy = IProxy(
            DeployUtils.create1({
                _name: "Proxy",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IProxy.__constructor__, (alice)))
            })
        );
        ISuperchainConfig newImpl = ISuperchainConfig(
            DeployUtils.create1({
                _name: "SuperchainConfig",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(ISuperchainConfig.__constructor__, ()))
            })
        );

        vm.startPrank(alice);
        newProxy.upgradeToAndCall(
            address(newImpl),
            abi.encodeCall(ISuperchainConfig.initialize, (deploy.cfg().superchainConfigGuardian(), true, LOCKBOX))
        );

        assertTrue(ISuperchainConfig(address(newProxy)).paused());
        assertEq(ISuperchainConfig(address(newProxy)).guardian(), deploy.cfg().superchainConfigGuardian());
    }
}

contract SuperchainConfig_Pause_TestFail is CommonTest {
    /// @dev Tests that `pause` reverts when called by a non-guardian.
    function test_pause_notGuardian_reverts() external {
        assertFalse(superchainConfig.paused());

        assertTrue(superchainConfig.guardian() != alice);
        vm.expectRevert("SuperchainConfig: only guardian can pause");
        vm.prank(alice);
        superchainConfig.pause("identifier");

        assertFalse(superchainConfig.paused());
    }
}

contract SuperchainConfig_Pause_Test is CommonTest {
    /// @dev Tests that `pause` successfully pauses
    ///      when called by the guardian.
    function test_pause_succeeds() external {
        assertFalse(superchainConfig.paused());

        vm.expectEmit(address(superchainConfig));
        emit Paused("identifier");

        vm.prank(superchainConfig.guardian());
        superchainConfig.pause("identifier");

        assertTrue(superchainConfig.paused());
    }
}

contract SuperchainConfig_Unpause_TestFail is CommonTest {
    /// @dev Tests that `unpause` reverts when called by a non-guardian.
    function test_unpause_notGuardian_reverts() external {
        vm.prank(superchainConfig.guardian());
        superchainConfig.pause("identifier");
        assertEq(superchainConfig.paused(), true);

        assertTrue(superchainConfig.guardian() != alice);
        vm.expectRevert("SuperchainConfig: only guardian can unpause");
        vm.prank(alice);
        superchainConfig.unpause();

        assertTrue(superchainConfig.paused());
    }
}

contract SuperchainConfig_Unpause_Test is CommonTest {
    /// @dev Tests that `unpause` successfully unpauses
    ///      when called by the guardian.
    function test_unpause_succeeds() external {
        vm.startPrank(superchainConfig.guardian());
        superchainConfig.pause("identifier");
        assertEq(superchainConfig.paused(), true);

        vm.expectEmit(address(superchainConfig));
        emit Unpaused();
        superchainConfig.unpause();

        assertFalse(superchainConfig.paused());
    }
}

contract SuperchainConfig_AddChain_Test is CommonTest {
    event ChainAdded(uint256 indexed chainId, address indexed systemConfig, address indexed portal);

    address internal immutable PORTAL = makeAddr("OptimismPortal");

    function _mockAndExpect(address _target, bytes memory _calldata, bytes memory _returnData) internal {
        vm.mockCall(_target, _calldata, _returnData);
        vm.expectCall(_target, _calldata);
    }

    function test_addChain_reverts_unauthorized(address _caller, uint256 _chainId, address _systemConfig) external {
        vm.assume(_caller != superchainConfig.guardian());

        vm.expectRevert(Unauthorized.selector);
        vm.prank(_caller);
        superchainConfig.addChain(_chainId, _systemConfig);
    }

    function test_addChain_reverts_chainAlreadyExists(uint256 _chainId, address _systemConfig) external {
        SuperchainConfigForTest superchainConfig = new SuperchainConfigForTest();
        superchainConfig.forTest_addChainOnDependencySet(_chainId);

        vm.startPrank(superchainConfig.guardian());
        vm.expectRevert(SuperchainConfig.ChainAlreadyAdded.selector);
        superchainConfig.addChain(_chainId, _systemConfig);
    }

    function test_addChain_succeeds(uint256 _chainId) external {
        vm.assume(!superchainConfig.isInDependencySet(_chainId));

        // Store the PORTAL address we expect to be used in a call in the SystemConfig OptimsimPortal slot
        vm.store(
            address(systemConfig),
            bytes32(uint256(keccak256("systemconfig.optimismportal")) - 1),
            bytes32(uint256(uint160(PORTAL)))
        );

        vm.expectEmit(address(superchainConfig));
        emit ChainAdded(_chainId, address(systemConfig), PORTAL);

        vm.expectCall(address(systemConfig), abi.encodeWithSelector(ISystemConfigInterop.optimismPortal.selector));

        _mockAndExpect(LOCKBOX, abi.encodeWithSelector(ISharedLockbox.authorizePortal.selector, PORTAL), "");

        vm.startPrank(superchainConfig.guardian());
        superchainConfig.addChain(_chainId, address(systemConfig));

        assertTrue(superchainConfig.isInDependencySet(_chainId));
    }

    function test_addChain_succeeds_withMultipleDependencies(uint256 _chainId) external { }
}

contract SuperchainConfig_IsInDependencySet_Test is CommonTest { }

contract SuperchainConfig_DependencySet_Test is CommonTest { }
