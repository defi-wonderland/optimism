// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { AddressAliasHelper } from "src/vendor/AddressAliasHelper.sol";
import { Asset, BridgeHookItem, Direction, Item } from "src/libraries/BridgeHookItem.sol";

// Interfaces
import { IBridgeHook } from "interfaces/universal/IBridgeHook.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IL1StandardBridge } from "interfaces/L1/IL1StandardBridge.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";

/// @title BridgeHookPortal
/// @notice The OptimismPortal's side of the bridge hook. It builds each item, asks the hook,
///         commits to the items the hook holds and moves the escrow of held token transfers.
library BridgeHookPortal {
    /// @notice The Portal's bridge hook state.
    /// @custom:field hook             Address of the bridge hook, zero if none is set.
    /// @custom:field inHook           Whether the hook or an escrow move is being called.
    /// @custom:field depositNonce     Counter that makes each screened deposit unique.
    /// @custom:field outstandingItems Number of items the hook holds.
    /// @custom:field heldDeposits     Held deposits, keyed by item identifier.
    /// @custom:field heldWithdrawals  Held withdrawals, keyed by item identifier.
    struct State {
        IBridgeHook hook;
        bool inHook;
        uint64 depositNonce;
        uint64 outstandingItems;
        mapping(bytes32 => bool) heldDeposits;
        mapping(bytes32 => bool) heldWithdrawals;
    }

    /// @notice Emitted when the bridge hook holds a deposit.
    /// @param id Identifier of the held deposit.
    event DepositHeld(bytes32 indexed id);

    /// @notice Emitted when the bridge hook holds a withdrawal.
    /// @param id             Identifier of the held withdrawal.
    /// @param withdrawalHash Hash of the withdrawal transaction.
    event WithdrawalHeld(bytes32 indexed id, bytes32 indexed withdrawalHash);

    /// @notice Thrown when the hook or an escrow move calls back into the Portal.
    error OptimismPortal_NoReentrancy();

    /// @notice Thrown when the caller is not the bridge hook.
    error OptimismPortal_NotBridgeHook();

    /// @notice Thrown when completing an item that is not held.
    error OptimismPortal_NotHeld();

    /// @notice Thrown when the ETH sent with a completion does not match the held item.
    error OptimismPortal_ValueMismatch();

    /// @notice Asks the hook about a deposit. On a hold, commits to its terms and hands its value
    ///         to the hook.
    /// @param self          The Portal's bridge hook state.
    /// @param _systemConfig The SystemConfig, for the bridge and messenger addresses.
    /// @param _from         Sender of the deposit, aliased if it is a contract.
    /// @param _to           Target address on L2.
    /// @param _value        ETH value to send to the recipient.
    /// @param _gasLimit     Amount of L2 gas purchased.
    /// @param _isCreation   Whether or not the transaction is a contract creation.
    /// @param _data         Data to trigger the recipient with.
    /// @return pass_ True if the deposit proceeds.
    function screenDeposit(
        State storage self,
        ISystemConfig _systemConfig,
        address _from,
        address _to,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes memory _data
    )
        internal
        returns (bool pass_)
    {
        if (self.inHook) revert OptimismPortal_NoReentrancy();

        Item memory item = _depositItem(self, _from, _to, _value, _gasLimit, _isCreation, _data);
        bytes memory message = recognizeTokenTransfer(item, _systemConfig);

        self.inHook = true;
        pass_ = self.hook.screenDeposit(item);
        if (!pass_) {
            bytes32 id = BridgeHookItem.hash(item);
            self.heldDeposits[id] = true;
            self.outstandingItems++;
            emit DepositHeld(id);

            if (item.asset == Asset.ERC20) _bridge(_systemConfig).holdERC20(Direction.Deposit, message);
            self.hook.holdDeposit{ value: msg.value }(item);
        }
        self.inHook = false;
    }

    /// @notice Asks the hook about a withdrawal being finalized. On a hold, commits to it and
    ///         hands its value to the hook.
    /// @param self            The Portal's bridge hook state.
    /// @param _systemConfig   The SystemConfig, for the bridge and messenger addresses.
    /// @param _tx             Withdrawal transaction.
    /// @param _withdrawalHash Hash of the withdrawal transaction.
    /// @param _finalizableAt  When the withdrawal became finalizable, with the proof being used.
    /// @return pass_ True if the withdrawal is paid.
    function screenWithdrawal(
        State storage self,
        ISystemConfig _systemConfig,
        Types.WithdrawalTransaction memory _tx,
        bytes32 _withdrawalHash,
        uint256 _finalizableAt
    )
        internal
        returns (bool pass_)
    {
        if (self.inHook) revert OptimismPortal_NoReentrancy();

        Item memory item = BridgeHookItem.fromWithdrawalTransaction(_tx);
        bytes memory message = recognizeTokenTransfer(item, _systemConfig);

        self.inHook = true;
        pass_ = self.hook.screenWithdrawal(item, _finalizableAt);
        if (!pass_) {
            bytes32 id = BridgeHookItem.hash(item);
            self.heldWithdrawals[id] = true;
            self.outstandingItems++;
            emit WithdrawalHeld(id, _withdrawalHash);

            if (item.asset == Asset.ERC20) _bridge(_systemConfig).holdERC20(Direction.Withdrawal, message);
            self.hook.holdWithdrawal{ value: _tx.value }(item);
        }
        self.inHook = false;
    }

    /// @notice Checks a held deposit against its commitment, deletes the commitment and takes
    ///         back the escrow of a token deposit. Only the hook can complete. The Portal then
    ///         emits the deposit.
    /// @param self          The Portal's bridge hook state.
    /// @param _systemConfig The SystemConfig, for the bridge address.
    /// @param _item         The held deposit.
    function completeDeposit(State storage self, ISystemConfig _systemConfig, Item memory _item) internal {
        if (msg.sender != address(self.hook)) revert OptimismPortal_NotBridgeHook();
        if (self.inHook) revert OptimismPortal_NoReentrancy();

        bytes32 id = BridgeHookItem.hash(_item);
        if (!self.heldDeposits[id]) revert OptimismPortal_NotHeld();
        if (msg.value != _item.ethAmount) revert OptimismPortal_ValueMismatch();

        delete self.heldDeposits[id];
        self.outstandingItems--;

        if (_item.asset == Asset.ERC20) _restoreERC20(self, _systemConfig, Direction.Deposit, _item.data);
    }

    /// @notice Checks a held withdrawal against its commitment, deletes the commitment and takes
    ///         back the escrow of a token withdrawal. Only the hook can complete. The Portal then
    ///         executes the returned transaction.
    /// @param self          The Portal's bridge hook state.
    /// @param _systemConfig The SystemConfig, for the bridge address.
    /// @param _item         The held withdrawal.
    /// @return tx_ The withdrawal transaction to execute.
    function completeWithdrawal(
        State storage self,
        ISystemConfig _systemConfig,
        Item memory _item
    )
        internal
        returns (Types.WithdrawalTransaction memory tx_)
    {
        if (msg.sender != address(self.hook)) revert OptimismPortal_NotBridgeHook();
        if (self.inHook) revert OptimismPortal_NoReentrancy();

        bytes32 id = BridgeHookItem.hash(_item);
        if (!self.heldWithdrawals[id]) revert OptimismPortal_NotHeld();
        tx_ = BridgeHookItem.toWithdrawalTransaction(_item);
        if (msg.value != tx_.value) revert OptimismPortal_ValueMismatch();

        delete self.heldWithdrawals[id];
        self.outstandingItems--;

        if (_item.asset == Asset.ERC20) _restoreERC20(self, _systemConfig, Direction.Withdrawal, _item.data);
    }

    /// @notice Marks an item as a token transfer if it is a message between the standard bridges.
    ///         Its tokens and amount stay in its data.
    /// @param _item         The item, built as an ETH item.
    /// @param _systemConfig The SystemConfig, for the bridge and messenger addresses.
    /// @return message_ The bridge's finalizeBridgeERC20 message, or empty if it is not one.
    function recognizeTokenTransfer(
        Item memory _item,
        ISystemConfig _systemConfig
    )
        internal
        view
        returns (bytes memory message_)
    {
        // Token transfers carry no ETH.
        if (_item.ethAmount != 0) return message_;

        bool isDeposit = _item.direction == Direction.Deposit;
        {
            address messenger = _systemConfig.l1CrossDomainMessenger();
            bool fromMessenger = isDeposit
                ? _item.aliased && _item.from == AddressAliasHelper.applyL1ToL2Alias(messenger)
                    && _item.to == Predeploys.L2_CROSS_DOMAIN_MESSENGER
                : _item.from == Predeploys.L2_CROSS_DOMAIN_MESSENGER && _item.to == messenger;
            if (!fromMessenger) return message_;
        }

        bytes memory message;
        {
            (bool ok, address sender, address target, bytes memory inner) =
                BridgeHookItem.decodeRelayMessage(_item.data);
            address bridge = _systemConfig.l1StandardBridge();

            // The messenger stamps the inner sender, so only the bridges can produce a match.
            bool betweenBridges = isDeposit
                ? sender == bridge && target == Predeploys.L2_STANDARD_BRIDGE
                : sender == Predeploys.L2_STANDARD_BRIDGE && target == bridge;
            if (!ok || !betweenBridges) return message_;
            message = inner;
        }

        (bool isTransfer,,,) = BridgeHookItem.decodeFinalizeBridgeERC20(message);
        if (!isTransfer) return message_;

        _item.asset = Asset.ERC20;
        message_ = message;
    }

    /// @notice Checks if a withdrawal is a relay through the L1CrossDomainMessenger that the
    ///         messenger did not record as successful.
    /// @param _tx           Withdrawal transaction.
    /// @param _systemConfig The SystemConfig, for the messenger address.
    /// @return True if the relay failed.
    function isFailedRelay(
        Types.WithdrawalTransaction memory _tx,
        ISystemConfig _systemConfig
    )
        internal
        view
        returns (bool)
    {
        address messenger = _systemConfig.l1CrossDomainMessenger();
        if (_tx.sender != Predeploys.L2_CROSS_DOMAIN_MESSENGER || _tx.target != messenger) return false;

        (bool ok, bytes32 messageHash) = BridgeHookItem.relayMessageHash(_tx.data);
        return !ok || !ICrossDomainMessenger(messenger).successfulMessages(messageHash);
    }

    /// @notice Builds the ETH item of a deposit, with the next deposit counter as its unique field.
    function _depositItem(
        State storage self,
        address _from,
        address _to,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes memory _data
    )
        private
        returns (Item memory item_)
    {
        item_.direction = Direction.Deposit;
        item_.asset = Asset.ETH;
        item_.from = _from;
        item_.aliased = _from != msg.sender;
        item_.to = _to;
        item_.ethAmount = msg.value;
        item_.l2Value = _value;
        item_.gasLimit = _gasLimit;
        item_.isCreation = _isCreation;
        item_.data = _data;
        item_.nonce = self.depositNonce++;
    }

    /// @notice Has the L1StandardBridge take back the escrow of a held token transfer.
    function _restoreERC20(
        State storage self,
        ISystemConfig _systemConfig,
        Direction _direction,
        bytes memory _data
    )
        private
    {
        (,,, bytes memory message) = BridgeHookItem.decodeRelayMessage(_data);
        self.inHook = true;
        _bridge(_systemConfig).restoreERC20(_direction, message);
        self.inHook = false;
    }

    /// @notice Returns the L1StandardBridge.
    function _bridge(ISystemConfig _systemConfig) private view returns (IL1StandardBridge) {
        return IL1StandardBridge(payable(_systemConfig.l1StandardBridge()));
    }
}
