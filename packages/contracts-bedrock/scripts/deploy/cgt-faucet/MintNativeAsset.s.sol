// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { NativeAssetFaucet } from "scripts/deploy/cgt-faucet/NativeAssetFaucet.sol";

/// @title MintNativeAsset
/// @notice Script to mint native asset on L2 via deposit transaction from L1.
///         Must be executed by the faucet owner.
contract MintNativeAsset is Script {
    address deployer;

    /// @notice Mints native asset to a recipient on L2.
    /// @param _portal The OptimismPortal2 contract address on L1.
    /// @param _faucet The NativeAssetFaucet contract address on L2.
    /// @param _to The recipient address on L2.
    /// @param _amount The amount to mint (in wei).
    /// @param _gasLimit The gas limit for the L2 deposit transaction.
    function run(
        address _portal,
        address _faucet,
        address _to,
        uint256 _amount,
        uint64 _gasLimit
    )
        public
    {
        deployer = msg.sender;

        console.log("=== MintNativeAsset ===");
        console.log("Portal:", _portal);
        console.log("Faucet:", _faucet);
        console.log("Recipient:", _to);
        console.log("Amount:", _amount);
        console.log("Gas Limit:", _gasLimit);
        console.log("Deployer (must be faucet owner):", deployer);

        vm.broadcast(deployer);
        IOptimismPortal2(payable(_portal)).depositTransaction({
            _to: _faucet,
            _value: 0,
            _gasLimit: _gasLimit,
            _isCreation: false,
            _data: abi.encodeCall(NativeAssetFaucet.mint, (_to, _amount))
        });

        console.log("\n=== Mint Complete ===");
        console.log("Deposit transaction sent to mint", _amount, "wei to", _to);
    }
}
