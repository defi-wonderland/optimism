// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import { Script, console } from "forge-std/Script.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ISuperchainWETH } from "interfaces/L2/ISuperchainWETH.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";
import { IL2ToL2CrossDomainMessenger, Identifier } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { IL2StandardBridge } from "interfaces/L2/IL2StandardBridge.sol";
import { OptimismPortal } from "src/L1/OptimismPortal.sol";
import { L2OutputOracle } from "src/L1/L2OutputOracle.sol";
import { DisputeGameFactory } from "src/dispute/DisputeGameFactory.sol";
import { Types } from "src/libraries/Types.sol";

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
    string public constant L1_RPC = "http://127.0.0.1:8545";
    uint256 public constant L1_CHAIN_ID = 900;

    /// @notice Main entry point for the interop smoke test
    /// @dev This function tests the full flow of wrapping ETH into SuperchainWETH,
    ///      sending it cross-chain, and relaying the message on the destination chain
    function run() public {
        // Log the start of the test
        console.log("Running InteropSmokeTest...");

        // Step 1: Wrap native ETH into SuperchainWETH on the source chain
        wrapSuperchainWETH_FFI();

        // Step 2: Send the SuperchainWETH to the destination chain
        // Returns the message identifier and payload needed for relaying
        (Identifier memory identifier, bytes memory payload) = sendSuperchainWETH_FFI();

        // Step 3: Relay the message on the destination chain to complete the transfer
        relaySuperchainWETH_FFI(identifier, payload);

        // Step 4: Unwrap the SuperchainWETH on the destination chain
        unwrapSuperchainWETH_FFI();

        // Step 5: Withdraw the native ETH from the destination chain to L1
        (bytes32 withdrawalHash, Types.WithdrawalTransaction memory withdrawalTx) = withdrawETH_FFI();

        // Step 6: Finalize the withdrawal on L1
        finalizeWithdrawalOnL1_FFI(withdrawalHash, withdrawalTx);

        // Log completion
        console.log("FINISH...");
    }

    /// @notice Wraps native ETH into SuperchainWETH on the source chain
    /// @dev Uses FFI to execute a cast send command that wraps ETH by sending value directly to the Super WETH contract
    function wrapSuperchainWETH_FFI() public {
        console.log("Starting ETH wrapping process...");

        // Create a fork of the source chain
        vm.createSelectFork(vm.rpcUrl(L2_1_RPC));

        // Get initial WETH balance
        uint256 prevBalance = _wethBalanceOf(DEPLOYER);
        console.log("Initial WETH balance:", prevBalance);

        // Execute the wrap by sending ETH directly to WETH contract
        console.log("Sending", VALUE, "wei to SuperchainWETH contract...");
        _executeCastSend(
            Predeploys.SUPERCHAIN_WETH,
            "",  // empty calldata for direct value transfer
            L2_1_RPC,
            VALUE
        );

        // Create new fork to get updated state
        vm.createSelectFork(vm.rpcUrl(L2_1_RPC));

        // Verify the wrap was successful
        uint256 balance = _wethBalanceOf(DEPLOYER);
        console.log("Final WETH balance:", balance);
        require(balance == prevBalance + VALUE, "InteropSmokeTest: wrapSuperchainWETH balance failed");

        console.log("ETH successfully wrapped into SuperchainWETH");
    }

    /// @notice Sends SuperchainWETH tokens to the destination chain
    /// @dev Executes a cross-chain transfer via the SuperchainTokenBridge and captures the message details
    /// @return identifier The message identifier containing metadata about the cross-chain message
    /// @return payload The encoded message payload needed for relay
    function sendSuperchainWETH_FFI() public returns (Identifier memory identifier, bytes memory payload) {
        console.log("Starting cross-chain WETH transfer...");

        // Create fork of source chain
        vm.createSelectFork(vm.rpcUrl(L2_1_RPC));

        // Get initial balances and block number
        uint256 prevBalance = _wethBalanceOf(DEPLOYER);
        uint256 beforeBlockNumber = block.number;
        console.log("Initial WETH balance:", prevBalance);
        console.log("Starting block number:", beforeBlockNumber);

        // Execute the cross-chain transfer
        console.log("Executing transfer of", VALUE, "WETH to chain ID:", L2_2_CHAIN_ID);
        _executeCastSend(
            Predeploys.SUPERCHAIN_TOKEN_BRIDGE,
            string.concat(
                "sendERC20(address,address,uint256,uint256) ",
                vm.toString(Predeploys.SUPERCHAIN_WETH), " ",
                vm.toString(DEPLOYER), " ",
                vm.toString(VALUE), " ",
                vm.toString(L2_2_CHAIN_ID)
            ),
            L2_1_RPC
        );

        // Verify the transfer deducted tokens correctly
        vm.createSelectFork(vm.rpcUrl(L2_1_RPC));
        uint256 balance = _wethBalanceOf(DEPLOYER);
        console.log("Final WETH balance:", balance);
        require(balance == prevBalance - VALUE, "InteropSmokeTest: sendSuperchainWETH balance failed");

        // Get the cross-domain message logs
        console.log("Retrieving cross-domain message logs...");
        VmSafe.EthGetLogs[] memory ethLogs = vm.eth_getLogs(
            beforeBlockNumber, block.number, Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, new bytes32[](0)
        );
        VmSafe.EthGetLogs memory log = ethLogs[0];

        // Get block timestamp for the message
        bytes memory timestampResult = _executeCastBlock(
            log.blockNumber,
            "timestamp",
            L2_1_RPC
        );

        uint256 timestamp = vm.parseUint(vm.split(vm.toString(timestampResult), "x")[1]);
        console.log("Message block timestamp:", timestamp);

        // Construct the message identifier
        identifier = Identifier({
            origin: Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            blockNumber: log.blockNumber,
            logIndex: log.logIndex,
            timestamp: timestamp,
            chainId: L2_1_CHAIN_ID
        });

        // Construct the message payload
        payload = abi.encodePacked(
            abi.encode(SENT_MESSAGE_EVENT_SELECTOR, log.topics[1], log.topics[2], log.topics[3]), log.data
        );

        console.log("Cross-chain transfer message prepared successfully");
    }

    /// @notice Relays the cross-chain message on the destination chain to complete the transfer
    /// @dev Takes the message details from sendSuperchainWETH and executes the relay on L2_2
    /// @param identifier The message identifier containing metadata about the cross-chain message
    /// @param payload The encoded message payload to relay
    function relaySuperchainWETH_FFI(Identifier memory identifier, bytes memory payload) public {
        console.log("Starting message relay on destination chain...");

        // Create fork of destination chain
        vm.createSelectFork(vm.rpcUrl(L2_2_RPC));

        // Get initial balance
        uint256 prevBalance = _wethBalanceOf(DEPLOYER);
        console.log("Initial WETH balance on destination:", prevBalance);

        // Execute the message relay
        console.log("Relaying cross-chain message...");
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
            true // async
        );

        console.log("Relay transaction result:");
        console.logBytes(result);

        // Verify the tokens were received
        vm.createSelectFork(vm.rpcUrl(L2_2_RPC));
        uint256 balance = _wethBalanceOf(DEPLOYER);
        console.log("Final WETH balance on destination:", balance);
        require(balance == prevBalance + VALUE, "InteropSmokeTest: relaySuperchainWETH balance failed");

        console.log("Cross-chain transfer completed successfully");
    }


    /// @notice Unwraps SuperchainWETH back to native ETH on the destination chain
    function unwrapSuperchainWETH_FFI() public {
        console.log("Starting WETH unwrapping process...");

        // Create fork of destination chain
        vm.createSelectFork(vm.rpcUrl(L2_2_RPC));

        uint256 prevBalance = _wethBalanceOf(DEPLOYER);

        // Execute the unwrap
        _executeCastSend(
            Predeploys.SUPERCHAIN_WETH,
            vm.toString(
                abi.encodeCall(
                    ISuperchainWETH.withdraw,
                    (VALUE)
                )
            ),
            L2_2_RPC
        );

        // Verify the unwrap
        vm.createSelectFork(vm.rpcUrl(L2_2_RPC));
        uint256 balance = _wethBalanceOf(DEPLOYER);
        require(balance == prevBalance - VALUE, "InteropSmokeTest: unwrapSuperchainWETH balance failed");

        console.log("SuperchainWETH successfully unwrapped to ETH");
    }

    /// @notice Withdraws native ETH from destination chain to L1
    /// @return withdrawalHash The hash of the withdrawal transaction
    /// @return withdrawalTx The withdrawal transaction data needed for proving
    function withdrawETH_FFI() public returns (bytes32 withdrawalHash, Types.WithdrawalTransaction memory withdrawalTx) {
        console.log("Starting ETH withdrawal to L1...");

        // Create fork of destination chain
        vm.createSelectFork(vm.rpcUrl(L2_2_RPC));

        // Get the block number before withdrawal for event tracking
        uint256 beforeBlockNumber = block.number;

        // Execute the withdrawal using L2StandardBridge
        bytes memory result = _executeCastSend(
            Predeploys.L2_STANDARD_BRIDGE,
            vm.toString(
                abi.encodeCall(
                    IL2StandardBridge.withdrawTo,
                    (address(0), DEPLOYER, VALUE, 0, "")
                )
            ),
            L2_2_RPC,
            VALUE
        );

        // Get the withdrawal transaction hash
        withdrawalHash = vm.getTransactionHash(result);

        // Get the withdrawal event logs
        VmSafe.EthGetLogs[] memory logs = vm.eth_getLogs(
            beforeBlockNumber,
            block.number,
            Predeploys.L2_STANDARD_BRIDGE,
            new bytes32[](0)
        );

        // Parse the withdrawal transaction details from the logs
        require(logs.length > 0, "No withdrawal event found");

        // The withdrawal event contains the following fields in order:
        // l1Token, l2Token, from, to, amount, extraData
        (,, address from, address to, uint256 amount, bytes memory extraData) =
            abi.decode(logs[0].data, (address, address, address, address, uint256, bytes));

        // Get the nonce from the event topics
        uint256 nonce = uint256(logs[0].topics[1]);

        withdrawalTx = Types.WithdrawalTransaction({
            nonce: nonce,
            sender: from,
            target: to,
            value: amount,
            gasLimit: 100_000, // This could be made configurable
            data: extraData
        });

        console.log("Withdrawal to L1 initiated successfully");
        console.log("Withdrawal hash:", vm.toString(withdrawalHash));
    }


    /// @notice Finalizes the withdrawal on L1 by proving and completing it
    /// @param _withdrawalHash The hash of the withdrawal transaction from L2
    /// @param _withdrawalTx The withdrawal transaction data needed for proving
    function finalizeWithdrawalOnL1_FFI(
        bytes32 _withdrawalHash,
        Types.WithdrawalTransaction memory _withdrawalTx
    ) public {
       // TODO how to finalize the withdrawal?
    }


    /// @notice Helper function to get WETH balance of an address
    /// @param _user The address to check the balance of
    /// @return The WETH balance of the address
    function _wethBalanceOf(address _user) internal view returns (uint256) {
        return ISuperchainWETH(payable(Predeploys.SUPERCHAIN_WETH)).balanceOf(_user);
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

    function _executeCastSend(
        address _target,
        string memory _calldata,
        string memory _rpcUrl
    ) internal returns (bytes memory) {
        return _executeCastSend(_target, _calldata, _rpcUrl, 0, false);
    }

    function _executeCastSend(
        address _target,
        string memory _calldata,
        string memory _rpcUrl,
        uint256 _value
    ) internal returns (bytes memory) {
        return _executeCastSend(_target, _calldata, _rpcUrl, _value, false);
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
        uint256 i = 0;
        cmds[i++] = "cast";
        cmds[i++] = "block";
        cmds[i++] = vm.toString(_blockNumber);
        cmds[i++] = "--field";
        cmds[i++] = _field;
        cmds[i++] = "--rpc-url";
        cmds[i++] = _rpcUrl;
        return vm.ffi(cmds);
    }
}
