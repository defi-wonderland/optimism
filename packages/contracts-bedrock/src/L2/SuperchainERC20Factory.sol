// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ISemver } from "src/universal/ISemver.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IL2ToL2CrossDomainMessenger } from "src/L2/IL2ToL2CrossDomainMessenger.sol";
import { ICrossDomainMessenger } from "@openzeppelin/contracts/vendor/optimism/ICrossDomainMessenger.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { CREATE3 } from "@rari-capital/solmate/src/utils/CREATE3.sol";

/// @notice Thrown when attempting to deploy a SuperchainERC20 from L1 and the caller is not the L2CrossDomainMessenger.
error CallerNotL2CrossDomainMessenger();

/// @notice Thrown when attempting to deploy a SuperchainERC20 from L1 and the xDomainMessageSender is not the native
/// initializer.
error InvalidNativeInitializer();

/// @notice Thrown when attempting to deploy a SuperchainERC20 from L2 and the caller is not the
/// L2ToL2CrossDomainMessenger.
error CallerNotL2ToL2CrossDomainMessenger();

/// @notice Thrown when attempting to deploy a SuperchainERC20 from L2 and the crossDomainMessageSender is not the
/// SuperchainERC20Factory
error InvalidCrossDomainSender();

/// @notice Thrown when attempting to deploy a SuperchainERC20 and the deployment already exists.
error AlreadyDeployed(address _remoteToken);

/// @notice Thrown when attempting to deploy a SuperchainERC20 with metadata and the deployment does not exist.
error NotDeployed();

/// @custom:proxied
/// @title SuperchainERC20Factory
/// @notice SuperchainERC20Factory is a factory contract that deploys SuperchainERC20 Beacon Proxies using CREATE3.
contract SuperchainERC20Factory is ISemver {
    /// TODO: Replace with real native initializer address
    /// @notice Address of the native initializer.
    address internal constant NATIVE_INITIALIZER = 0x0000000000000000000000000000000000000000;

    /// @notice Address of the L2CrossDomainMessenger Predeploy.
    address internal constant L2_CROSS_DOMAIN_MESSENGER = Predeploys.L2_CROSS_DOMAIN_MESSENGER;

    /// @notice Address of the L2ToL2CrossDomainMessenger Predeploy.
    address internal constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    /// @notice Address of the SuperchainERC20Beacon Predeploy.
    address internal constant SUPERCHAIN_ERC20_BEACON = Predeploys.SUPERCHAIN_ERC20_BEACON;

    /// @notice Deployment data for a SuperchainERC20.
    struct DeploymentData {
        address superchainERC20;
        uint8 decimals;
        string name;
        string symbol;
    }

    /// @notice Mapping of remote token address to deployment data.
    mapping(address => DeploymentData) public deploymentsData;

    /// @notice Emitted when a SuperchainERC20 is deployed.
    /// @param superchainERC20 Address of the SuperchainERC20 deployment.
    /// @param remoteToken Address of the remote token.
    /// @param decimals Decimals of the SuperchainERC20.
    /// @param name Name of the SuperchainERC20.
    /// @param symbol Symbol of the SuperchainERC20.
    event SuperchainERC20Deployed(
        address indexed superchainERC20, address indexed remoteToken, uint8 decimals, string name, string symbol
    );

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Deploys a SuperchainERC20 from L1.
    /// @param _remoteToken Address of the remote token.
    /// @param _decimals Decimals of the remote token.
    /// @param _name Name of the remote token.
    /// @param _symbol Symbol of the remote token.
    /// @return Address of the SuperchainERC20 deployment.
    function deployFromL1(
        address _remoteToken,
        uint8 _decimals,
        string memory _name,
        string memory _symbol
    )
        external
        returns (address)
    {
        if (msg.sender != L2_CROSS_DOMAIN_MESSENGER) revert CallerNotL2CrossDomainMessenger();

        if (ICrossDomainMessenger(L2_CROSS_DOMAIN_MESSENGER).xDomainMessageSender() != NATIVE_INITIALIZER) {
            revert InvalidNativeInitializer();
        }

        // Generate Superchain metadata
        string memory _superName = string.concat("Super", _name);
        string memory _superSymbol = string.concat("S-", _symbol);

        return _deploy(_remoteToken, _decimals, _superName, _superSymbol);
    }

    /// @notice Deploys a SuperchainERC20 from another L2.
    /// @param _remoteToken Address of the remote token.
    /// @param _decimals Decimals of the SuperchainERC20.
    /// @param _name Name of the SuperchainERC20.
    /// @param _symbol Symbol of the SuperchainERC20.
    /// @return Address of the SuperchainERC20 deployment.
    function deployFromL2(
        address _remoteToken,
        uint8 _decimals,
        string memory _name,
        string memory _symbol
    )
        external
        returns (address)
    {
        if (msg.sender != L2_TO_L2_CROSS_DOMAIN_MESSENGER) revert CallerNotL2CrossDomainMessenger();

        if (IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).crossDomainMessageSender() != address(this)) {
            revert InvalidCrossDomainSender();
        }

        return _deploy(_remoteToken, _decimals, _name, _symbol);
    }

    /// @notice Deploys a SuperchainERC20 Beacon Proxy using CREATE3.
    /// @param _remoteToken Address of the remote token.
    /// @param _decimals Decimals of the SuperchainERC20.
    /// @param _name Name of the SuperchainERC20.
    /// @param _symbol Symbol of the SuperchainERC20.
    /// @return _superchainERC20 Address of the SuperchainERC20 deployment.
    function _deploy(
        address _remoteToken,
        uint8 _decimals,
        string memory _name,
        string memory _symbol
    )
        internal
        returns (address _superchainERC20)
    {
        // Revert if the deployment already exists
        if (deploymentsData[_remoteToken].superchainERC20 != address(0)) revert AlreadyDeployed(_remoteToken);

        // Encode the BeaconProxy creation code with the beacon contract address and metadata
        bytes memory _creationCode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(SUPERCHAIN_ERC20_BEACON, abi.encode(_remoteToken, _decimals, _name, _symbol))
        );

        // Use CREATE3 for deterministic deployment
        bytes32 salt = keccak256(abi.encode(_remoteToken));
        _superchainERC20 = CREATE3.deploy({ salt: salt, creationCode: _creationCode, value: 0 });

        // Store SuperchainERC20 address and metadata
        deploymentsData[_remoteToken] = DeploymentData(_superchainERC20, _decimals, _name, _symbol);

        emit SuperchainERC20Deployed(_superchainERC20, _remoteToken, _decimals, _name, _symbol);
    }

    /// @notice Deploys a SuperchainERC20 from L2 with storage metadata.
    /// @param _remoteToken Address of the remote token.
    /// @param _chainIds Chain IDs to deploy to.
    function deployWithMetadata(address _remoteToken, uint256[] memory _chainIds) external {
        DeploymentData memory _metadata = deploymentsData[_remoteToken];

        // Revert if the deployment does not exist
        if (_metadata.superchainERC20 == address(0)) revert NotDeployed();

        // Encode the deployFromL2 call with the remote token and metadata
        bytes memory _message =
            abi.encodeCall(this.deployFromL2, (_remoteToken, _metadata.decimals, _metadata.name, _metadata.symbol));

        // Send the message to each chain ID
        for (uint256 i; i < _chainIds.length;) {
            IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER).sendMessage({
                _destination: _chainIds[i],
                _target: address(this),
                _message: _message
            });

            unchecked {
                ++i;
            }
        }
    }
}
