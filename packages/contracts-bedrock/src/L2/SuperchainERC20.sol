// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ISuperchainERC20Extensions, ISuperchainERC20Errors } from "src/L2/interfaces/ISuperchainERC20.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { IL2ToL2CrossDomainMessenger } from "src/L2/interfaces/IL2ToL2CrossDomainMessenger.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";

/// @title SuperchainERC20
/// @notice SuperchainERC20 is a standard extension of the base ERC20 token contract that unifies ERC20 token
///         bridging to make it fungible across the Superchain. It builds on top of the L2ToL2CrossDomainMessenger for
///         both replay protection and domain binding.
abstract contract SuperchainERC20 is ISuperchainERC20Extensions, ISuperchainERC20Errors, ERC20 {
    /// @notice Address of the L2ToL2CrossDomainMessenger Predeploy.
    address internal constant MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    /// @inheritdoc ISuperchainERC20Extensions
    function PERMIT2() public pure returns (address) {
        return Preinstalls.Permit2;
    }

    /// @inheritdoc ISuperchainERC20Extensions
    function sendERC20(address _to, uint256 _amount, uint256 _chainId) external virtual {
        if (_to == address(0)) revert ZeroAddress();

        _burn(msg.sender, _amount);

        bytes memory _message = abi.encodeCall(this.relayERC20, (msg.sender, _to, _amount));
        IL2ToL2CrossDomainMessenger(MESSENGER).sendMessage(_chainId, address(this), _message);

        emit SendERC20(msg.sender, _to, _amount, _chainId);
    }

    /// @inheritdoc ISuperchainERC20Extensions
    function relayERC20(address _from, address _to, uint256 _amount) external virtual {
        if (msg.sender != MESSENGER) revert CallerNotL2ToL2CrossDomainMessenger();

        if (IL2ToL2CrossDomainMessenger(MESSENGER).crossDomainMessageSender() != address(this)) {
            revert InvalidCrossDomainSender();
        }

        uint256 source = IL2ToL2CrossDomainMessenger(MESSENGER).crossDomainMessageSource();

        _mint(_to, _amount);

        emit RelayERC20(_from, _to, _amount, source);
    }

    /// @notice Transfers `amount` tokens from `from` to `to`.
    ///         If the spender is the permit2 address, returns the maximum uint256 value.
    /// @param  from   The address of the owner of the tokens.
    /// @param  to     The address that will receive the tokens.
    /// @param  amount The amount of tokens to transfer.
    /// @return Whether the transfer was successful or not.
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (msg.sender == PERMIT2()) {
            uint256 _BALANCE_SLOT_SEED = 0x87a211a2;
            uint256 _TRANSFER_EVENT_SIGNATURE = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

            _beforeTokenTransfer(from, to, amount);

            assembly {
                let from_ := shl(96, from)
                // Compute the balance slot and load its value.
                mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))
                let fromBalanceSlot := keccak256(0x0c, 0x20)
                let fromBalance := sload(fromBalanceSlot)
                // Revert if insufficient balance.
                if gt(amount, fromBalance) {
                    mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                    revert(0x1c, 0x04)
                }
                // Subtract and store the updated balance.
                sstore(fromBalanceSlot, sub(fromBalance, amount))
                // Compute the balance slot of `to`.
                mstore(0x00, to)
                let toBalanceSlot := keccak256(0x0c, 0x20)
                // Add and store the updated balance of `to`.
                // Will not overflow because the sum of all user balances
                // cannot exceed the maximum uint256 value.
                sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
                // Emit the {Transfer} event.
                mstore(0x20, amount)
                log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, from_), shr(96, mload(0x0c)))
            }
            _afterTokenTransfer(from, to, amount);
            return true;
        }
        return super.transferFrom(from, to, amount);
    }

    /// @notice Returns the allowance for a spender on the owner's tokens.
    ///         If the spender is the permit2 address, returns the maximum uint256 value.
    /// @param  owner   Owner of the tokens.
    /// @param  spender Spender of the tokens.
    /// @return result Allowance for the spender.
    function allowance(address owner, address spender) public view virtual override returns (uint256 result) {
        if (spender == PERMIT2()) {
            return type(uint256).max;
        }
        result = super.allowance(owner, spender);
    }
}
