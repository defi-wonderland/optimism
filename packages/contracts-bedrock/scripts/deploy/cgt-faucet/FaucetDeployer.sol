// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Interfaces
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";

import { NativeAssetFaucet } from "scripts/deploy/cgt-faucet/NativeAssetFaucet.sol";

/// @title ICreate2Deployer
/// @notice Interface for the CREATE2 Deployer predeploy
interface ICreate2Deployer {
    function deploy(uint256 _value, bytes32 _salt, bytes memory _code) external returns (address);
}

/// @title FaucetDeployer
/// @notice L1 contract to deploy and manage NativeAssetFaucet on L2 via deposit transactions.
///         This contract is designed to be called via delegatecall from a Safe or similar multisig.
///         - deployAndAuthorize(): Called by LiquidityController owner to deploy faucet and authorize it as minter
///         - mint(): Called by faucet owner to mint tokens to recipients
contract FaucetDeployer {
    /// @notice The address of the OptimismPortal2 on L1.
    IOptimismPortal2 public immutable portal;

    /// @notice The salt prefix for the Faucet system.
    string internal constant SALT_SEED = "Faucet";

    /// @notice Constructor to set the OptimismPortal2 address
    /// @param _portal The address of the OptimismPortal2 on L1
    constructor(IOptimismPortal2 _portal) {
        portal = _portal;
    }

    /// @notice Deploys a NativeAssetFaucet via CREATE2 on L2 and authorizes it as a minter.
    ///         Must be called by the LiquidityController owner (or via delegatecall from a Safe).
    /// @param _faucetOwner Owner of the NativeAssetFaucet contract (can be different from LC owner)
    /// @param _permissionlessAmount Amount users can claim per block in permissionless mode
    /// @param _gasLimit Gas limit for each L2 deposit transaction
    /// @return faucetAddress The computed address where the faucet will be deployed
    function deployAndAuthorize(
        address _faucetOwner,
        uint256 _permissionlessAmount,
        uint64 _gasLimit
    )
        external
        returns (address faucetAddress)
    {
        bytes memory initCode =
            bytes.concat(type(NativeAssetFaucet).creationCode, abi.encode(_faucetOwner, _permissionlessAmount));
        bytes32 salt = keccak256(abi.encodePacked(SALT_SEED, ":", _faucetOwner));

        // Calculate the CREATE2 address
        faucetAddress = computeCreate2Address(salt, initCode);

        // Deploy the faucet via CREATE2
        portal.depositTransaction({
            _to: Preinstalls.Create2Deployer,
            _value: 0,
            _gasLimit: _gasLimit,
            _isCreation: false,
            _data: abi.encodeCall(ICreate2Deployer.deploy, (0, salt, initCode))
        });

        // Authorize the faucet as a minter in the LiquidityController
        portal.depositTransaction({
            _to: Predeploys.LIQUIDITY_CONTROLLER,
            _value: 0,
            _gasLimit: _gasLimit,
            _isCreation: false,
            _data: abi.encodeCall(ILiquidityController.authorizeMinter, (faucetAddress))
        });
    }

    /// @notice Mints tokens to a recipient via the NativeAssetFaucet.
    ///         Must be called by the faucet owner (or via delegatecall from a Safe that owns the faucet).
    /// @param _faucet Address of the NativeAssetFaucet contract on L2
    /// @param _to Address to receive the minted tokens
    /// @param _amount Amount of tokens to mint
    /// @param _gasLimit Gas limit for the L2 deposit transaction
    function mint(address _faucet, address _to, uint256 _amount, uint64 _gasLimit) external {
        portal.depositTransaction({
            _to: _faucet,
            _value: 0,
            _gasLimit: _gasLimit,
            _isCreation: false,
            _data: abi.encodeCall(NativeAssetFaucet.mint, (_to, _amount))
        });
    }

    /// @notice Computes the CREATE2 address for a given salt and init code
    /// @param _salt The salt used for CREATE2 deployment
    /// @param _initCode The initialization code
    /// @return The computed CREATE2 address
    function computeCreate2Address(bytes32 _salt, bytes memory _initCode) public pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), Preinstalls.Create2Deployer, _salt, keccak256(_initCode)));
        return address(uint160(uint256(hash)));
    }
}
