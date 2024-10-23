// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/Console.sol";

/// @notice Script to generate the hash onion from the tokens json file.
///         The tokens json file needs to be created on the path specified in the `_tokensPath` function. The keys of
///         the json must be `localToken` and `remoteToken` with the addresses of the tokens. The
///         `test-mock-tokens.json` file can be used as a reference (it's only for testing purposes).
contract GenerateHashOnion is Script {
    /// @notice Struct to hold the local and remote token addresses.
    /// @param localToken  Address of the local token.
    /// @param remoteToken Address of the remote token.
    struct TokenPair {
        address localToken;
        address remoteToken;
    }

    /// @notice Initial layer of the hash onion.
    /// keccak256(abi.encode(0));
    bytes32 internal constant INITIAL_ONION_LAYER = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;

    /// @notice Generates the hash onion from the tokens json file.
    /// @return _hashOnion The hash onion value.
    function run() public view virtual returns (bytes32 _hashOnion) {
        // Read the json of the tokens and parse it
        TokenPair[] memory _tokensPairs = _parseJson(_tokensPath());

        // Generate the hash onion and print it
        _hashOnion = _generateHashOnion(_tokensPairs);
        console.log("Generated hash onion: ");
        console.logBytes32(_hashOnion);
    }

    /// @notice Helper function to get the path of the tokens json file.
    ///         Forge must have read permissions allowed to the path.
    /// @return _path Path of the tokens json file.
    function _tokensPath() internal view virtual returns (string memory _path) {
        _path = string.concat(vm.projectRoot(), "/scripts/hash-onion/tokens.json");
    }

    /// @notice Helper function to read and parse the tokens json file.
    /// @param _path Path of the tokens json file.
    /// @return _tokensPairs Array of token pairs.
    function _parseJson(string memory _path) internal view returns (TokenPair[] memory _tokensPairs) {
        string memory _tokensJson = vm.readFile(_path);
        bytes memory _tokensData = vm.parseJson(_tokensJson);
        _tokensPairs = abi.decode(_tokensData, (TokenPair[]));
    }

    /// @notice Helper function to calculate the hash onion from the given arrays of local and remote tokens.
    /// @param _tokensPairs Array of token pairs.
    /// @return _hashOnion The hash onion value.
    function _generateHashOnion(TokenPair[] memory _tokensPairs) internal pure returns (bytes32 _hashOnion) {
        bytes32 _innerLayer = INITIAL_ONION_LAYER;
        for (uint256 _i; _i < _tokensPairs.length; _i++) {
            _innerLayer = keccak256(
                abi.encodePacked(
                    _innerLayer, abi.encodePacked(_tokensPairs[_i].localToken, _tokensPairs[_i].remoteToken)
                )
            );
        }

        _hashOnion = _innerLayer;
    }
}
