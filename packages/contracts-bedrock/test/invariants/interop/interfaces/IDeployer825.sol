// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDeployer825 {
    function deployCrossL2Inbox() external returns (address crossL2Inbox);

    function deployL2ToL2CrossDomainMessenger() external returns (address l2ToL2CrossDomainMessenger);

    function deploySuperchainTokenBridge() external returns (address superchainTokenBridge);

    function deploySuperchainERC20() external returns (address superchainERC20);
}
