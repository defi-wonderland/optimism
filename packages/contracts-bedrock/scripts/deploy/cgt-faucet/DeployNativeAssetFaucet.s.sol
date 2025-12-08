// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { NativeAssetFaucet } from "src/L2/NativeAssetFaucet.sol";

/// @title ICreate2Deployer
/// @notice Interface for the CREATE2 Deployer predeploy
interface ICreate2Deployer {
    function deploy(uint256 _value, bytes32 _salt, bytes memory _code) external returns (address);
}

/// @title DeployNativeAssetFaucet
/// @notice Script to deploy NativeAssetFaucet to L2 via deposit transactions
contract DeployNativeAssetFaucet is Script {
    /// @notice The CREATE2 Deployer predeploy address
    address constant CREATE2_DEPLOYER = 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2;

    /// @notice Salt prefix for deterministic deployment
    string constant SALT_SEED = "Faucet2";

    /// @notice Gas limit for L2 transactions
    uint64 constant GAS_LIMIT = 1000000;

    function run() external {
        // Get environment variables
        address payable portal = payable(vm.envAddress("PORTAL"));
        address owner = vm.envAddress("FAUCET_OWNER");
        uint256 permissionlessAmount = vm.envOr("PERMISSIONLESS_AMOUNT", uint256(1 ether));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("=== DeployNativeAssetFaucet ===");
        console.log("Portal:", portal);
        console.log("Owner:", owner);
        console.log("Permissionless Amount:", permissionlessAmount);

        // Calculate the faucet address
        address faucetAddress = computeFaucetAddress(owner, permissionlessAmount);
        console.log("Computed Faucet Address:", faucetAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy faucet via CREATE2
        console.log("\n=== Step 1: Deploying NativeAssetFaucet via CREATE2 ===");
        deployFaucet(IOptimismPortal2(portal), owner, permissionlessAmount);

        // Step 2: Authorize faucet as minter in LiquidityController
        console.log("\n=== Step 2: Authorizing faucet as minter ===");
        authorizeFaucet(IOptimismPortal2(portal), faucetAddress);

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("Faucet will be deployed at:", faucetAddress);
        console.log("Wait for L2 to process the deposit transactions (~10-15 seconds)");
    }

    /// @notice Deploys NativeAssetFaucet via CREATE2 on L2
    function deployFaucet(
        IOptimismPortal2 _portal,
        address _owner,
        uint256 _permissionlessAmount
    )
        internal
    {
        bytes memory initCode =
            bytes.concat(type(NativeAssetFaucet).creationCode, abi.encode(_owner, _permissionlessAmount));
        bytes32 salt = keccak256(abi.encodePacked(SALT_SEED, ":", _owner));

        _portal.depositTransaction({
            _to: CREATE2_DEPLOYER,
            _value: 0,
            _gasLimit: GAS_LIMIT,
            _isCreation: false,
            _data: abi.encodeCall(ICreate2Deployer.deploy, (0, salt, initCode))
        });

        console.log("Deposit transaction sent for CREATE2 deployment");
    }

    /// @notice Authorizes the faucet as a minter in LiquidityController
    function authorizeFaucet(IOptimismPortal2 _portal, address _faucet) internal {
        _portal.depositTransaction({
            _to: Predeploys.LIQUIDITY_CONTROLLER,
            _value: 0,
            _gasLimit: GAS_LIMIT,
            _isCreation: false,
            _data: abi.encodeCall(ILiquidityController.authorizeMinter, (_faucet))
        });

        console.log("Deposit transaction sent for authorizeMinter");
    }

    /// @notice Computes the CREATE2 address for the faucet
    function computeFaucetAddress(address _owner, uint256 _permissionlessAmount) public pure returns (address) {
        bytes memory initCode =
            bytes.concat(type(NativeAssetFaucet).creationCode, abi.encode(_owner, _permissionlessAmount));
        bytes32 salt = keccak256(abi.encodePacked(SALT_SEED, ":", _owner));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, keccak256(initCode)));
        return address(uint160(uint256(hash)));
    }
}
