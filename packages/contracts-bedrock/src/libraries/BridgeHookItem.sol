// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Hashing } from "src/libraries/Hashing.sol";

// Interfaces
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IStandardBridge } from "interfaces/universal/IStandardBridge.sol";

/// @notice Whether an item enters or leaves L1.
enum Direction {
    Deposit,
    Withdrawal
}

/// @notice The asset an item moves. ERC20 is a token transfer between the standard bridges.
enum Asset {
    ETH,
    ERC20
}

/// @notice One deposit or one withdrawal, as the OptimismPortal sees it. Its hash is the item's
///         identifier. It is emitted when the item is held and supplied again when it completes.
/// @custom:field direction   Whether the item is a deposit or a withdrawal.
/// @custom:field asset       Asset the item moves.
/// @custom:field from        Deposit sender, aliased if it is a contract, or withdrawal sender.
/// @custom:field aliased     Whether `from` is aliased.
/// @custom:field to          Deposit or withdrawal target.
/// @custom:field localToken  L1 token of a token transfer.
/// @custom:field remoteToken L2 token of a token transfer.
/// @custom:field amount      ETH of an ETH item, token amount of an ERC20 item.
/// @custom:field value       ETH value of the L2 call. Deposits only.
/// @custom:field gasLimit    Deposit or withdrawal gas limit.
/// @custom:field isCreation  Whether the deposit creates a contract.
/// @custom:field data        Deposit or withdrawal calldata.
/// @custom:field nonce       Withdrawal nonce.
/// @custom:field uid         Deposit counter or withdrawal hash.
struct Item {
    Direction direction;
    Asset asset;
    address from;
    bool aliased;
    address to;
    address localToken;
    address remoteToken;
    uint256 amount;
    uint256 value;
    uint256 gasLimit;
    bool isCreation;
    bytes data;
    uint256 nonce;
    bytes32 uid;
}

/// @title BridgeHookItem
/// @notice Item helpers shared by the OptimismPortal and the bridge hook.
library BridgeHookItem {
    /// @notice Derives an item's identifier from all of its fields.
    /// @param _item Item to hash.
    /// @return Identifier of the item.
    function hash(Item memory _item) internal pure returns (bytes32) {
        return keccak256(abi.encode(_item));
    }

    /// @notice Builds the ETH item of a withdrawal transaction.
    /// @param _tx             Withdrawal transaction.
    /// @param _withdrawalHash Hash of the withdrawal transaction.
    /// @return The item.
    function fromWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        bytes32 _withdrawalHash
    )
        internal
        pure
        returns (Item memory)
    {
        return Item({
            direction: Direction.Withdrawal,
            asset: Asset.ETH,
            from: _tx.sender,
            aliased: false,
            to: _tx.target,
            localToken: address(0),
            remoteToken: address(0),
            amount: _tx.value,
            value: 0,
            gasLimit: _tx.gasLimit,
            isCreation: false,
            data: _tx.data,
            nonce: _tx.nonce,
            uid: _withdrawalHash
        });
    }

    /// @notice Rebuilds the withdrawal transaction of a withdrawal item.
    /// @param _item Withdrawal item.
    /// @return The withdrawal transaction.
    function toWithdrawalTransaction(Item memory _item) internal pure returns (Types.WithdrawalTransaction memory) {
        return Types.WithdrawalTransaction({
            nonce: _item.nonce,
            sender: _item.from,
            target: _item.to,
            value: _item.asset == Asset.ETH ? _item.amount : 0,
            gasLimit: _item.gasLimit,
            data: _item.data
        });
    }

    /// @notice Reads the inner sender, target and message of a relayMessage envelope.
    /// @param _data Calldata that may be an envelope.
    /// @return ok_      Whether `_data` is an envelope.
    /// @return sender_  Inner sender.
    /// @return target_  Inner target.
    /// @return message_ Inner message, pointing into `_data`.
    function decodeRelayMessage(bytes memory _data)
        internal
        pure
        returns (bool ok_, address sender_, address target_, bytes memory message_)
    {
        (ok_,, sender_, target_,,, message_) = _readRelayMessage(_data);
    }

    /// @notice Returns the hash the L1CrossDomainMessenger records a relayed envelope under.
    /// @param _data Envelope calldata.
    /// @return ok_   Whether `_data` is an envelope.
    /// @return hash_ Versioned hash of the message.
    function relayMessageHash(bytes memory _data) internal pure returns (bool ok_, bytes32 hash_) {
        (
            bool ok,
            uint256 nonce,
            address sender,
            address target,
            uint256 value,
            uint256 minGasLimit,
            bytes memory message
        ) = _readRelayMessage(_data);
        if (!ok) return (false, bytes32(0));
        return (true, Hashing.hashCrossDomainMessageV1(nonce, sender, target, value, minGasLimit, message));
    }

    /// @notice Reads the two tokens and the amount of a finalizeBridgeERC20 call. The first token
    ///         is the one local to the chain the call executes on.
    /// @param _message Message that may be a finalizeBridgeERC20 call.
    /// @return ok_     Whether `_message` is a finalizeBridgeERC20 call.
    /// @return token0_ First token argument.
    /// @return token1_ Second token argument.
    /// @return amount_ Amount argument.
    function decodeFinalizeBridgeERC20(bytes memory _message)
        internal
        pure
        returns (bool ok_, address token0_, address token1_, uint256 amount_)
    {
        // finalizeBridgeERC20(localToken, remoteToken, from, to, amount, extraData)
        if (_selector(_message) != IStandardBridge.finalizeBridgeERC20.selector) {
            return (false, address(0), address(0), 0);
        }
        if (_message.length < 4 + 6 * 32) return (false, address(0), address(0), 0);
        return (
            true,
            address(uint160(uint256(_word(_message, 0)))),
            address(uint160(uint256(_word(_message, 1)))),
            uint256(_word(_message, 4))
        );
    }

    /// @notice Reads the sender and recipient of a finalizeBridgeETH or finalizeBridgeERC20 call.
    /// @param _message Message that may be a standard bridge finalizer.
    /// @return ok_   Whether `_message` is a standard bridge finalizer.
    /// @return from_ Sender argument.
    /// @return to_   Recipient argument.
    function decodeFinalizeParties(bytes memory _message)
        internal
        pure
        returns (bool ok_, address from_, address to_)
    {
        bytes4 selector = _selector(_message);
        uint256 index;
        if (selector == IStandardBridge.finalizeBridgeETH.selector) {
            // finalizeBridgeETH(from, to, amount, extraData)
            index = 0;
        } else if (selector == IStandardBridge.finalizeBridgeERC20.selector) {
            // finalizeBridgeERC20(localToken, remoteToken, from, to, amount, extraData)
            index = 2;
        } else {
            return (false, address(0), address(0));
        }
        if (_message.length < 4 + (index + 2) * 32) return (false, address(0), address(0));
        return (
            true,
            address(uint160(uint256(_word(_message, index)))),
            address(uint160(uint256(_word(_message, index + 1))))
        );
    }

    /// @notice Reads every field of a relayMessage envelope without copying it.
    /// @param _data Calldata that may be an envelope.
    function _readRelayMessage(bytes memory _data)
        private
        pure
        returns (
            bool ok_,
            uint256 nonce_,
            address sender_,
            address target_,
            uint256 value_,
            uint256 minGasLimit_,
            bytes memory message_
        )
    {
        // relayMessage(nonce, sender, target, value, minGasLimit, message): six head words and the
        // message length word after the selector.
        if (_selector(_data) != ICrossDomainMessenger.relayMessage.selector) {
            return (false, 0, address(0), address(0), 0, 0, message_);
        }
        if (_data.length < 4 + 7 * 32) return (false, 0, address(0), address(0), 0, 0, message_);

        uint256 offset = uint256(_word(_data, 5));
        uint256 args = _data.length - 4;
        if (offset > args - 32) return (false, 0, address(0), address(0), 0, 0, message_);

        assembly ("memory-safe") {
            message_ := add(add(_data, 0x24), offset)
        }
        if (message_.length > args - 32 - offset) return (false, 0, address(0), address(0), 0, 0, new bytes(0));

        nonce_ = uint256(_word(_data, 0));
        sender_ = address(uint160(uint256(_word(_data, 1))));
        target_ = address(uint160(uint256(_word(_data, 2))));
        value_ = uint256(_word(_data, 3));
        minGasLimit_ = uint256(_word(_data, 4));
        ok_ = true;
    }

    /// @notice Returns the head word at `_index` of an ABI-encoded call. The caller checks length.
    /// @param _call  ABI-encoded call, selector included.
    /// @param _index Index of the head word after the selector.
    function _word(bytes memory _call, uint256 _index) private pure returns (bytes32 word_) {
        assembly ("memory-safe") {
            word_ := mload(add(add(_call, 0x24), mul(_index, 0x20)))
        }
    }

    /// @notice Returns the selector of an ABI-encoded call, or zero if it is shorter than four bytes.
    /// @param _call ABI-encoded call.
    function _selector(bytes memory _call) private pure returns (bytes4 selector_) {
        if (_call.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector_ := and(mload(add(_call, 0x20)), shl(224, 0xffffffff))
        }
    }
}
