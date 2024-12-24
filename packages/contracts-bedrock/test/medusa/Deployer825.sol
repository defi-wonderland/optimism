// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Contracts
import { CrossL2Inbox } from "src/L2/CrossL2Inbox.sol";
import { L2ToL2CrossDomainMessenger } from "src/L2/L2ToL2CrossDomainMessenger.sol";
import { SuperchainTokenBridge } from "src/L2/SuperchainTokenBridge.sol";
import { SuperchainERC20 } from "src/L2/SuperchainERC20.sol";

contract Deployer825 {
    function deployCrossL2Inbox() public returns (address crossL2Inbox) {
        crossL2Inbox = address(new CrossL2Inbox());
    }

    function deployL2ToL2CrossDomainMessenger() public returns (address l2ToL2CrossDomainMessenger) {
        l2ToL2CrossDomainMessenger = address(new L2ToL2CrossDomainMessenger());
    }

    function deploySuperchainTokenBridge() public returns (address superchainTokenBridge) {
        superchainTokenBridge = address(new SuperchainTokenBridge());
    }

    function deploySuperchainERC20() public returns (address superchainERC20) {
        superchainERC20 = address(new MedusaToken());
    }
}

contract MedusaToken is SuperchainERC20 {
    function name() public pure override returns (string memory) {
        return "MedusaToken";
    }

    /// @dev Returns the symbol of the token.
    function symbol() public pure override returns (string memory) {
        return "MEDUSA";
    }
}
