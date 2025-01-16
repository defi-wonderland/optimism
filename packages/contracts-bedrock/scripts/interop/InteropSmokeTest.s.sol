// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import { Script, console } from "forge-std/Script.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ISuperchainWETH } from "interfaces/L2/ISuperchainWETH.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";
import { IL2ToL2CrossDomainMessenger, Identifier } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

contract InteropSmokeTest is Script {
    string public constant MNEMONIC = "test test test test test test test test test test test junk"; // L2 dev accounts
    uint256 public constant VALUE = 1 ether;
    bytes32 internal constant SENT_MESSAGE_EVENT_SELECTOR =
        0x382409ac69001e11931a28435afef442cbfd20d9891907e8fa373ba7d351f320;

    uint256 public immutable PRIVATE_KEY = vm.deriveKey(MNEMONIC, 0);
    address public immutable DEPLOYER = vm.rememberKey(PRIVATE_KEY);

    // TODO: The following constants can change during execution, so we need to pass them as arguments
    string public constant L2_1_RPC = "http://127.0.0.1:64580";
    string public constant L2_2_RPC = "http://127.0.0.1:64794";
    uint256 public constant L2_1_CHAIN_ID = 2151908;
    uint256 public constant L2_2_CHAIN_ID = 2151909;

    function run() public {
        console.log("Running InteropSmokeTest...");

        wrapSuperchainWETH_FFI();
        (Identifier memory identifier, bytes memory payload) = sendSuperchainWETH_FFI();
        relaySuperchainWETH_FFI(identifier, payload);

        console.log("FINISH...");
    }

    function runOld() public {
        vm.createSelectFork(vm.rpcUrl(L2_1_RPC));
        wrapSuperchainWETH();

        sendSuperchainWETH(L2_2_CHAIN_ID);

        // VmSafe.Log[] memory logs = vm.getRecordedLogs();
        // Identifier memory identifier;
        // bytes memory payload;
        // for (uint256 i = 0; i < logs.length; i++) {
        //     if (logs[i].topics[0] == SENT_MESSAGE_EVENT_SELECTOR) {
        //         identifier = Identifier({
        //             origin: Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
        //             blockNumber: block.number,
        //             logIndex: i,
        //             timestamp: block.timestamp,
        //             chainId: L2_1_CHAIN_ID
        //         });

        //         payload = abi.encodePacked(
        //             abi.encode(SENT_MESSAGE_EVENT_SELECTOR, logs[i].topics[1], logs[i].topics[2], logs[i].topics[3]),
        //             logs[i].data
        //         );
        //     }
        // }

        // console.log("Identifier:");
        // console.log("  Origin: %s", identifier.origin);
        // console.log("  Block number: %s", identifier.blockNumber);
        // console.log("  Log index: %s", identifier.logIndex);
        // console.log("  Timestamp: %s", identifier.timestamp);
        // console.log("  Chain ID: %s", identifier.chainId);
        // console.log("Payload:");
        // console.logBytes(payload);

        vm.createSelectFork(vm.rpcUrl(L2_2_RPC));
        // relaySuperchainWETH(identifier, payload);
    }

    function _wethBalanceOf(address _user) internal view returns (uint256) {
        return ISuperchainWETH(payable(Predeploys.SUPERCHAIN_WETH)).balanceOf(_user);
    }

    function wrapSuperchainWETH_FFI() public {
        vm.createSelectFork(vm.rpcUrl(L2_1_RPC));
        uint256 prevBalance = _wethBalanceOf(DEPLOYER);

        _executeCastSend(
            Predeploys.SUPERCHAIN_WETH,
            "",  // empty calldata for direct value transfer
            L2_1_RPC,
            VALUE,
            false
        );

        vm.createSelectFork(vm.rpcUrl(L2_1_RPC));
        uint256 balance = _wethBalanceOf(DEPLOYER);
        require(balance == prevBalance + VALUE, "InteropSmokeTest: wrapSuperchainWETH balance failed");
    }

    function sendSuperchainWETH_FFI() public returns (Identifier memory identifier, bytes memory payload) {
        vm.createSelectFork(vm.rpcUrl(L2_1_RPC));
        uint256 prevBalance = _wethBalanceOf(DEPLOYER);
        uint256 beforeBlockNumber = block.number;

        _executeCastSend(
            Predeploys.SUPERCHAIN_TOKEN_BRIDGE,
            string.concat(
                "sendERC20(address,address,uint256,uint256) ",
                vm.toString(Predeploys.SUPERCHAIN_WETH), " ",
                vm.toString(DEPLOYER), " ",
                vm.toString(VALUE), " ",
                vm.toString(L2_2_CHAIN_ID)
            ),
            L2_1_RPC,
            0,  // no value
            false
        );

        vm.createSelectFork(vm.rpcUrl(L2_1_RPC));
        uint256 balance = _wethBalanceOf(DEPLOYER);
        require(balance == prevBalance - VALUE, "InteropSmokeTest: sendSuperchainWETH balance failed");

        VmSafe.EthGetLogs[] memory ethLogs = vm.eth_getLogs(
            beforeBlockNumber, block.number, Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, new bytes32[](0)
        );
        VmSafe.EthGetLogs memory log = ethLogs[0];

        // string[] memory params = new string[](1);
        // bytes memory data = vm.rpc(L2_1_RPC, "eth_getBlockByNumber", vm.toString(block.number));
        // console.log("Block data:");
        // console.logBytes(data);

        bytes memory timestampResult = _executeCastBlock(
            log.blockNumber,
            "timestamp",
            L2_1_RPC
        );

        uint256 timestamp = vm.parseUint(vm.split(vm.toString(timestampResult), "x")[1]);
        console.log(timestamp);

        identifier = Identifier({
            origin: Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            blockNumber: log.blockNumber,
            logIndex: log.logIndex,
            timestamp: timestamp,
            chainId: L2_1_CHAIN_ID
        });

        payload = abi.encodePacked(
            abi.encode(SENT_MESSAGE_EVENT_SELECTOR, log.topics[1], log.topics[2], log.topics[3]), log.data
        );

        // vm.createSelectFork(vm.rpcUrl(L2_2_RPC));
        // IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage(identifier, payload);
    }

    function parseTimestamp(string calldata timestampResult) public pure returns (uint256) {
        console.log(timestampResult);
        console.logBytes(bytes(timestampResult[2:]));
        return uint256(bytes32(bytes(timestampResult[2:])));
    }

    function relaySuperchainWETH_FFI(Identifier memory identifier, bytes memory payload) public {
        vm.createSelectFork(vm.rpcUrl(L2_2_RPC));
        uint256 prevBalance = _wethBalanceOf(DEPLOYER);

        bytes memory result = _executeCastSend(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            vm.toString(
                abi.encodeCall(
                    IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage,
                    (identifier, payload)
                )
            ),
            L2_2_RPC,
            0,  // no value
            true
        );

        console.log("Relay result:");
        console.logBytes(result);

        vm.createSelectFork(vm.rpcUrl(L2_2_RPC));
        uint256 balance = _wethBalanceOf(DEPLOYER);
        require(balance == prevBalance + VALUE, "InteropSmokeTest: relaySuperchainWETH balance failed");
    }

    function wrapSuperchainWETH() public {
        uint256 prevBalance = _wethBalanceOf(DEPLOYER);

        vm.startBroadcast(DEPLOYER);

        (bool success,) = Predeploys.SUPERCHAIN_WETH.call{ value: VALUE }("");
        require(success, "InteropSmokeTest: wrapSuperchainWETH failed");

        uint256 balance = _wethBalanceOf(DEPLOYER);
        require(balance == prevBalance + VALUE, "InteropSmokeTest: wrapSuperchainWETH balance failed");

        vm.stopBroadcast();
    }

    function sendSuperchainWETH(uint256 _chainId) public {
        uint256 prevBalance = _wethBalanceOf(DEPLOYER);

        vm.startBroadcast(DEPLOYER);

        uint256 _beforeBlockNumber = block.number;

        vm.recordLogs();
        ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE).sendERC20(
            Predeploys.SUPERCHAIN_WETH, DEPLOYER, VALUE, _chainId
        );

        vm.stopBroadcast();

        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        Identifier memory identifier;
        bytes memory payload;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == SENT_MESSAGE_EVENT_SELECTOR) {
                bytes32[] memory topics = new bytes32[](4);
                topics[0] = SENT_MESSAGE_EVENT_SELECTOR;
                topics[1] = logs[i].topics[1];
                topics[2] = logs[i].topics[2];
                topics[3] = logs[i].topics[3];

                VmSafe.EthGetLogs[] memory ethLogs = vm.eth_getLogs(
                    _beforeBlockNumber, block.number + 10, Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, topics
                );

                identifier = Identifier({
                    origin: Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
                    blockNumber: block.number,
                    logIndex: i,
                    timestamp: block.timestamp,
                    chainId: L2_1_CHAIN_ID
                });

                payload = abi.encodePacked(
                    abi.encode(SENT_MESSAGE_EVENT_SELECTOR, logs[i].topics[1], logs[i].topics[2], logs[i].topics[3]),
                    logs[i].data
                );
            }
        }

        // for (uint256 i = 0; i < logs.length; i++) {
        //     console.log("Block number: %s", logs[i].blockNumber);
        //     console.log("Log index: %s", logs[i].logIndex);
        //     console.logBytes(logs[i].data);
        // }

        uint256 balance = _wethBalanceOf(DEPLOYER);
        require(balance == prevBalance - VALUE, "InteropSmokeTest: sendSuperchainWETH failed");
    }

    function relaySuperchainWETH(Identifier memory _identifier, bytes memory _payload) public {
        uint256 prevBalance = _wethBalanceOf(DEPLOYER);

        vm.startBroadcast(DEPLOYER);

        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage(_identifier, _payload);

        uint256 balance = _wethBalanceOf(DEPLOYER);
        require(balance == prevBalance + VALUE, "InteropSmokeTest: relaySuperchainWETH failed");

        vm.stopBroadcast();
    }

    /// @notice Executes a cast send command via FFI to interact with the blockchain
    /// @dev This is a temporary implementation copied from cast.sol that should be moved to a shared library
    /// @param _target The address of the contract to interact with
    /// @param _calldata The calldata string to be passed to the contract (empty string for direct value transfers)
    /// @param _rpcUrl The RPC endpoint URL to send the transaction to
    /// @param _value The amount of ETH to send with the transaction (in wei)
    /// @param _async Whether to wait for the transaction to be mined (false) or return immediately (true)
    /// @return The raw bytes response from the cast command
    function _executeCastSend(
        address _target,
        string memory _calldata,
        string memory _rpcUrl,
        uint256 _value,
        bool _async
    ) internal returns (bytes memory) {
        // Calculate array size based on whether we have value and async parameters
        uint256 cmdLength = 8;  // base length
        if (_value > 0) cmdLength += 2;  // --value <amount>
        if (_async) cmdLength += 1;      // --async

        string[] memory cmds = new string[](cmdLength);
        uint256 i = 0;
        cmds[i++] = "cast";
        cmds[i++] = "send";
        cmds[i++] = vm.toString(_target);
        if (bytes(_calldata).length > 0) {
            cmds[i++] = _calldata;
        }
        if (_value > 0) {
            cmds[i++] = "--value";
            cmds[i++] = vm.toString(_value);
        }
        cmds[i++] = "--rpc-url";
        cmds[i++] = _rpcUrl;
        cmds[i++] = "--mnemonic";
        cmds[i++] = MNEMONIC;
        if (_async) {
            cmds[i++] = "--async";
        }
        return vm.ffi(cmds);
    }

    /// @notice Executes a cast block command via FFI to get block information
    /// @dev This is a temporary implementation copied from cast.sol that should be moved to a shared library
    /// @param _blockNumber The block number to query
    /// @param _field The block field to retrieve (e.g. timestamp, hash, etc)
    /// @param _rpcUrl The RPC endpoint URL to query
    /// @return The raw bytes response from the cast command
    function _executeCastBlock(
        uint256 _blockNumber,
        string memory _field,
        string memory _rpcUrl
    ) internal returns (bytes memory) {
        string[] memory cmds = new string[](7);
        cmds[0] = "cast";
        cmds[1] = "block";
        cmds[2] = vm.toString(_blockNumber);
        cmds[3] = "--field";
        cmds[4] = _field;
        cmds[5] = "--rpc-url";
        cmds[6] = _rpcUrl;
        return vm.ffi(cmds);
    }
}
