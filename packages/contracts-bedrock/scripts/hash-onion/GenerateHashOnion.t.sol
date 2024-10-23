// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { GenerateHashOnion } from "./GenerateHashOnion.s.sol";
import { Test } from "forge-std/Test.sol";

contract GenerateHashOnionForTest is GenerateHashOnion {
    /// @notice Override the tokens path to the test mock tokens json file.
    /// @notice The test mock tokens json file is used for testing purposes only.
    function _tokensPath() internal view override returns (string memory _path) {
        _path = string.concat(vm.projectRoot(), "/scripts/hash-onion/test-mock-tokens.json");
    }
}

contract GenerateHashOnion_Test is Test {
    bytes32 internal constant INITIAL_ONION_LAYER = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;

    GenerateHashOnionForTest internal script;

    function setUp() public {
        script = new GenerateHashOnionForTest();
    }

    /// @notice Test the script reads and parses properly the tokens json file, and hash onion generation.
    function test_generateHashOnion() public {
        // Calculate the hash onion using the same values than given tokens file.
        bytes32 _innerLayer = INITIAL_ONION_LAYER;
        // Use `_i + 2` so the addresses goes incremental per pair and they are never repeated.
        for (uint256 _i; _i < 10; _i += 2) {
            _innerLayer = keccak256(
                abi.encodePacked(_innerLayer, abi.encodePacked(address(uint160(_i)), address(uint160(_i + 1))))
            );
        }
        bytes32 _expectedHashOnion = _innerLayer;

        // Run the script to calculate the hash onion
        bytes32 _returnedHashOnion = script.run();

        // Assert the returned hash onion is the same as the expected hash onion
        assertEq(_returnedHashOnion, _expectedHashOnion);
    }
}
