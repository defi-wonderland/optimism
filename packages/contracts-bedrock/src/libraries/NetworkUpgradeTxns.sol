// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Vm } from "forge-std/Vm.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";

/// @title NetworkUpgradeTxns
/// @notice Standard library for generating Network Upgrade Transaction (NUT) artifacts.
///         Provides interface to create DepositTx-compatible transaction metadata with optional Safe fields.
library NetworkUpgradeTxns {
    using stdJson for string;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Source domain for upgrade transactions
    uint64 internal constant UPGRADE_DEPOSIT_SOURCE_DOMAIN = 2;

    /// @notice Represents a Network Upgrade Transaction with both NUT and Safe fields
    ///         NUT fields map to the `DepositTx` struct defined in
    ///         https://github.com/ethereum-optimism/op-geth/blob/optimism/core/types/deposit_tx.go
    ///         Safe fields provide contractMethod and contractInputsValues for Safe UI compatibility
    struct NetworkUpgradeTxn {
        address to;
        uint256 value;
        bytes data;
        address from;
        uint64 gas;
        bool isSystemTransaction;
        uint256 mint;
        bytes32 sourceHash;
        string contractMethodJson;
        string contractInputsValuesJson;
    }

    /// @notice Represents a transaction bundle metadata
    struct BundleMeta {
        string createdFromSafeAddress;
        string createdFromOwnerAddress;
        string name;
        string description;
    }

    /// @notice Create an upgrade transaction with optional Safe fields
    /// @param intent Human-readable intent
    /// @param from Sender address
    /// @param to Target address
    /// @param mint Mint amount
    /// @param value Value to send
    /// @param gas Gas limit
    /// @param isSystemTransaction Whether this is a system transaction
    /// @param data Transaction data
    /// @param contractMethodJson Optional Safe contractMethod JSON (empty string if not needed)
    /// @param contractInputsValuesJson Optional Safe contractInputsValues JSON (empty string if not needed)
    /// @return Upgrade transaction struct
    function newTx(
        string memory intent,
        address from,
        address to,
        uint256 mint,
        uint256 value,
        uint64 gas,
        bool isSystemTransaction,
        bytes memory data,
        string memory contractMethodJson,
        string memory contractInputsValuesJson
    )
        internal
        pure
        returns (NetworkUpgradeTxn memory)
    {
        return NetworkUpgradeTxn({
            to: to,
            value: value,
            data: data,
            from: from,
            gas: gas,
            isSystemTransaction: isSystemTransaction,
            mint: mint,
            sourceHash: sourceHash(intent),
            contractMethodJson: contractMethodJson,
            contractInputsValuesJson: contractInputsValuesJson
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

    /// @notice Write transaction bundle to JSON file
    /// @param version Version string (e.g., "1.0")
    /// @param chainId Chain ID as string
    /// @param createdAt Creation timestamp
    /// @param meta Bundle metadata
    /// @param txns Array of upgrade transactions
    /// @param outputPath File path for output JSON
    function writeArtifact(
        string memory version,
        string memory chainId,
        uint256 createdAt,
        BundleMeta memory meta,
        NetworkUpgradeTxn[] memory txns,
        string memory outputPath
    )
        internal
    {
        // Serialize meta object
        string memory metaObj = "meta";
        vm.serializeString(metaObj, "createdFromSafeAddress", meta.createdFromSafeAddress);
        vm.serializeString(metaObj, "createdFromOwnerAddress", meta.createdFromOwnerAddress);
        vm.serializeString(metaObj, "name", meta.name);
        string memory metaJson = vm.serializeString(metaObj, "description", meta.description);

        // Build transactions array
        string memory txnsArrayStr = "[";
        for (uint256 i = 0; i < txns.length; i++) {
            txnsArrayStr = string.concat(txnsArrayStr, serializeTxn(txns[i]));
            if (i < txns.length - 1) {
                txnsArrayStr = string.concat(txnsArrayStr, ",");
            }
        }
        txnsArrayStr = string.concat(txnsArrayStr, "]");

        // Manually construct final JSON
        string memory finalJson = string.concat(
            "{",
            "\"version\":\"", version, "\",",
            "\"chainId\":", chainId, ",",
            "\"createdAt\":", vm.toString(createdAt), ",",
            "\"meta\":", metaJson, ",",
            "\"transactions\":", txnsArrayStr,
            "}"
        );

        vm.writeJson(finalJson, outputPath);
    }

    /// @notice Serialize a transaction (with both NUT and optional Safe fields) to JSON
    /// @param txn Transaction to serialize
    /// @return JSON string representing the transaction
    function serializeTxn(NetworkUpgradeTxn memory txn) internal pure returns (string memory) {
        // Convert all values to strings early to avoid stack depth issues
        string memory toStr = vm.toString(txn.to);
        string memory valueStr = vm.toString(txn.value);
        string memory dataStr = vm.toString(txn.data);
        string memory fromStr = vm.toString(txn.from);
        string memory gasStr = vm.toString(uint256(txn.gas));
        string memory mintStr = vm.toString(txn.mint);
        string memory sourceHashStr = vm.toString(txn.sourceHash);
        string memory isSysStr = txn.isSystemTransaction ? "true" : "false";

        // Manually construct JSON to avoid double-serialization
        string memory finalJson = string.concat(
            "{\"to\":\"", toStr, "\",",
            "\"value\":\"", valueStr, "\",",
            "\"data\":\"", dataStr, "\",",
            "\"from\":\"", fromStr, "\",",
            "\"gas\":", gasStr, ","
        );

        finalJson = string.concat(
            finalJson,
            "\"isSystemTransaction\":", isSysStr, ",",
            "\"mint\":", mintStr, ",",
            "\"sourceHash\":\"", sourceHashStr, "\""
        );

        // Add Safe fields if present
        if (bytes(txn.contractMethodJson).length > 0) {
            finalJson = string.concat(
                finalJson,
                ",\"contractMethod\":", txn.contractMethodJson,
                ",\"contractInputsValues\":", txn.contractInputsValuesJson
            );
        }

        return string.concat(finalJson, "}");
    }

    /// @notice Create a transaction for L2ImplementationsDeployer.deploy with both NUT and Safe fields
    /// @param intent Human-readable intent for the NUT sourceHash
    /// @param from Sender address
    /// @param to Target address (L2ImplementationsDeployer)
    /// @param value ETH value to send
    /// @param gas Gas limit
    /// @param isSystemTransaction Whether this is a system transaction
    /// @param mint Mint amount
    /// @param salt Salt for CREATE2
    /// @param initCode Initialization code for the contract
    /// @return result Transaction struct
    function newDeployTx(
        string memory intent,
        address from,
        address to,
        uint256 value,
        uint64 gas,
        bool isSystemTransaction,
        uint256 mint,
        bytes32 salt,
        bytes memory initCode
    )
        internal
        returns (NetworkUpgradeTxn memory result)
    {
        // Compute sourceHash early to avoid stack depth issues
        bytes32 srcHash = sourceHash(intent);
        bytes memory data = abi.encodeWithSignature("deploy(uint256,bytes32,bytes)", value, salt, initCode);

        // Set basic fields first
        result.to = to;
        result.value = value;
        result.data = data;
        result.from = from;
        result.gas = gas;
        result.isSystemTransaction = isSystemTransaction;
        result.mint = mint;
        result.sourceHash = srcHash;

        // Generate Safe transaction fields
        string memory valueStr = vm.toString(value);
        string memory saltStr = vm.toString(salt);
        string memory initCodeStr = vm.toString(initCode);

        // Build inputs using a helper to reduce stack depth
        string memory inputsArray = _buildDeployInputsArray();

        result.contractMethodJson = string.concat(
            "{\"inputs\":", inputsArray, ",\"name\":\"deploy\",\"payable\":false}"
        );

        result.contractInputsValuesJson = _buildDeployInputsValues(valueStr, saltStr, initCodeStr);
    }

    /// @notice Helper to build deploy inputs array JSON
    function _buildDeployInputsArray() private returns (string memory) {
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

        return string.concat("[", input0Json, ",", input1Json, ",", input2Json, "]");
    }

    /// @notice Helper to build deploy inputs values JSON
    function _buildDeployInputsValues(
        string memory valueStr,
        string memory saltStr,
        string memory initCodeStr
    )
        private
        returns (string memory)
    {
        string memory obj = "contractInputsValues";
        vm.serializeString(obj, "_value", valueStr);
        vm.serializeString(obj, "_salt", saltStr);
        return vm.serializeString(obj, "_initCode", initCodeStr);
    }

    /// @notice Create a transaction for ProxyAdmin.performDelegateCall with both NUT and Safe fields
    /// @param intent Human-readable intent for the NUT sourceHash
    /// @param from Sender address
    /// @param proxyAdmin Target address (ProxyAdmin)
    /// @param target Address to delegatecall to (L2ContractsManager)
    /// @param gas Gas limit
    /// @param isSystemTransaction Whether this is a system transaction
    /// @param mint Mint amount
    /// @param value ETH value to send
    /// @return result Transaction struct
    function newPerformDelegateCallTx(
        string memory intent,
        address from,
        address proxyAdmin,
        address target,
        uint64 gas,
        bool isSystemTransaction,
        uint256 mint,
        uint256 value
    )
        internal
        returns (NetworkUpgradeTxn memory result)
    {
        // Compute sourceHash early to avoid stack depth issues
        bytes32 srcHash = sourceHash(intent);
        bytes memory data = abi.encodeWithSignature("performDelegateCall(address)", target);

        // Set basic fields first
        result.to = proxyAdmin;
        result.value = value;
        result.data = data;
        result.from = from;
        result.gas = gas;
        result.isSystemTransaction = isSystemTransaction;
        result.mint = mint;
        result.sourceHash = srcHash;

        // Generate Safe transaction fields
        string memory targetStr = vm.toString(target);

        string memory obj = "input0";
        vm.serializeString(obj, "internalType", "address");
        vm.serializeString(obj, "name", "_target");
        string memory input0Json = vm.serializeString(obj, "type", "address");

        string memory inputsArray = string.concat("[", input0Json, "]");

        result.contractMethodJson = string.concat(
            "{\"inputs\":", inputsArray, ",\"name\":\"performDelegateCall\",\"payable\":false}"
        );

        obj = "contractInputsValuesDelegateCall";
        result.contractInputsValuesJson = vm.serializeString(obj, "_target", targetStr);
    }
}
