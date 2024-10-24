// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { GenerateHashOnion } from "./GenerateHashOnion.s.sol";
import { Test } from "forge-std/Test.sol";

contract GenerateHashOnionForTest is GenerateHashOnion {
    function forTest_setTokensPath(string memory _path) public {
        tokensPath = _path;
    }
}

contract GenerateHashOnion_Test is Test {
    bytes32 internal constant INITIAL_ONION_LAYER = keccak256(abi.encode(0));

    GenerateHashOnionForTest internal script;

    function setUp() public {
        script = new GenerateHashOnionForTest();
    }

    /// @notice Helper function to set a unique remote token address for each local token address.
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

    /// @dev Encodes the local and remote tokens into a JSON format with "pair" keys.
    function _encodeTokensToJson(
        address[] memory _localTokens,
        address[] memory _remoteTokens
    )
        internal
        pure
        returns (string memory _json)
    {
        _json = "["; // Start JSON array
        for (uint256 i = 0; i < _localTokens.length; i++) {
            uint256 _pairId = i + 1;
            // names
            string memory _tokensItem = string.concat(
                '{"id": ',
                vm.toString(_pairId),
                ",",
                '"localToken":"',
                vm.toString(abi.encodePacked(_localTokens[i])),
                '",',
                '"remoteToken":"',
                vm.toString(abi.encodePacked(_remoteTokens[i])),
                '"}'
            );
            // Concatenate the pair item to the JSON, add a comma if it's not the last item
            _json = string.concat(_json, _tokensItem, (i < _localTokens.length - 1) ? "," : "");
        }
        _json = string.concat(_json, "]"); // Close JSON
    }

    /// @notice Test the script reverts when an item in the tokens json file has a repeated token id.
    function test_generateHashOnion_reverts_whenRepeatedId() public {
        string memory _path = string.concat(vm.projectRoot(), "/scripts/hash-onion/test-bad-tokens.json");
        script.forTest_setTokensPath(_path);
        uint256 _id = 1;

        // Create the json file with 2 items with repeated token ids
        string memory _badTokensJson = string.concat(
            '[{"id": ',
            vm.toString(_id),
            ",",
            '"localToken":"',
            vm.toString(abi.encodePacked(address(0))),
            '",',
            '"remoteToken":"',
            vm.toString(abi.encodePacked(address(1))),
            '"},',
            '{"id": ',
            vm.toString(_id),
            ",",
            '"localToken":"',
            vm.toString(abi.encodePacked(address(2))),
            '",',
            '"remoteToken":"',
            vm.toString(abi.encodePacked(address(3))),
            '"}]'
        );

        vm.writeFile(_path, _badTokensJson);

        // vm.expectRevert(GenerateHashOnion.TokenIdAlreadyExists);
        vm.expectRevert(abi.encodeWithSelector(GenerateHashOnion.TokenIdAlreadyExists.selector, _id));

        // Run the script to calculate the hash onion
        script.run();
    }

    /// @notice Test the script reads and parses properly the tokens json file, and hash onion generation.
    ///         This test will only work with the `test-mock-tokens.json` file.
    function test_generateHashOnion_succeeds() public {
        script.forTest_setTokensPath(string.concat(vm.projectRoot(), "/scripts/hash-onion/test-mock-tokens.json"));

        // Calculate the hash onion using the same values than given tokens file.
        bytes32 _hashOnion = INITIAL_ONION_LAYER;
        // Use `_i + 2` so the addresses goes incremental per pair and they are never repeated.
        for (uint256 _i; _i < 10; _i += 2) {
            _hashOnion = keccak256(
                abi.encodePacked(_hashOnion, abi.encodePacked(address(uint160(_i)), address(uint160(_i + 1))))
            );
        }

        // Run the script to calculate the hash onion
        bytes32 _returnedHashOnion = script.run();

        // Assert the returned hash onion is the same as the expected hash onion
        assertEq(_returnedHashOnion, _hashOnion);
    }

    /// @notice Test the script reads and parses properly the tokens json file, and hash onion generation with a fuzz
    ///         test.
    function testFuzz_generateHashOnion_succeeds(address[] memory _localTokens) public {
        string memory _path = string.concat(vm.projectRoot(), "/scripts/hash-onion/fuzz-test-mock-tokens.json");
        script.forTest_setTokensPath(_path);

        vm.assume(_localTokens.length > 0);

        // Set the remote tokens array
        address[] memory _remoteTokens = _setRemoteTokensArray(_localTokens);

        // Calculate the hash onion using the given local and remote tokens
        bytes32 _hashOnion = INITIAL_ONION_LAYER;
        for (uint256 _i; _i < _localTokens.length; _i++) {
            _hashOnion = keccak256(abi.encodePacked(_hashOnion, abi.encodePacked(_localTokens[_i], _remoteTokens[_i])));
        }

        // Write over a json file with the given local and remote tokens
        string memory _tokensJson = _encodeTokensToJson(_localTokens, _remoteTokens);
        vm.writeFile(_path, _tokensJson);

        // Run the script to calculate the hash onion
        bytes32 _returnedHashOnion = script.run();

        // Assert the returned hash onion is the same as the expected hash onion
        assertEq(_returnedHashOnion, _hashOnion);
    }

    /// @notice Test the script reads and parses properly the tokens json file, and hash onion generation with a very
    ///         large array of tokens.
    ///         Make sure to add enough memory with the flag `--memory-limit` to run this test.
    function test_generateHashOnion_succeeds_onVeryLargeArray() public {
        address[] memory _localTokens = new address[](10000);
        for (uint256 _i; _i < _localTokens.length; _i++) {
            _localTokens[_i] = address(uint160(_i));
        }

        testFuzz_generateHashOnion_succeeds(_localTokens);
    }
}
