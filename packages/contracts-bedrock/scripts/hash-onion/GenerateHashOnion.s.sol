// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/Console.sol";
import { IOptimismERC20Factory } from "src/L2/interfaces/IOptimismERC20Factory.sol";

/// @notice Script to generate the hash onion from the tokens json file.
///         * The tokens json file needs to be created on the path specified in the `_tokensPath` function. The keys of
///         the json must be `localToken` and `remoteToken` with the addresses of the tokens. The
///         `test-mock-tokens.json` file can be used as a reference (it's only for testing purposes).
///         * Make sure to don't have any duplicated token ids or duplicated remote token  on the tokens json, there is
///         a check for that to ensure no token pair will accidentaly be overwritten.
///         * Make sure the deployment doesn't already exist on the factory to avoid overwriting.
///         * If running script over a very large amount of tokens, consider increasing the memory limit using the
///         `--memory-limit` flag.
contract GenerateHashOnion is Script {
    /// @notice Error thrown when a token id already exists.
    /// @param id The id of the token that already exists.
    error TokenIdAlreadyExists(uint256 id);

    /// @notice Error thrown when a deployment is already stored on the factory to avoid overwriting.
    /// @param localToken The address of the local token.
    error DeploymentAlreadyStored(address localToken);

    /// @notice Error thrown when a local token is repeated on the given token pairs.
    /// @param localToken The address of the local token.
    error RepeatedLocalToken(address localToken);

    /// @notice Struct to hold the local and remote token addresses.
    /// @param id          The id of the token pair.
    /// @param localToken  Address of the local token.
    /// @param remoteToken Address of the remote token.
    struct TokenPair {
        uint256 id;
        address localToken;
        address remoteToken;
    }

    /// @notice Initial layer of the hash onion.
    bytes32 internal constant INITIAL_ONION_LAYER = keccak256(abi.encode(0));

    IOptimismERC20Factory internal constant FACTORY = IOptimismERC20Factory(0x4200000000000000000000000000000000000012);

    /// @notice Path of the tokens json file.
    string internal tokensPath = string.concat(vm.projectRoot(), "/scripts/hash-onion/tokens.json");

    /// @notice Mapping to check if a token id already exists.
    mapping(uint256 _id => bool _exists) internal tokenIds;

    /// @notice Mapping to check if a remote token already exists on the given token pairs.
    mapping(address _localToken => bool _exists) internal localTokens;

    /// @notice Generates the hash onion from the tokens json file.
    /// @return hashOnion_ The hash onion value.
    function run() public virtual returns (bytes32 hashOnion_) {
        // Read the json of the tokens and parse it
        TokenPair[] memory _tokensPairs = _parseJson(tokensPath);

        // Generate the hash onion and print it
        hashOnion_ = _generateHashOnion(_tokensPairs);
        console.log("Generated hash onion: ");
        console.logBytes32(hashOnion_);
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
    /// @return hashOnion_ The hash onion value.
    function _generateHashOnion(TokenPair[] memory _tokensPairs) internal returns (bytes32 hashOnion_) {
        hashOnion_ = INITIAL_ONION_LAYER;
        for (uint256 _i; _i < _tokensPairs.length; _i++) {
            uint256 _id = _tokensPairs[_i].id;
            address _localToken = _tokensPairs[_i].localToken;

            // Checks to avoid an accidental overwrite on the given token pairs
            if (tokenIds[_id]) revert TokenIdAlreadyExists(_id);
            if (localTokens[_localToken]) revert RepeatedLocalToken(_localToken);
            if (FACTORY.deployments(_localToken) != address(0)) revert DeploymentAlreadyStored(_localToken);

            // Hash the onion with the local and remote token addresses
            hashOnion_ =
                keccak256(abi.encodePacked(hashOnion_, abi.encodePacked(_localToken, _tokensPairs[_i].remoteToken)));

            // Store on the internal mapping to be accessed on subsequent checks
            tokenIds[_id] = true;
            localTokens[_localToken] = true;
        }
    }
}
