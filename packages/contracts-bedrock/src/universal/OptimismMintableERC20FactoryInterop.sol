// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { OptimismMintableERC20Factory } from "./OptimismMintableERC20Factory.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Unauthorized } from "src/libraries/errors/CommonErrors.sol";

/// @custom:proxied true
/// @custom:predeployed 0x4200000000000000000000000000000000000012
/// @title OptimismMintableERC20FactoryInterop
/// @notice OptimismMintableERC20FactoryInterop is an extension of the OptimismMintableERC20Factory that handles the
/// `deployments` mapping inclusion of the tokens deployed before holocene. It uses a hash onion structure to verify and
/// store the deployments, and can be consired complete when the hash onion is fully peeled.
contract OptimismMintableERC20FactoryInterop is OptimismMintableERC20Factory {
    /// @notice Thwown when the hashOnion is already set.
    error HashOnionAlreadySet();

    /// @notice Thrown when the hashOnion is not set and `verifyAndStore` is called.
    error HashOnionNotSet();

    /// @notice Thrown when the hashOnion is already peeled - meaning that all the deployments are already stored.
    error OnionAlreadyPeelled();

    /// @notice Thrown when the tokens length to verify and store mismatch.
    error TokensLengthMismatch();

    /// @notice Thrown when the computed hash onion with the given tokens and starting inner layer doesn't match the
    /// hashOnion.
    error InvalidHashOnion();

    /// @notice Emitted when a deployment is stored after verifying the tokens against the hashOnion.
    /// @param localToken  Address of the local token.
    /// @param remoteToken Address of the remote token.
    event DeploymentStored(address indexed localToken, address indexed remoteToken);

    /// @notice Storage slot where hashOnion is stored at.
    /// keccak256(abi.encode(uint256(keccak256("hashOnion")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant HASH_ONION_SLOT = 0xae706b81046b35e941cb9737b644ec489aa4690fffd2c3f501ccbed8fd5b0400;

    /// @notice Initial layer on the hash onion.
    /// keccak256(abi.encode(0));
    bytes32 internal constant INITIAL_ONION_LAYER = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;

    /// @notice Semantic version.
    /// @custom:semver +interop
    function version() public pure override returns (string memory) {
        return string.concat(super.version(), "+interop");
    }

    /// @notice hashOnion getter.
    /// @return hashOnion_ The hashOnion value.
    function hashOnion() public view returns (bytes32 hashOnion_) {
        assembly {
            hashOnion_ := HASH_ONION_SLOT
        }
    }

    /// @notice Verifies the hashOnion and stores the provided addresses.
    /// @param _localTokens  Array of local token addresses.
    /// @param _remoteTokens Array of remote token addresses.
    /// @param _startingInnerLayer The starting inner layer of the hashOnion.
    function verifyAndStore(
        address[] calldata _localTokens,
        address[] calldata _remoteTokens,
        bytes32 _startingInnerLayer
    )
        external
    {
        bytes32 _hashOnion = hashOnion();
        if (_hashOnion == 0) revert HashOnionNotSet();
        if (_hashOnion == INITIAL_ONION_LAYER) revert OnionAlreadyPeelled();
        if (_localTokens.length != _remoteTokens.length) revert TokensLengthMismatch();

        // Unpeel the hash onion and store the deployments
        bytes32 innerLayer = _startingInnerLayer;
        for (uint256 i; i < _localTokens.length; i++) {
            innerLayer = keccak256(abi.encodePacked(innerLayer, abi.encodePacked(_localTokens[i], _remoteTokens[i])));
            deployments[_localTokens[i]] = _remoteTokens[i];
            emit DeploymentStored(_localTokens[i], _remoteTokens[i]);
        }

        if (innerLayer != _hashOnion) revert InvalidHashOnion();
        assembly {
            sstore(HASH_ONION_SLOT, _startingInnerLayer)
        }
    }

    /// @notice One-time setter for the hashOnion value to be called by the ProxyAdmin.
    /// @param _onionHash The new hashOnion value.
    function setOnionHash(bytes32 _onionHash) external {
        if (msg.sender != Predeploys.PROXY_ADMIN) revert Unauthorized();
        if (hashOnion() != 0) revert HashOnionAlreadySet();

        assembly {
            sstore(HASH_ONION_SLOT, _onionHash)
        }
    }
}
