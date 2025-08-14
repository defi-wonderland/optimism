// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IL1CGTStandardBridge } from "interfaces/L1/IL1CGTStandardBridge.sol";

interface IL2CGTStandardBridge is ISemver {
    event Initialized(uint8 version);

    event CGTBridgeInitiated(address indexed from, address indexed to, uint256 amount);
    event CGTBridgeFinalized(address indexed from, address indexed to, uint256 amount);

    error InsufficientValue();
    error InvalidRecipient();
    error Paused();
    error OnlyOtherBridge();

    function messenger() external view returns (ICrossDomainMessenger);
    function otherBridge() external view returns (IL1CGTStandardBridge);
    function VERSION() external view returns (string memory);
    function paused() external view returns (bool);
    function initialize(ICrossDomainMessenger _messenger, IL1CGTStandardBridge _otherBridge) external;
    function bridgeCGT(address _to, uint32 _minGasLimit) external payable;
    function finalizeBridgeCGT(address _from, address _to, uint256 _amount) external;
}
