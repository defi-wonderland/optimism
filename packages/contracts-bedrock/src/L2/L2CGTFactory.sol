// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { L2CGTBridge } from "src/L2/L2CGTBridge.sol";

// Interfaces
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

/// @title L2CGTFactory
/// @notice Factory contract to deploy the L2CGTBridge contract on L2.
///         This contract is deployed by the L1CGTFactory through cross-domain messaging.
contract L2CGTFactory {
    /// @notice The L2 cross-domain messenger address (predeploy).
    ICrossDomainMessenger public constant L2_MESSENGER =
        ICrossDomainMessenger(0x4200000000000000000000000000000000000007);

    /// @notice Address of the corresponding L1 bridge.
    address public immutable l1CGTBridge;

    /// @notice Address of the L2 bridge owner.
    address public immutable l2BridgeOwner;

    /// @notice Address of the LiquidityController.
    ILiquidityController public immutable liquidityController;

    /// @notice Thrown when the caller is not the expected L1 bridge.
    error L2CGTFactory_OnlyValidSender();

    /// @notice Emitted when the L2CGTBridge is deployed.
    /// @param l2Bridge Address of the deployed L2CGTBridge.
    /// @param l1Bridge Address of the corresponding L1CGTBridge.
    event L2BridgeDeployed(address indexed l2Bridge, address indexed l1Bridge);

    /// @notice Constructs the L2CGTFactory contract.
    /// @param _l1CGTBridge The address of the corresponding L1CGTBridge.
    /// @param _l2BridgeOwner The address of the L2 bridge owner.
    /// @param _liquidityController The address of the LiquidityController contract.
    constructor(address _l1CGTBridge, address _l2BridgeOwner, ILiquidityController _liquidityController) {
        l1CGTBridge = _l1CGTBridge;
        l2BridgeOwner = _l2BridgeOwner;
        liquidityController = _liquidityController;
    }

    /// @notice Deploys the L2CGTBridge contract.
    /// @dev This function is called by the L1CGTFactory through cross-domain messaging.
    ///      The L2 messenger is hardcoded as a constant.
    /// @return The address of the deployed L2CGTBridge.
    function deployL2Bridge() external returns (address) {
        // Only allow calls from the L1 bridge through the L2 messenger
        if (msg.sender != address(L2_MESSENGER) && L2_MESSENGER.xDomainMessageSender() != l1CGTBridge) {
            revert L2CGTFactory_OnlyValidSender();
        }

        // Deploy L2CGTBridge implementation
        address _l2BridgeImpl = address(new L2CGTBridge());

        // Deploy proxy and initialize
        address _l2Bridge = address(
            new ERC1967Proxy(
                _l2BridgeImpl, abi.encodeCall(L2CGTBridge.initialize, (L2_MESSENGER, liquidityController, l1CGTBridge))
            )
        );

        emit L2BridgeDeployed(_l2Bridge, l1CGTBridge);

        return _l2Bridge;
    }
}
