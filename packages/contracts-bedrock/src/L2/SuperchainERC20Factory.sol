// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ISemver } from "src/universal/ISemver.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { CREATE3 } from "@rari-capital/solmate/src/utils/CREATE3.sol";

/// @custom:proxied
/// @title SuperchainERC20Factory
/// @notice SuperchainERC20Factory is a factory contract that deploys SuperchainERC20 Beacon Proxies using CREATE3.
contract SuperchainERC20Factory is ISemver {
    /// @notice Mapping of the deployed SuperchainERC20 to the remote token address.
    mapping(address superchainToken => address remoteToken) public deployments;

    /// @notice Emitted when a SuperchainERC20 is deployed.
    /// @param superchainERC20 Address of the SuperchainERC20 deployment.
    /// @param remoteToken Address of the remote token.
    /// @param name Name of the SuperchainERC20.
    /// @param symbol Symbol of the SuperchainERC20.
    /// @param decimals Decimals of the SuperchainERC20.
    event SuperchainERC20Deployed(
        address indexed superchainERC20, address indexed remoteToken, string name, string symbol, uint8 decimals
    );

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Deploys a SuperchainERC20 Beacon Proxy using CREATE3.
    /// @param _remoteToken Address of the remote token.
    /// @param _name Name of the SuperchainERC20.
    /// @param _symbol Symbol of the SuperchainERC20.
    /// @param _decimals Decimals of the SuperchainERC20.
    /// @return _superchainERC20 Address of the SuperchainERC20 deployment.
    function deploy(
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        external
        returns (address _superchainERC20)
    {
        // Encode the BeaconProxy creation code with the beacon contract address and metadata
        bytes memory _creationCode = bytes.concat(
            type(BeaconProxy).creationCode,
            abi.encode(Predeploys.SUPERCHAIN_ERC20_BEACON, abi.encode(_remoteToken, _name, _symbol, _decimals))
        );

        // Use CREATE3 for deterministic deployment
        // bytes32 _salt = keccak256(abi.encode(_remoteToken, _name, _symbol, _decimals));
        bytes32 _salt = bytes32(abi.encode(_remoteToken, _name, _symbol, _decimals));
        _superchainERC20 = CREATE3.deploy({ salt: _salt, creationCode: _creationCode, value: 0 });

        // Store SuperchainERC20 and remote token addresses
        deployments[_superchainERC20] = _remoteToken;

        emit SuperchainERC20Deployed(_superchainERC20, _remoteToken, _name, _symbol, _decimals);
    }
}
