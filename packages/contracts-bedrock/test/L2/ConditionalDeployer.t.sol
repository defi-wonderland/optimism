// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { ConditionalDeployer } from "src/L2/ConditionalDeployer.sol";
import { Config } from "scripts/libraries/Config.sol";
import { Constants } from "src/libraries/Constants.sol";

/// @title ConditionalDeployer_Harness
/// @notice A simple contract harness used for deployment testing of the ConditionalDeployer.
contract ConditionalDeployer_Harness {
    uint256 public immutable value;

    constructor(uint256 _value) {
        value = _value;
    }
}

/// @title ConditionalDeployer_TestInit
/// @notice Reusable test initialization for `ConditionalDeployer` tests.
contract ConditionalDeployer_TestInit is Test {
    // Test contracts
    ConditionalDeployer public conditionalDeployer;
    bytes public simpleContractCreationCode;

    function setUp() public {
        // Create fork
        vm.createSelectFork(Config.forkRpcUrl());

        // Deploy contracts
        conditionalDeployer = new ConditionalDeployer();
        simpleContractCreationCode = type(ConditionalDeployer_Harness).creationCode;
    }
}

/// @title ConditionalDeployer_Deploy_Test
/// @notice Tests the `deploy` function of the `ConditionalDeployer` contract.
contract ConditionalDeployer_Deploy_Test is ConditionalDeployer_TestInit {
    /// @notice Event emitted when an implementation is deployed.
    event ImplementationDeployed(address indexed implementation, bytes32 salt);

    /// @notice Event emitted when deployment is skipped because implementation already exists.
    event ImplementationExists(address indexed implementation);

    /// @notice Tests that `deploy` succeeds and emits the correct event.
    function testFuzz_deploy_succeeds(bytes32 _salt, uint256 _value) public {
        bytes memory _initCode = abi.encodePacked(simpleContractCreationCode, abi.encode(_value));
        bytes32 codeHash = keccak256(_initCode);
        address expectedImplementation = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), conditionalDeployer.DETERMINISTIC_DEPLOYMENT_PROXY(), _salt, codeHash
                        )
                    )
                )
            )
        );

        vm.expectEmit(address(conditionalDeployer));
        emit ImplementationDeployed(expectedImplementation, _salt);

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        address implementation = conditionalDeployer.deploy(0, _salt, _initCode);

        assertEq(implementation, expectedImplementation);
        assertEq(ConditionalDeployer_Harness(implementation).value(), _value);
        assert(implementation.code.length != 0);
    }

    /// @notice Tests that `deploy` succeeds when called by `address(0)`.
    function testFuzz_deploy_fromAddressZero_succeeds(bytes32 _salt, uint256 _value) public {
        bytes memory _initCode = abi.encodePacked(simpleContractCreationCode, abi.encode(_value));

        vm.prank(address(0));
        address implementation = conditionalDeployer.deploy(0, _salt, _initCode);

        assertEq(ConditionalDeployer_Harness(implementation).value(), _value);
        assert(implementation.code.length != 0);
    }

    /// @notice Tests that `deploy` is idempotent and produces the same address when called multiple times.
    function testFuzz_deploy_idempotent_succeeds(bytes32 _salt, uint256 _value) public {
        bytes memory _initCode = abi.encodePacked(simpleContractCreationCode, abi.encode(_value));

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        address implementation1 = conditionalDeployer.deploy(0, _salt, _initCode);

        // Assert that the implementation was deployed
        assert(implementation1.code.length != 0);

        // Attempt to deploy the same implementation again
        vm.expectEmit(address(conditionalDeployer));
        emit ImplementationExists(implementation1);

        vm.prank(Constants.DEPOSITOR_ACCOUNT);
        address implementation2 = conditionalDeployer.deploy(0, _salt, _initCode);

        assertEq(implementation1, implementation2);
    }

    /// @notice Tests that `deploy` reverts when called by an unauthorized address.
    function testFuzz_deploy_unauthorizedCaller_reverts(address _sender) public {
        vm.assume(_sender != Constants.DEPOSITOR_ACCOUNT && _sender != address(0));

        bytes memory _initCode = abi.encodePacked(simpleContractCreationCode, abi.encode(0));

        vm.prank(_sender);
        vm.expectRevert(ConditionalDeployer.ConditionalDeployer_UnauthorizedCaller.selector);
        conditionalDeployer.deploy(0, bytes32(0), _initCode);
    }
}
