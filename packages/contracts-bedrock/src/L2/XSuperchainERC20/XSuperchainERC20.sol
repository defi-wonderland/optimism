// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Contracts
import { XERC20 } from "@xERC20/contracts/XERC20.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Unauthorized } from "src/libraries/errors/CommonErrors.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IXERC20 } from "@xERC20/interfaces/IXERC20.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IERC7802, IERC165 } from "interfaces/L2/IERC7802.sol";

/// @title XSuperchainERC20
/// @notice A standard ERC20 extension implementing IERC7281 and IERC7802 for 
///         unified cross-chain fungibility across any bridge.
contract XSuperchainERC20 is XERC20, IERC7802, ISemver {
    /// @dev The canonical Permit2 address.
    /// For signature-based allowance granting for single transaction ERC20 `transferFrom`.
    /// [Github](https://github.com/Uniswap/permit2)
    /// [Etherscan](https://optimistic.etherscan.io/address/0x000000000022d473030f116ddee9f6b43ac78ba3#code)
    address internal constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @notice Constructs the XSuperchainERC20 contract.
    ///
    /// @param _name    Name of the token.
    /// @param _symbol  Symbol of the token.
    /// @param _factory Address of the factory contract.
    constructor(string memory _name, string memory _symbol, address _factory) XERC20(_name, _symbol, _factory) { }

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-beta.1
    function version() external view virtual returns (string memory) {
        return "1.0.0-beta.1";
    }

    /// @notice Returns the remaining number of tokens that `spender` will be
    ///         allowed to spend on behalf of `owner` through {transferFrom}. This is
    ///         zero by default.
    /// @dev This value changes when {approve} or {transferFrom} are called.
    /// @dev Allowance is overriden to allow Permit2 to spend unlimited tokens.
    function allowance(address _owner, address _spender) public view virtual override returns (uint256) {
        return _spender == _PERMIT2 ? type(uint256).max : super.allowance(_owner, _spender);
    }

    /// @notice Allows the SuperchainTokenBridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function crosschainMint(address _to, uint256 _amount) external {
        _mintWithCaller(msg.sender, _to, _amount);

        emit CrosschainMint(_to, _amount, msg.sender);
    }

    /// @notice Allows the SuperchainTokenBridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function crosschainBurn(address _from, uint256 _amount) external {
        _burnWithCaller(msg.sender, _from, _amount);

        emit CrosschainBurn(_from, _amount, msg.sender);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceId) public view virtual returns (bool) {
        return _interfaceId == type(IERC7802).interfaceId || _interfaceId == type(IERC20).interfaceId
            || _interfaceId == type(IERC165).interfaceId || _interfaceId == type(IXERC20).interfaceId;
    }
}
