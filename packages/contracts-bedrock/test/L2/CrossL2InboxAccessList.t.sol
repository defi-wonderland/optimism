// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { TransientContext } from "src/libraries/TransientContext.sol";

// Target contracts
import {
    CrossL2Inbox,
    Identifier,
    NotEntered,
    NoExecutingDeposits,
    NotDepositor,
    InteropStartAlreadySet,
    NotWarm
} from "src/L2/CrossL2Inbox.sol";
import { IL1BlockInterop } from "interfaces/L2/IL1BlockInterop.sol";

import "forge-std/console.sol";

/// @title CrossL2InboxAccessListTest
/// @dev Contract for testing the CrossL2Inbox contract with access lists.
contract CrossL2InboxAccessListTest is Test {
    string public constant MNEMONIC = "test test test test test test test test test test test junk"; // L2 dev accounts
    uint256 public immutable PRIVATE_KEY = vm.deriveKey(MNEMONIC, 0);
    address public immutable DEPLOYER = vm.rememberKey(PRIVATE_KEY);
    string public constant RPC_URL = "http://127.0.0.1:8545";

    event SendResult(bytes);

    /// @dev CrossL2Inbox contract instance.
    CrossL2Inbox crossL2Inbox;

    /// @dev Sets up the test suite.
    function setUp() public {
        vm.createSelectFork(RPC_URL);

        vm.prank(DEPLOYER);
        crossL2Inbox = new CrossL2Inbox();

        console.log("CrossL2Inbox address", address(crossL2Inbox));

        _executeCastSend(address(0), "", RPC_URL, 0, false, true, new string[](0));
    }

    /// @dev Tests that the validateMessage function succeeds with an access list
    function test_validateMessage_accessList_E2E_succeeds(Identifier calldata _id, bytes32 _messageHash) external {
        string[] memory storageKeys = new string[](1);
        storageKeys[0] = vm.toString(keccak256(abi.encode(_id, _messageHash)));

        _executeCastSend(
            address(crossL2Inbox),
            vm.toString(abi.encodeCall(CrossL2Inbox.validateMessage, (_id, _messageHash))),
            RPC_URL,
            0,
            false,
            false,
            storageKeys
        );
    }

    /// @dev Tests that the validateMessage function reverts without an access list
    function test_validateMessage_withoutAccessList_E2E_reverts(
        Identifier calldata _id,
        bytes32 _messageHash
    )
        external
    {
        (bytes memory _result, bytes memory _error) = _executeCastSend(
            address(crossL2Inbox),
            vm.toString(abi.encodeCall(CrossL2Inbox.validateMessage, (_id, _messageHash))),
            RPC_URL,
            0,
            false,
            false,
            new string[](0)
        );

        assertEq(_result, "");
        assertNotEq(_error, "");
    }

    /// @notice Executes a cast send command via FFI to interact with the blockchain
    /// @dev This is a temporary implementation copied from cast.sol that should be moved to a shared library
    /// @param _target The address of the contract to interact with
    /// @param _calldata The calldata string to be passed to the contract (empty string for direct value transfers)
    /// @param _rpcUrl The RPC endpoint URL to send the transaction to
    /// @param _value The amount of ETH to send with the transaction (in wei)
    /// @param _async Whether to wait for the transaction to be mined (false) or return immediately (true)
    /// @return _result The raw bytes response from the cast command
    /// @return _error The raw bytes error from the cast command
    function _executeCastSend(
        address _target,
        string memory _calldata,
        string memory _rpcUrl,
        uint256 _value,
        bool _async,
        bool _create,
        string[] memory _storageKeys
    )
        internal
        returns (bytes memory _result, bytes memory _error)
    {
        // Calculate array size based on whether we have value and async parameters
        uint256 cmdLength = 9; // base length
        if (bytes(_calldata).length > 0) cmdLength += 1; // _calldata
        if (_value > 0) cmdLength += 2; // --value <amount>
        if (_async) cmdLength += 1; // --async
        if (_create) cmdLength += 1; // --create
        if (_storageKeys.length > 0) cmdLength += (_storageKeys.length + 1); // --access-list

        string[] memory cmds = new string[](cmdLength);
        uint256 i = 0;
        cmds[i++] = "cast";
        cmds[i++] = "send";
        if (!_create) {
            cmds[i++] = vm.toString(_target);
        }
        if (bytes(_calldata).length > 0) cmds[i++] = _calldata;
        if (_value > 0) {
            cmds[i++] = "--value";
            cmds[i++] = vm.toString(_value);
        }
        cmds[i++] = "--rpc-url";
        cmds[i++] = _rpcUrl;
        cmds[i++] = "--mnemonic";
        cmds[i++] = MNEMONIC;
        if (_async) {
            cmds[i++] = "--async";
        }
        cmds[i++] = "--confirmations";
        cmds[i++] = "5";
        if (_create) {
            cmds[i++] = "--create";
            cmds[i++] = vm.toString(type(CrossL2Inbox).creationCode);
        }
        if (_storageKeys.length > 0) {
            cmds[i++] = "--access-list";
            string memory accessListStr = "[{\"address\": \"";
            accessListStr = string.concat(accessListStr, vm.toString(_target));
            accessListStr = string.concat(accessListStr, "\", \"storageKeys\": [");
            for (uint256 j = 0; j < _storageKeys.length; j++) {
                if (j > 0) {
                    accessListStr = string.concat(accessListStr, ",");
                }
                accessListStr = string.concat(accessListStr, "\"");
                accessListStr = string.concat(accessListStr, _storageKeys[j]);
                accessListStr = string.concat(accessListStr, "\"");
            }
            accessListStr = string.concat(accessListStr, "]}]");
            cmds[i++] = accessListStr;
        }

        VmSafe.FfiResult memory result = vm.tryFfi(cmds);
        if (result.exitCode != 0) {
            _error = result.stderr;
        }
        _result = result.stdout;
    }
}
