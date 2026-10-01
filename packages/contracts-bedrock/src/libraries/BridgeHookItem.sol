// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import { Types } from "src/libraries/Types.sol";

/// @notice The direction an item is travelling relative to L1.
enum Direction {
    Deposit,
    Withdrawal
}

/// @notice The asset class of an item. A new asset class is a new value here plus logic in the
///         hook implementation. Neither the hook interface nor any call site changes.
enum Asset {
    ETH,
    ERC20
}

/// @notice One unit of value crossing the bridge in one direction under one identifier.
///         Passed by value across hops and hashed into the identifier. Never stored: it is
///         emitted in full when an item is held and re-supplied when value moves.
/// @custom:field direction    Whether the item is entering or leaving L1.
/// @custom:field asset        The asset class of the item.
/// @custom:field from         Final L2 sender for deposits, aliased if the L1 caller was a
///                            contract. L2 sender for withdrawals.
/// @custom:field aliased      Whether `from` carries the L1 to L2 alias. Describes the outer
///                            field only: a party recovered from an envelope is never aliased.
/// @custom:field to           Recipient or target.
/// @custom:field localToken   Token on this chain. Zero for ETH.
/// @custom:field remoteToken  Token on the remote chain. Zero for ETH.
/// @custom:field amount       Value taken into custody: ETH held, or token amount.
/// @custom:field value        L2 call value. Only meaningful for an ETH deposit.
/// @custom:field gasLimit     L2 gas limit for a deposit, the withdrawal's gas limit for an ETH
///                            withdrawal, the message's minimum gas limit for a token deposit.
/// @custom:field isCreation   Whether the deposit is a contract creation.
/// @custom:field data         Deposit or withdrawal calldata, or a token item's extra data.
/// @custom:field messageNonce Reconstruction data, not identity. Only an ETH withdrawal sets it,
///                            because only that path has to rebuild a WithdrawalTransaction to
///                            hand back to the Portal.
/// @custom:field uid          What makes this item distinct from an otherwise identical one. The
///                            protocol supplies it where it has one and a counter fills in where
///                            it does not. See the table below.
///
/// Which fields are meaningful, by case. Everything else is zero, and the identifier binds all of
/// them either way.
///
/// | Field        | ETH deposit | ERC-20 deposit | ETH withdrawal | ERC-20 withdrawal |
/// | ------------ | ----------- | -------------- | -------------- | ----------------- |
/// | from, to     | yes         | yes            | yes            | yes               |
/// | aliased      | yes         | no             | no             | no                |
/// | localToken   | no          | yes            | no             | yes               |
/// | remoteToken  | no          | yes            | no             | yes               |
/// | amount       | ETH sent    | token amount   | ETH withdrawn  | token amount      |
/// | value        | yes         | no             | no             | no                |
/// | gasLimit     | L2 gas      | min gas limit  | withdrawal gas | no                |
/// | isCreation   | yes         | no             | no             | no                |
/// | data         | calldata    | extra data     | calldata       | extra data        |
/// | messageNonce | no          | no             | yes            | no                |
/// | uid          | counter     | counter        | withdrawal hash| withdrawal hash   |
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
    uint256 messageNonce;
    bytes32 uid;
}

/// @title BridgeHookItem
/// @notice Defines the one type the OptimismPortal, the L1StandardBridge and the hook all agree
///         on, and the rule for deriving an item's identifier. The identifier is derived rather
///         than passed, so a call site and the hook agree by construction and no caller can
///         supply an identifier that disagrees with the terms.
/// @dev This vocabulary deliberately lives outside Types.sol and Hashing.sol, which are
///      consensus-adjacent.
///
///      Uniqueness and term binding are two different guarantees and both are needed. Uniqueness
///      says at most one legitimate item exists per protocol event, and comes from `uid`. Term
///      binding says only the committed terms can execute, and comes from the identifier covering
///      every field. Neither substitutes for the other: an identifier that *is* a protocol hash
///      rather than one that *contains* it would be unique but would let a caller repoint `to` or
///      inflate `amount` on an item that already carries a clearance.
library BridgeHookItem {
    /// @notice Derives an item's identifier. One rule for all four cases, so that every field is
    ///         bound on every path and no case needs its own reasoning about what is covered.
    /// @param _item Item to hash.
    /// @return Identifier for the item.
    function hash(Item memory _item) internal pure returns (bytes32) {
        return keccak256(abi.encode(_item));
    }

    /// @notice Rebuilds the withdrawal an ETH withdrawal item was derived from.
    /// @param _item Item to convert. Must be an ETH withdrawal.
    /// @return The withdrawal transaction.
    function toWithdrawalTransaction(Item memory _item) internal pure returns (Types.WithdrawalTransaction memory) {
        return Types.WithdrawalTransaction({
            nonce: _item.messageNonce,
            sender: _item.from,
            target: _item.to,
            value: _item.amount,
            gasLimit: _item.gasLimit,
            data: _item.data
        });
    }

    /// @notice Normalizes a withdrawal transaction into an item.
    /// @dev Both the screening path and the release path build the item through this function, so
    ///      the identifier they derive agrees by construction. Changing it in one place without
    ///      the other would strand held items silently.
    /// @param _tx  Withdrawal transaction to convert.
    /// @param _uid The withdrawal's hash, which is what makes the item unique.
    /// @return The item.
    function fromWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        bytes32 _uid
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
            messageNonce: _tx.nonce,
            uid: _uid
        });
    }
}
