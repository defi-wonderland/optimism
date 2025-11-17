// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Vm } from "forge-std/Vm.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";

/// @title NetworkUpgradeTxns
/// @notice Standard library for generating Network Upgrade Transaction (NUT) artifacts.
///         Provides minimal interface to create DepositTx-compatible transaction metadata.
library NetworkUpgradeTxns {
    using stdJson for string;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Source domain for upgrade transactions
    uint64 internal constant UPGRADE_DEPOSIT_SOURCE_DOMAIN = 2;

    /// @notice Represents a single Network Upgrade Transaction
    ///         Maps to the fields of the `DepositTx` struct defined in
    ///         https://github.com/ethereum-optimism/op-geth/blob/optimism/core/types/deposit_tx.go
    struct NetworkUpgradeTxn {
        bytes data;
        address from;
        uint64 gas;
        bool isSystemTransaction;
        uint256 mint;
        bytes32 sourceHash;
        address to;
        uint256 value;
    }

    /// @notice Represents a Safe transaction bundle metadata
    struct SafeBundleMeta {
        string createdFromSafeAddress;
        string createdFromOwnerAddress;
        string name;
        string description;
    }

    /// @notice Create an upgrade transaction
    /// @param intent Human-readable intent
    /// @param from Sender address
    /// @param to Target address
    /// @param mint Mint amount
    /// @param value Value to send
    /// @param gas Gas limit
    /// @param isSystemTransaction Whether this is a system transaction
    /// @param data Transaction data
    /// @return Upgrade transaction struct
    function newTx(
        string memory intent,
        address from,
        address to,
        uint256 mint,
        uint256 value,
        uint64 gas,
        bool isSystemTransaction,
        bytes memory data
    )
        internal
        pure
        returns (NetworkUpgradeTxn memory)
    {
        return NetworkUpgradeTxn({
            sourceHash: sourceHash(intent),
            from: from,
            to: to,
            mint: mint,
            value: value,
            gas: gas,
            isSystemTransaction: isSystemTransaction,
            data: data
        });
    }

    /// @notice Calculate source hash for an upgrade transaction
    /// @param intent Human-readable intent string
    /// @return Source hash
    function sourceHash(string memory intent) internal pure returns (bytes32) {
        bytes32 intentHash = keccak256(bytes(intent));
        bytes memory domainInput = new bytes(64);

        assembly {
            mstore(add(domainInput, 56), shl(192, UPGRADE_DEPOSIT_SOURCE_DOMAIN))
            mstore(add(domainInput, 64), intentHash)
        }

        return keccak256(domainInput);
    }

    /// @notice Write transactions array to JSON file
    /// @param txns Array of upgrade transactions
    /// @param outputPath File path for output JSON
    function writeArtifact(NetworkUpgradeTxn[] memory txns, string memory outputPath) internal {
        string memory finalJson = "[";

        for (uint256 i = 0; i < txns.length; i++) {
            string memory txnJson = serializeTxn(txns[i], i);
            finalJson = string.concat(finalJson, txnJson);
            if (i < txns.length - 1) {
                finalJson = string.concat(finalJson, ",");
            }
        }

        finalJson = string.concat(finalJson, "]");

        // Write the final serialized JSON array to file
        vm.writeJson(finalJson, outputPath);
    }

    /// @notice Serialize a single transaction to JSON
    /// @param txn Transaction to serialize
    /// @param index Transaction index
    /// @return JSON string
    function serializeTxn(NetworkUpgradeTxn memory txn, uint256 index) internal returns (string memory) {
        string memory key = vm.toString(index);

        vm.serializeBytes32(key, "sourceHash", txn.sourceHash);
        vm.serializeAddress(key, "from", txn.from);
        vm.serializeAddress(key, "to", txn.to);
        vm.serializeUint(key, "mint", txn.mint);
        vm.serializeUint(key, "value", txn.value);
        vm.serializeUint(key, "gas", uint256(txn.gas));
        vm.serializeBool(key, "isSystemTransaction", txn.isSystemTransaction);
        return vm.serializeBytes(key, "data", txn.data);
    }

    /// @notice Helper function to read upgrade transactions from JSON file
    /// @param _inputPath File path for input JSON
    /// @return Array of upgrade transactions
    function readArtifact(string memory _inputPath)
        internal
        view
        returns (NetworkUpgradeTxns.NetworkUpgradeTxn[] memory)
    {
        string memory json = vm.readFile(_inputPath);
        bytes memory parsedData = vm.parseJson(json);
        NetworkUpgradeTxns.NetworkUpgradeTxn[] memory txns =
            abi.decode(parsedData, (NetworkUpgradeTxns.NetworkUpgradeTxn[]));
        return txns;
    }

    /// @notice Write Safe transaction bundle to JSON file
    /// @param version Version string
    /// @param chainId Chain ID string (as string, e.g., "10")
    /// @param createdAt Creation timestamp
    /// @param meta Bundle metadata
    /// @param transactionJsons Array of transaction JSON strings
    /// @param outputPath File path for output JSON
    function writeSafeBundle(
        string memory version,
        string memory chainId,
        uint256 createdAt,
        SafeBundleMeta memory meta,
        string[] memory transactionJsons,
        string memory outputPath
    )
        internal
    {
        // Serialize meta object using vm.serialize* for proper structure
        string memory metaObj = "meta";
        vm.serializeString(metaObj, "createdFromSafeAddress", meta.createdFromSafeAddress);
        vm.serializeString(metaObj, "createdFromOwnerAddress", meta.createdFromOwnerAddress);
        vm.serializeString(metaObj, "name", meta.name);
        string memory metaJson = vm.serializeString(metaObj, "description", meta.description);

        // Build transactions array from individual JSON strings
        string memory txnsArrayStr = "[";
        for (uint256 i = 0; i < transactionJsons.length; i++) {
            txnsArrayStr = string.concat(txnsArrayStr, transactionJsons[i]);
            if (i < transactionJsons.length - 1) {
                txnsArrayStr = string.concat(txnsArrayStr, ",");
            }
        }
        txnsArrayStr = string.concat(txnsArrayStr, "]");

        // Manually construct final JSON - chainId is numeric string, transactions is raw JSON array
        string memory finalJson = string.concat(
            "{",
            "\"version\":\"", version, "\",",
            "\"chainId\":", chainId, ",",  // No quotes around chainId value
            "\"createdAt\":", vm.toString(createdAt), ",",
            "\"meta\":", metaJson, ",",
            "\"transactions\":", txnsArrayStr,
            "}"
        );

        vm.writeJson(finalJson, outputPath);
    }

    /// @notice Create a Safe transaction for L2ImplementationsDeployer.deploy
    /// @param to Target address (L2ImplementationsDeployer)
    /// @param value ETH value to send
    /// @param salt Salt for CREATE2
    /// @param initCode Initialization code for the contract
    /// @return JSON string representing the Safe transaction
    function createSafeDeployJson(
        address to,
        uint256 value,
        bytes32 salt,
        bytes memory initCode
    )
        internal
        returns (string memory)
    {
        // Encode data early to avoid recomputing
        string memory dataStr = vm.toString(abi.encodeWithSignature("deploy(uint256,bytes32,bytes)", value, salt, initCode));
        string memory valueStr = vm.toString(value);
        string memory saltStr = vm.toString(salt);
        string memory initCodeStr = vm.toString(initCode);
        string memory toStr = vm.toString(to);

        // Serialize inputs array items
        string memory obj = "input0";
        vm.serializeString(obj, "internalType", "uint256");
        vm.serializeString(obj, "name", "_value");
        string memory input0Json = vm.serializeString(obj, "type", "uint256");

        obj = "input1";
        vm.serializeString(obj, "internalType", "bytes32");
        vm.serializeString(obj, "name", "_salt");
        string memory input1Json = vm.serializeString(obj, "type", "bytes32");

        obj = "input2";
        vm.serializeString(obj, "internalType", "bytes");
        vm.serializeString(obj, "name", "_initCode");
        string memory input2Json = vm.serializeString(obj, "type", "bytes");

        // Build inputs as raw JSON array (not escaped string)
        string memory inputsArray = string.concat("[", input0Json, ",", input1Json, ",", input2Json, "]");

        // Build contractMethod as raw JSON (using string.concat to avoid double-serialization)
        string memory contractMethodJson = string.concat(
            "{\"inputs\":", inputsArray, ",\"name\":\"deploy\",\"payable\":false}"
        );

        // Serialize contractInputsValues object
        obj = "contractInputsValues";
        vm.serializeString(obj, "_value", valueStr);
        vm.serializeString(obj, "_salt", saltStr);
        string memory contractInputsJson = vm.serializeString(obj, "_initCode", initCodeStr);

        // Build main transaction as raw JSON to avoid escaping nested objects
        string memory finalJson = string.concat(
            "{\"to\":\"", toStr, "\",",
            "\"value\":\"", valueStr, "\",",
            "\"data\":\"", dataStr, "\",",
            "\"contractMethod\":", contractMethodJson, ",",
            "\"contractInputsValues\":", contractInputsJson,
            "}"
        );

        return finalJson;
    }

    /// @notice Create a Safe transaction for ProxyAdmin.performDelegateCall
    /// @param to Target address (ProxyAdmin)
    /// @param target Address to delegatecall to (L2ContractsManager)
    /// @return JSON string representing the Safe transaction
    function createSafePerformDelegateCallJson(address to, address target)
        internal
        returns (string memory)
    {
        // Convert to strings early to avoid stack depth issues
        string memory dataStr = vm.toString(abi.encodeWithSignature("performDelegateCall(address)", target));
        string memory targetStr = vm.toString(target);
        string memory toStr = vm.toString(to);

        // Serialize inputs array item
        string memory obj = "input0";
        vm.serializeString(obj, "internalType", "address");
        vm.serializeString(obj, "name", "_target");
        string memory input0Json = vm.serializeString(obj, "type", "address");

        // Build inputs as raw JSON array (not escaped string)
        string memory inputsArray = string.concat("[", input0Json, "]");

        // Build contractMethod as raw JSON (using string.concat to avoid double-serialization)
        string memory contractMethodJson = string.concat(
            "{\"inputs\":", inputsArray, ",\"name\":\"performDelegateCall\",\"payable\":false}"
        );

        // Serialize contractInputsValues object
        obj = "contractInputsValues";
        string memory contractInputsJson = vm.serializeString(obj, "_target", targetStr);

        // Build main transaction as raw JSON to avoid escaping nested objects
        string memory finalJson = string.concat(
            "{\"to\":\"", toStr, "\",",
            "\"value\":\"0\",",
            "\"data\":\"", dataStr, "\",",
            "\"contractMethod\":", contractMethodJson, ",",
            "\"contractInputsValues\":", contractInputsJson,
            "}"
        );

        return finalJson;
    }
}
