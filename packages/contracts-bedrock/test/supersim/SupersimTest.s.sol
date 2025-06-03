// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IOwnable } from "interfaces/universal/IOwnable.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { GasTank } from "src/L2/GasTank.sol";
import { L2ToL2CrossDomainMessenger } from "src/L2/L2ToL2CrossDomainMessenger.sol";
import { ICrossL2Inbox, Identifier } from "interfaces/L2/ICrossL2Inbox.sol";

// Step1: supersim --interop.autorelay
// Step2: forge script test/supersim/SupersimTest.s.sol:SupersimTest --broadcast && sleep 10 &&
//forge script test/supersim/SupersimTest.s.sol:CheckBalance --broadcast

interface L2NativeSuperchainERC20 {
    function mint(address _to, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface ITokenBridge {
    function sendERC20(
        address _token,
        address _to,
        uint256 _amount,
        uint256 _chainId
    )
        external
        returns (bytes32 msgHash_);
}

contract GetAdmin is Script {
    function run() public {
        address admin = IProxy(payable(0x4200000000000000000000000000000000000023)).implementation();
        console.log("Admin:", admin);
    }
}

contract SupersimTest is Script {
    function run() public {
        // Configuration for first part
        string memory rpcUrl1 = "http://127.0.0.1:9545";
        vm.createSelectFork(rpcUrl1);
        uint256 deployerPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

        // Contract addresses and parameters
        address superchainERC20 = 0x420beeF000000000000000000000000000000001;
        address tokenBridge = 0x4200000000000000000000000000000000000028;
        address sender = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address recipient = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        uint256 amount = 1000;
        uint256 chainId = 902;

        // Start broadcasting with the private key
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the gas tank
        GasTank gasTank = new GasTank();

        // First mint the tokens
        L2NativeSuperchainERC20(superchainERC20).mint(sender, amount);

        // Then send them cross-chain
        bytes32 msgHash = ITokenBridge(tokenBridge).sendERC20(superchainERC20, recipient, amount, chainId);

        // Flag the message
        gasTank.flag(msgHash);

        vm.stopBroadcast();
    }
}

contract CheckBalance is Script {
    function run() public {
        // Configuration
        string memory rpcUrl = "http://127.0.0.1:9546";
        vm.createSelectFork(rpcUrl);

        // Contract addresses and parameters
        address superchainERC20 = 0x420beeF000000000000000000000000000000001;
        address recipient = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

        // Check balance
        uint256 balance = L2NativeSuperchainERC20(superchainERC20).balanceOf(recipient);
        console.log("Balance of recipient:", balance);
    }
}

contract ClaimMessage is Script {
    function run() public {
        // Configuration
        string memory rpcUrl = "http://127.0.0.1:9545";
        vm.createSelectFork(rpcUrl);

        uint256 relayer_pk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address gasProvider = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

        vm.startBroadcast(relayer_pk);

        // Identifier memory id;
        // id.origin = address(MESSENGER);

        // bytes memory payload =
        //     abi.encode(IGasTank.RelayedMessageGasReceipt.selector, msgHash, rootMsgHash, address(this), relayCost);

        // Claim the message
        // GasTank(0x8464135c8F25Da09e49BC8782676a84730C318bC).claim(Identifier(), gasProvider, "");

        vm.stopBroadcast();
    }
}

// Origin Chain -> Deposit -> SendMessage -> Flag
// Destination Chain -> Relay
// Origin Chain -> Claim
