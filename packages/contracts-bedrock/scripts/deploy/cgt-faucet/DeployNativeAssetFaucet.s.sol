// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";
import { NativeAssetFaucet } from "scripts/deploy/cgt-faucet/NativeAssetFaucet.sol";

/// @title ICreate2Deployer
/// @notice Interface for the CREATE2 Deployer predeploy
interface ICreate2Deployer {
    function deploy(uint256 _value, bytes32 _salt, bytes memory _code) external returns (address);
}

/// @title DeployNativeAssetFaucet
/// @notice Script to deploy NativeAssetFaucet to L2 via deposit transactions
contract DeployNativeAssetFaucet is Script {

    /// @notice Deploys and authorizes the NativeAssetFaucet on L2.
    /// @param _portal The OptimismPortal2 contract address.
    /// @param _owner The owner of the faucet.
    /// @param _permissionlessAmount The amount claimable per call.
    /// @param _gasLimit The gas limit for L2 deposit transactions.
    /// @param _saltSeed The salt seed for deterministic deployment.
    function run(
        address _portal,
        address _owner,
        uint256 _permissionlessAmount,
        uint64 _gasLimit,
        string memory _saltSeed
    )
        public
        returns (address)
    {
        console.log("=== DeployNativeAssetFaucet ===");
        console.log("Portal:", _portal);
        console.log("Owner:", _owner);
        console.log("Permissionless Amount:", _permissionlessAmount);
        console.log("Gas Limit:", _gasLimit);
        console.log("Salt Seed:", _saltSeed);

        // Calculate the faucet address
        address faucetAddress = computeFaucetAddress(_owner, _permissionlessAmount, _saltSeed);
        console.log("Computed Faucet Address:", faucetAddress);

        vm.startBroadcast();

        // Step 1: Deploy faucet via CREATE2
        console.log("\n=== Step 1: Deploying NativeAssetFaucet via CREATE2 ===");
        deployFaucet(IOptimismPortal2(payable(_portal)), _owner, _permissionlessAmount, _gasLimit, _saltSeed);

        // Step 2: Authorize faucet as minter in LiquidityController
        console.log("\n=== Step 2: Authorizing faucet as minter ===");
        authorizeFaucet(IOptimismPortal2(payable(_portal)), faucetAddress, _gasLimit);

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("Faucet will be deployed at:", faucetAddress);
        console.log("Wait for L2 to process the deposit transactions (~10-15 seconds)");

        return faucetAddress;
    }

    /// @notice Deploys NativeAssetFaucet via CREATE2 on L2
    function deployFaucet(
        IOptimismPortal2 _portal,
        address _owner,
        uint256 _permissionlessAmount,
        uint64 _gasLimit,
        string memory _saltSeed
    )
        internal
    {
        bytes memory initCode =
            bytes.concat(type(NativeAssetFaucet).creationCode, abi.encode(_owner, _permissionlessAmount));
        bytes32 salt = keccak256(abi.encodePacked(_saltSeed, ":", _owner));

        _portal.depositTransaction({
            _to: Preinstalls.Create2Deployer,
            _value: 0,
            _gasLimit: _gasLimit,
            _isCreation: false,
            _data: abi.encodeCall(ICreate2Deployer.deploy, (0, salt, initCode))
        });

        console.log("Deposit transaction sent for CREATE2 deployment");
    }

    /// @notice Authorizes the faucet as a minter in LiquidityController
    function authorizeFaucet(IOptimismPortal2 _portal, address _faucet, uint64 _gasLimit) internal {
        _portal.depositTransaction({
            _to: Predeploys.LIQUIDITY_CONTROLLER,
            _value: 0,
            _gasLimit: _gasLimit,
            _isCreation: false,
            _data: abi.encodeCall(ILiquidityController.authorizeMinter, (_faucet))
        });

        console.log("Deposit transaction sent for authorizeMinter");
    }

    /// @notice Computes the CREATE2 address for the faucet
    function computeFaucetAddress(
        address _owner,
        uint256 _permissionlessAmount,
        string memory _saltSeed
    )
        public
        pure
        returns (address)
    {
        bytes memory initCode =
            bytes.concat(type(NativeAssetFaucet).creationCode, abi.encode(_owner, _permissionlessAmount));
        bytes32 salt = keccak256(abi.encodePacked(_saltSeed, ":", _owner));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), Preinstalls.Create2Deployer, salt, keccak256(initCode)));
        return address(uint160(uint256(hash)));
    }
}
