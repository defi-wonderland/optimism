// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeSend } from "src/universal/SafeSend.sol";

// Libraries
import { Unauthorized } from "src/libraries/errors/CommonErrors.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { INativeAssetLiquidity } from "interfaces/L2/INativeAssetLiquidity.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:predeploy 0x4200000000000000000000000000000000000029
/// @title LiquidityController
/// @notice The LiquidityController contract is responsible for controlling the liquidity of the native asset on the L2
///         chain.
contract LiquidityController is Ownable, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Mapping of addresses authorized to control liquidity operations
    mapping(address => bool) public minters;

    /// @notice The name of the native asset
    string public gasPayingTokenName;

    /// @notice The symbol of the native asset
    string public gasPayingTokenSymbol;

    constructor(string memory _gasPayingTokenName, string memory _gasPayingTokenSymbol) {
        gasPayingTokenName = _gasPayingTokenName;
        gasPayingTokenSymbol = _gasPayingTokenSymbol;
    }

    /// @notice Authorizes an address to perform liquidity control operations
    /// @param _minter The address to authorize as a minter
    function authorizeMinter(address _minter) external onlyOwner {
        minters[_minter] = true;
    }

    /// @notice Mints native asset liquidity and sends it to a specified address
    /// @param _to The address to receive the minted native asset
    /// @param _amount The amount of native asset to mint and send
    function mint(address _to, uint256 _amount) external {
        if (!minters[msg.sender]) revert Unauthorized();
        INativeAssetLiquidity(Predeploys.NATIVE_ASSET_LIQUIDITY).withdraw(_amount);

        // This is a forced ETH send to the recipient, the recipient should NOT expect to be called
        new SafeSend{ value: _amount }(payable(_to));
    }

    /// @notice Burns native asset liquidity by sending ETH to the contract
    function burn() external payable {
        if (!minters[msg.sender]) revert Unauthorized();
        INativeAssetLiquidity(Predeploys.NATIVE_ASSET_LIQUIDITY).deposit{ value: msg.value }();
    }

    /// @notice Returns the decimals of the gas paying token
    function gasPayingTokenDecimals() external pure returns (uint8) {
        return 18;
    }
}
