// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { AddressAliasHelper } from "src/vendor/AddressAliasHelper.sol";

// Interfaces
import { ILiquidityController } from "interfaces/L2/ILiquidityController.sol";

/// @title NativeAssetFaucet
/// @notice Simple faucet contract for CGT devnets.
///         This contract is immutable and can only be called by its owner or the aliased owner.
///         Also supports permissionless minting with a per-block rate limit.
contract NativeAssetFaucet {
    /// @notice Error for when the caller is not authorized
    error NativeAssetFaucet_Unauthorized();

    /// @notice Error for when user has already claimed in this block
    error NativeAssetFaucet_BlockLimitReached();

    /// @notice The owner of this contract (can be an L1 address)
    address public immutable owner;

    /// @notice Amount users can claim per block in permissionless mode
    uint256 public permissionlessAmount;

    /// @notice Mapping of user address to last block number they claimed
    mapping(address => uint256) public lastClaimBlock;

    /// @notice Constructor to set the owner and initial permissionless amount
    /// @param _owner The owner address (can be L1 address, will accept both normal and aliased calls)
    /// @param _permissionlessAmount Initial amount users can claim per block
    constructor(address _owner, uint256 _permissionlessAmount) {
        owner = _owner;
        permissionlessAmount = _permissionlessAmount;
    }

    /// @notice Modifier to restrict access to owner or aliased owner
    modifier onlyOwner() {
        if (msg.sender != owner && msg.sender != AddressAliasHelper.applyL1ToL2Alias(owner)) {
            revert NativeAssetFaucet_Unauthorized();
        }
        _;
    }

    /// @notice Mints tokens to a recipient via the LiquidityController (owner only)
    /// @param _to The address to receive the minted tokens
    /// @param _amount The amount of tokens to mint
    function mint(address _to, uint256 _amount) external onlyOwner {
        ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER).mint(_to, _amount);
    }

    /// @notice Sets the permissionless claim amount (owner only)
    /// @param _amount The new amount users can claim per block
    function setPermissionlessAmount(uint256 _amount) external onlyOwner {
        permissionlessAmount = _amount;
    }

    /// @notice Permissionless claim function - anyone can claim per block
    /// @param _to The address to receive the minted tokens
    function claim(address _to) external {
        if (lastClaimBlock[_to] == block.number) {
            revert NativeAssetFaucet_BlockLimitReached();
        }

        lastClaimBlock[_to] = block.number;

        ILiquidityController(Predeploys.LIQUIDITY_CONTROLLER).mint(_to, permissionlessAmount);
    }
}
