// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/Console.sol";

/// @notice Script to generate the hash onion from the tokens json file.
///         * The tokens json file needs to be created on the path specified in the `_tokensPath` function. The keys of
///         the json must be `localToken` and `remoteToken` with the addresses of the tokens. The
///         `test-mock-tokens.json` file can be used as a reference (it's only for testing purposes).
///         * Make sure to don't have duplicated token ids, there is a check for that to ensure no token pair will
///         accidentaly be overwritten.
///         * If running script over a very large amount of tokens, consider increasing the memory limit using the
///         `--memory-limit` flag.
contract GenerateHashOnion is Script {
    /// @notice Error emitted when a token id already exists.
    /// @param id The id of the token that already exists.
    error TokenIdAlreadyExists(uint256 id);

    /// @notice Struct to hold the local and remote token addresses.
    /// @param localToken  Address of the local token.
    /// @param remoteToken Address of the remote token.
    struct TokenPair {
        uint256 id;
        address localToken;
        address remoteToken;
    }

    /// @notice Initial layer of the hash onion.
    bytes32 internal constant INITIAL_ONION_LAYER = keccak256(abi.encode(0));

    /// @notice Path of the tokens json file.
    string internal tokensPath = string.concat(vm.projectRoot(), "/scripts/hash-onion/tokens.json");

    /// @notice Mapping to check if a token id already exists.
    mapping(uint256 _id => bool _exists) internal tokenIds;

    /// @notice Generates the hash onion from the tokens json file.
    /// @return _hashOnion The hash onion value.
    function run() public virtual returns (bytes32 _hashOnion) {
        // Read the json of the tokens and parse it
        TokenPair[] memory _tokensPairs = _parseJson(tokensPath);

        // Generate the hash onion and print it
        _hashOnion = _generateHashOnion(_tokensPairs);
        console.log("Generated hash onion: ");
        console.logBytes32(_hashOnion);
    }

    /// @notice Helper function to read and parse the tokens json file.
    /// @param _path Path of the tokens json file.
    /// @return _tokensPairs Array of token pairs.
    function _parseJson(string memory _path) internal view returns (TokenPair[] memory _tokensPairs) {
        string memory _tokensData = vm.readFile(_path);
        bytes memory _tokensJson = vm.parseJson(_tokensData);
        _tokensPairs = abi.decode(_tokensJson, (TokenPair[]));
    }

    /// @notice Helper function to calculate the hash onion from the given arrays of local and remote tokens.
    /// @param _tokensPairs Array of token pairs.
    /// @return _hashOnion The hash onion value.
    function _generateHashOnion(TokenPair[] memory _tokensPairs) internal returns (bytes32 _hashOnion) {
        _hashOnion = INITIAL_ONION_LAYER;
        for (uint256 _i; _i < _tokensPairs.length; _i++) {
            if (tokenIds[_tokensPairs[_i].id]) revert TokenIdAlreadyExists(_tokensPairs[_i].id);

            // Hash the onion with the local and remote token addresses
            _hashOnion = keccak256(
                abi.encodePacked(
                    _hashOnion, abi.encodePacked(_tokensPairs[_i].localToken, _tokensPairs[_i].remoteToken)
                )
            );

            tokenIds[_tokensPairs[_i].id] = true;
        }
    }
}
