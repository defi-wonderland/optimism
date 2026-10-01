// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import { Item } from "src/libraries/BridgeHookItem.sol";

// Interfaces
import { IBridgeHook } from "interfaces/universal/IBridgeHook.sol";
import { IProxyAdminOwnedBase } from "interfaces/universal/IProxyAdminOwnedBase.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IL1StandardBridge } from "interfaces/L1/IL1StandardBridge.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";

interface IComplianceModule is IBridgeHook, IProxyAdminOwnedBase {
    event Held(bytes32 indexed id, Item item);
    event Cleared(bytes32 indexed id, uint64 at);
    event ClearanceRevoked(bytes32 indexed id);
    event Completed(bytes32 indexed id);
    event Released(bytes32 indexed id);
    event PolicySet(address indexed policy);

    error ComplianceModule_NotCallSite();
    error ComplianceModule_NotPolicy();
    error ComplianceModule_NotHeld();
    error ComplianceModule_NotCleared();
    error ComplianceModule_ReleaseDeclined();
    error ComplianceModule_Paused();
    error ComplianceModule_ValueMismatch();
    error ComplianceModule_ZeroAddress();

    function version() external pure returns (string memory);
    function initialize(address _policy) external;

    function portal() external view returns (IOptimismPortal2);
    function bridge() external view returns (IL1StandardBridge);
    function l1CrossDomainMessenger() external view returns (ICrossDomainMessenger);
    function policy() external view returns (address);
    function items(bytes32) external view returns (uint64 heldAt, uint64 clearedAt);

    function setPolicy(address _policy) external;
    function recordVerdict(bytes32 _id) external;
    function revokeVerdict(bytes32 _id) external;
    function completeDeposit(Item calldata _item) external;
    function releaseWithdrawal(Item calldata _item) external;
    function effectiveParties(Item memory _item) external view returns (address[] memory parties_);
    function decodeRelayMessage(bytes calldata _data)
        external
        pure
        returns (address sender_, address target_, bytes memory message_);
}
