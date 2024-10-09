// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ICrosschainERC20 } from "src/L2/interfaces/ICrosschainERC20.sol";
import { ISemver } from "src/universal/interfaces/ISemver.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";

/// @title SuperchainERC20
/// @notice SuperchainERC20 is a standard extension of the base ERC20 token contract that unifies ERC20 token
///         bridging to make it fungible across the Superchain. This construction allows the SuperchainTokenBridge to
///         burn and mint tokens.
abstract contract SuperchainERC20 is ERC20, ICrosschainERC20, ISemver {
    /// @notice Thrown when attempting to mint or burn tokens and the function caller is not the SuperchainTokenBridge.
    error OnlySuperchainTokenBridge();

    /// @notice A modifier that only allows the SuperchainTokenBridge to call
    modifier onlySuperchainTokenBridge() {
        if (msg.sender != Predeploys.SUPERCHAIN_TOKEN_BRIDGE) revert OnlySuperchainTokenBridge();
        _;
    }

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-beta.1
    function version() external view virtual returns (string memory) {
        return "1.0.0-beta.1";
    }

    /// @notice Allows the SuperchainTokenBridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function __crosschainMint(address _to, uint256 _amount) external virtual onlySuperchainTokenBridge {
        _mint(_to, _amount);

        emit CrosschainMinted(_to, _amount);
    }

    /// @notice Allows the SuperchainTokenBridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function __crosschainBurn(address _from, uint256 _amount) external virtual onlySuperchainTokenBridge {
        _burn(_from, _amount);

        emit CrosschainBurnt(_from, _amount);
    }

    function handleExpireMessage(
        uint256 destination,
        uint256 nonce,
        address sender,
        address target,
        bytes memory message,
        address to,
        uint256 amount,
        address originalSender
    )
        external
    {
        require(sender == Predeploys.SUPERCHAIN_ERC20_BRIDGE);
        require(target == address(this));

        bytes memory expectedMessage =
            abi.encodeCall(Predeploys.SUPERCHAIN_ERC20_BRIDGE.relayERC20, (address(this), originalSender, to, amount));
        require(expectedMessage = message);

        bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage({
            _destination: destination,
            _source: block.chainId,
            _nonce: nonce,
            _sender: sender,
            _target: target,
            _message: message
        });

        bool isExpired = Predeploys.L2ToL2CrossDomainMessenger.expiredMessages(msgHash) != 0;

        if (isExpired) {
            // a recovery address could be added to the message as well
            _mint(originalSender, amount);
        }
    }
}
