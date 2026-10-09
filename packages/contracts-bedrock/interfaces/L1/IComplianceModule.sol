// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import { Item } from "src/libraries/BridgeHookItem.sol";

// Interfaces
import { IBridgeHook } from "interfaces/universal/IBridgeHook.sol";
import { IProxyAdminOwnedBase } from "interfaces/universal/IProxyAdminOwnedBase.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";

interface IComplianceModule is IBridgeHook, IProxyAdminOwnedBase {
    event Initialized(uint8 version);
    event Held(bytes32 indexed id, Item item);
    event Cleared(bytes32 indexed id, uint64 at);
    event ClearanceRevoked(bytes32 indexed id);
    event Completed(bytes32 indexed id);
    event PolicySet(address indexed policy);
    event DisabledSet(bool disabled);

    error ComplianceModule_NotPortal();
    error ComplianceModule_NotPolicy();
    error ComplianceModule_NotHeld();
    error ComplianceModule_NotCleared();
    error ComplianceModule_Declined();
    error ComplianceModule_ValueMismatch();
    error ComplianceModule_ZeroAddress();
    error ComplianceModule_Undelivered();

    function version() external pure returns (string memory);
    function initialize(address _policy) external;
    function portal() external view returns (IOptimismPortal2);
    function bridge() external view returns (address);
    function l1CrossDomainMessenger() external view returns (address);
    function policy() external view returns (address);
    function disabled() external view returns (bool);
    function items(bytes32) external view returns (uint64 heldAt, uint64 clearedAt);
    function heldTokens(address, address) external view returns (uint256);
    function heldTokenTotal(address) external view returns (uint256);
    function setPolicy(address _policy) external;
    function setDisabled(bool _disabled) external;
    function recordVerdict(bytes32 _id) external;
    function revokeVerdict(bytes32 _id) external;
    function completeDeposit(Item calldata _item) external;
    function completeWithdrawal(Item calldata _item) external;
    function effectiveParties(Item memory _item) external view returns (address[] memory parties_);

    function __constructor__(IOptimismPortal2 _portal, address _bridge, address _l1CrossDomainMessenger) external;
}
