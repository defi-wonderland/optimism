// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { L1CGTBridge } from "src/L1/L1CGTBridge.sol";
import { L2CGTFactory } from "src/L2/L2CGTFactory.sol";

// Libraries
import { CrossChainDeployments } from "src/libraries/CrossChainDeployments.sol";
import { Features } from "src/libraries/Features.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { CrossChainDeployments } from "src/libraries/CrossChainDeployments.sol";
import { Features } from "src/libraries/Features.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @title L1CGTFactory
/// @notice Factory contract to deploy and setup the L1CGTBridge contract on L1, and
///         triggers the deployment of the L2 factory and L2 bridge contracts.
/// @dev The salt is always different for each deployed instance of this contract on the L1 Factory,
///      and the L2 contracts are deployed with CREATE to guarantee that the addresses are unique
///      among all the L2s, avoiding scenarios where L2 contracts have the same address on different
///      L2s when triggered by different owners.
contract L1CGTFactory is ProxyAdminOwnedBase, ReinitializableBase, Initializable, ISemver {
    /// @notice The L2 CREATE2 deployer address.
    address public constant L2_CREATE2_DEPLOYER = 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2;

    /// @notice The L2 bridge proxy is the first deployment from the L2 factory, so nonce is 1.
    uint256 internal constant _L2_BRIDGE_DEPLOYMENT_NONCE = 1;

    /// @notice The CGT token address.
    /// @custom:network-specific
    IERC20 public cgtToken;

    /// @notice The deployments salt counter.
    uint256 public deploymentsSaltCounter;

    /// @notice Reserve extra slots in the storage layout for future upgrades.
    uint256[48] private __gap;

    /// @notice Thrown when trying to deploy while Custom Gas Token mode is not enabled.
    error L1CGTFactory_CustomGasTokenNotEnabled();

    /// @notice Emitted when the protocol is deployed.
    /// @param l1Bridge Address of the deployed L1CGTBridge.
    /// @param l2Factory Address of the deployed L2CGTFactory.
    /// @param l2Bridge Address of the deployed L2CGTBridge.
    event ProtocolDeployed(address indexed l1Bridge, address indexed l2Factory, address indexed l2Bridge);

    /// @notice Struct containing L2 deployment parameters.
    /// @dev This struct is used to store the deployment parameters for the L2 factory and bridge.
    /// @param l2BridgeOwner The address of the L2 bridge owner.
    /// @param liquidityController The address of the L2 LiquidityController contract.
    /// @param minGasLimitDeploy The minimum gas limit for the L2 factory deployment.
    /// @param minGasLimitBridge The minimum gas limit for the L2 bridge deployment.
    struct L2Deployments {
        address l2BridgeOwner;
        address liquidityController;
        uint32 minGasLimitDeploy;
        uint32 minGasLimitBridge;
    }

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    function version() public pure returns (string memory) {
        return "1.0.0";
    }

    /// @notice Constructs the L1CGTFactory contract.
    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Initializes the L1CGTFactory contract.
    /// @param _cgtToken The address of the CGT token contract.
    function initialize(IERC20 _cgtToken) external reinitializer(initVersion()) {
        // Initialization transactions must come from the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        cgtToken = _cgtToken;
    }

    /// @notice Deploys the L1 bridge and triggers L2 deployments.
    /// @param _l1Messenger The address of the L1 messenger for the L2 Op chain.
    /// @param _superchainConfig The address of the SuperchainConfig contract.
    /// @param _systemConfig The address of the SystemConfig contract.
    /// @param _l1BridgeOwner The address of the owner of the L1 bridge.
    /// @param _chainName The name of the L2 Op chain.
    /// @param _l2Deployments The deployments data for the L2 factory and bridge.
    /// @return _l1Bridge The address of the L1 bridge.
    /// @return _l2Factory The address of the L2 factory.
    /// @return _l2Bridge The address of the L2 bridge.
    function deploy(
        ICrossDomainMessenger _l1Messenger,
        ISuperchainConfig _superchainConfig,
        ISystemConfig _systemConfig,
        address _l1BridgeOwner,
        string calldata _chainName,
        L2Deployments calldata _l2Deployments
    )
        external
        returns (address _l1Bridge, address _l2Factory, address _l2Bridge)
    {
        // Only allow ProxyAdmin or ProxyAdmin owner to deploy
        _assertOnlyProxyAdminOrProxyAdminOwner();

        // Only allow deployment when Custom Gas Token mode is enabled
        _assertCustomGasTokenEnabled(_systemConfig);

        // Update the salt counter and get current nonce
        uint256 _currentNonce = deploymentsSaltCounter += 2;

        // Precalculate the L1 bridge proxy address
        _l1Bridge = CrossChainDeployments.precalculateCreateAddress(address(this), _currentNonce);

        // Deploy L2 factory through cross-domain messaging
        _l2Factory = CrossChainDeployments.deployL2Factory(
            abi.encodePacked(
                type(L2CGTFactory).creationCode,
                abi.encode(_l1Bridge, _l2Deployments.l2BridgeOwner, _l2Deployments.liquidityController)
            ),
            bytes32(_currentNonce),
            address(_l1Messenger),
            L2_CREATE2_DEPLOYER,
            _l2Deployments.minGasLimitDeploy
        );

        // Precalculate the L2 bridge address
        _l2Bridge = CrossChainDeployments.precalculateCreateAddress(_l2Factory, _L2_BRIDGE_DEPLOYMENT_NONCE);

        // Send message to deploy L2 bridge
        _l1Messenger.sendMessage({
            _target: _l2Factory,
            _message: abi.encodeCall(L2CGTFactory.deployL2Bridge, ()),
            _minGasLimit: _l2Deployments.minGasLimitBridge
        });

        // Deploy L1 bridge implementation and proxy
        address _l1BridgeImpl = address(new L1CGTBridge());
        new ERC1967Proxy(
            _l1BridgeImpl,
            abi.encodeCall(L1CGTBridge.initialize, (_l1Messenger, _superchainConfig, cgtToken, _l2Bridge))
        );

        emit ProtocolDeployed(_l1Bridge, _l2Factory, _l2Bridge);
    }

    /// @notice Asserts that Custom Gas Token mode is enabled.
    /// @param _systemConfig The SystemConfig contract to check.
    function _assertCustomGasTokenEnabled(ISystemConfig _systemConfig) internal view {
        // Check if Custom Gas Token feature is enabled in the SystemConfig
        if (!_systemConfig.isFeatureEnabled(Features.CUSTOM_GAS_TOKEN)) {
            revert L1CGTFactory_CustomGasTokenNotEnabled();
        }
    }
}
