// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Vm, VmSafe } from "forge-std/Vm.sol";
import { Identifier } from "src/L2/CrossL2Inbox.sol";
import { CrossL2Inbox } from "src/L2/CrossL2Inbox.sol";
import { Hashing } from "src/libraries/Hashing.sol";

// Contracts
import { GasTank } from "./contracts/GasTank.sol";
import { L2ToL2CrossDomainMessenger } from "./contracts/L2ToL2CrossDomainMessenger.sol";

// Constants
string constant ORIGIN_CHAIN_RPC_URL = "http://127.0.0.1:9545";
string constant DESTINATION_CHAIN_RPC_URL = "http://127.0.0.1:9546";
uint256 constant ORIGIN_CHAIN_ID = 901;
uint256 constant DESTINATION_CHAIN_ID = 902;

address constant MESSENGER = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
address constant GAS_TANK = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;

// Private Keys Addresses
uint256 constant DEPLOYER_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
uint256 constant MESSAGE_SENDER_PRIVATE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
address constant MESSAGE_SENDER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
uint256 constant RELAYER_PRIVATE_KEY = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
address constant RELAYER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

// forge script test/supersim/GasTank.t.sol:SetUp --broadcast
contract SetUp is Script {
    function run() public {
        // Deploy GasTank and Custom L2ToL2CrossDomainMessenger on Origin Chain
        vm.createSelectFork(ORIGIN_CHAIN_RPC_URL);
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        L2ToL2CrossDomainMessenger originMessenger = new L2ToL2CrossDomainMessenger();
        GasTank gasTank = new GasTank();
        vm.stopBroadcast();

        // Deploy Custom L2ToL2CrossDomainMessenger on Destination Chain
        vm.createSelectFork(DESTINATION_CHAIN_RPC_URL);
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        L2ToL2CrossDomainMessenger destinationMessenger = new L2ToL2CrossDomainMessenger();
        vm.stopBroadcast();

        // Console log the addresses
        console.log("GasTank:", address(gasTank)); //0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
        console.log("Origin L2ToL2CrossDomainMessenger:", address(originMessenger)); //0x5FbDB2315678afecb367f032d93F642f64180aa3
        console.log("Destination L2ToL2CrossDomainMessenger:", address(destinationMessenger)); //0x5FbDB2315678afecb367f032d93F642f64180aa3
    }
}

// forge script test/supersim/GasTank.t.sol:SendMessage --broadcast
contract SendMessage is Script {
    function run() public {
        vm.createSelectFork(ORIGIN_CHAIN_RPC_URL);
        vm.startBroadcast(MESSAGE_SENDER_PRIVATE_KEY);

        // Send a message from the message sender to the destination chain
        vm.recordLogs();
        bytes32 messageHash =
            L2ToL2CrossDomainMessenger(MESSENGER).sendMessage(DESTINATION_CHAIN_ID, MESSAGE_SENDER, "Hello, world!");
        vm.getRecordedLogs();

        // Deposit funds to the gas tank and flag the message
        GasTank(GAS_TANK).deposit{ value: 0.01 ether }(MESSAGE_SENDER);
        GasTank(GAS_TANK).flag(messageHash);

        // Log Block Number  and Timestamp
        console.log("Block Number:", vm.getBlockNumber());
        console.log("Timestamp:", vm.getBlockTimestamp());

        vm.stopBroadcast();
    }
}

// forge script test/supersim/GasTank.t.sol:RelayMessage --broadcast -vvvvv
contract RelayMessage is Script {
    /// forge-config: default.isolate = true
    function run() public {
        bytes32 messagePayloadHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: 902,
            _source: 901,
            _nonce: 0,
            _sender: MESSAGE_SENDER,
            _target: MESSAGE_SENDER,
            _message: "Hello, world!"
        });

        Identifier memory id = Identifier(0x5FbDB2315678afecb367f032d93F642f64180aa3, 17, 0, 1748964872, 901);

        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, 902, MESSAGE_SENDER, 0), // topics
            abi.encode(MESSAGE_SENDER, "Hello, world!", abi.encode(1, messagePayloadHash)) // data
        );

        CrossL2Inbox crossL2Inbox = CrossL2Inbox(0x4200000000000000000000000000000000000022);

        bytes32 _messageHash = 0x84b307dc05cf0fe6a756cf78a142e8cdbd55950dd6138da98e817b4aae394cca;

        bytes32 slot_ = calculateChecksum(id, _messageHash);
        bytes32[] memory slots = new bytes32[](1);
        slots[0] = slot_;
        VmSafe.AccessListItem[] memory accessList = new VmSafe.AccessListItem[](1);
        accessList[0] = VmSafe.AccessListItem({ target: address(crossL2Inbox), storageKeys: slots });

        vm.createSelectFork(DESTINATION_CHAIN_RPC_URL);
        vm.startBroadcast(RELAYER_PRIVATE_KEY);
        vm.accessList(accessList);
        L2ToL2CrossDomainMessenger(MESSENGER).relayMessage(id, sentMessage);
        vm.stopBroadcast();
    }

    function calculateChecksum(Identifier memory _id, bytes32 _msgHash) internal pure returns (bytes32 checksum_) {
        bytes32 _MSB_MASK = bytes32(~uint256(0xff << 248));
        bytes32 _TYPE_3_MASK = bytes32(uint256(0x03 << 248));

        // Hash the origin address and message hash together
        bytes32 logHash = keccak256(abi.encodePacked(_id.origin, _msgHash));

        // Downsize the identifier fields to match the needed type for the custom checksum calculation.
        uint64 blockNumber = uint64(_id.blockNumber);
        uint64 timestamp = uint64(_id.timestamp);
        uint32 logIndex = uint32(_id.logIndex);

        // Pack identifier fields with a left zero padding (uint96(0))
        bytes32 idPacked = bytes32(abi.encodePacked(uint96(0), blockNumber, timestamp, logIndex));

        // Hash the logHash with the packed identifier data
        bytes32 idLogHash = keccak256(abi.encodePacked(logHash, idPacked));

        // Create the final hash by combining idLogHash with chainId
        bytes32 bareChecksum = keccak256(abi.encodePacked(idLogHash, _id.chainId));

        // Apply bit masking to create the final checksum
        checksum_ = (bareChecksum & _MSB_MASK) | _TYPE_3_MASK;
    }
}

contract ClaimMessage is Script {
    function run() public {
        vm.startBroadcast();

        vm.stopBroadcast();
    }
}
