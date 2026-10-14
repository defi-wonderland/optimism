// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Libraries
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";
import { EOA } from "src/libraries/EOA.sol";
import { Asset, BridgeHookItem, Direction, Item } from "src/libraries/BridgeHookItem.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOptimismMintableERC20 } from "interfaces/universal/IOptimismMintableERC20.sol";
import { ILegacyMintableERC20 } from "interfaces/legacy/ILegacyMintableERC20.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IBridgeHook } from "interfaces/universal/IBridgeHook.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";

/// @custom:upgradeable
/// @title StandardBridge
/// @notice StandardBridge is a base contract for the L1 and L2 standard ERC20 bridges. It handles
///         the core bridging logic, including escrowing tokens that are native to the local chain
///         and minting/burning tokens that are native to the remote chain.
abstract contract StandardBridge is Initializable {
    using SafeERC20 for IERC20;

    /// @notice The L2 gas limit set when eth is depoisited using the receive() function.
    uint32 internal constant RECEIVE_DEFAULT_GAS_LIMIT = 200_000;

    /// @custom:legacy
    /// @custom:spacer messenger
    /// @notice Spacer for backwards compatibility.
    bytes30 private spacer_0_2_30;

    /// @custom:legacy
    /// @custom:spacer l2TokenBridge
    /// @notice Spacer for backwards compatibility.
    address private spacer_1_0_20;

    /// @notice Mapping that stores deposits for a given pair of local and remote tokens.
    mapping(address => mapping(address => uint256)) public deposits;

    /// @notice Messenger contract on this domain.
    /// @custom:network-specific
    ICrossDomainMessenger public messenger;

    /// @notice Corresponding bridge on the other domain.
    /// @custom:network-specific
    StandardBridge public otherBridge;

    /// @notice Address of the bridge hook, gated by the BRIDGE_HOOK feature. Only ever set on L1:
    ///         `_isUsingBridgeHook` is false in this contract and only L1StandardBridge overrides
    ///         it, so every hook path below is unreachable on L2.
    /// @custom:network-specific
    IBridgeHook public bridgeHook;

    /// @notice Counter this contract folds into the identifier of every item it assigns, which is
    ///         what makes two otherwise identical items distinct. Shared by both directions.
    uint64 public erc20ItemNonce;

    /// @notice Terms committed to for token deposits deferred to the hook.
    mapping(bytes32 => bool) public pendingERC20Deposits;

    /// @notice Terms committed to for token withdrawals that finalized into holding.
    /// @dev The commitment is this contract's own because the hold happens here: the hook fires
    ///      inside `finalizeBridgeERC20`, nested in the messenger relay, by which point the Portal
    ///      has already finished with the withdrawal and cannot be asked to release it. The
    ///      identifier still borrows the protocol's withdrawal hash wherever one is available,
    ///      which is what `_erc20WithdrawalUid` resolves.
    mapping(bytes32 => bool) public heldERC20Withdrawals;

    /// @notice Items this contract has deferred to the hook and not yet completed.
    /// @dev Both completion paths are gated on the live `bridgeHook` address, so repointing or
    ///      unsetting it while anything is outstanding would strand the tokens held against it.
    ///      `setBridgeHook` reads this and refuses.
    uint64 public outstandingBridgeHookItems;

    /// @notice Reserve extra slots (to a total of 50) in the storage layout for future upgrades.
    ///         A gap size of 41 was chosen here, so that the first slot used in a child contract
    ///         would be a multiple of 50.
    uint256[41] private __gap;

    /// @notice Emitted when an ETH bridge is initiated to the other chain.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of ETH sent.
    /// @param extraData Extra data sent with the transaction.
    event ETHBridgeInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @notice Emitted when an ETH bridge is finalized on this chain.
    /// @param from      Address of the sender.
    /// @param to        Address of the receiver.
    /// @param amount    Amount of ETH sent.
    /// @param extraData Extra data sent with the transaction.
    event ETHBridgeFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @notice Emitted when an ERC20 bridge is initiated to the other chain.
    /// @param localToken  Address of the ERC20 on this chain.
    /// @param remoteToken Address of the ERC20 on the remote chain.
    /// @param from        Address of the sender.
    /// @param to          Address of the receiver.
    /// @param amount      Amount of the ERC20 sent.
    /// @param extraData   Extra data sent with the transaction.
    event ERC20BridgeInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @notice Emitted when an ERC20 bridge is finalized on this chain.
    /// @param localToken  Address of the ERC20 on this chain.
    /// @param remoteToken Address of the ERC20 on the remote chain.
    /// @param from        Address of the sender.
    /// @param to          Address of the receiver.
    /// @param amount      Amount of the ERC20 sent.
    /// @param extraData   Extra data sent with the transaction.
    event ERC20BridgeFinalized(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @notice Emitted when a token deposit is held by the bridge hook. No escrow is recorded and
    ///         no message is sent until the deposit completes.
    /// @param id          Identifier of the held deposit.
    /// @param uid         Uniqueness source folded into the identifier.
    /// @param localToken  Address of the ERC20 on this chain.
    /// @param remoteToken Address of the ERC20 on the remote chain.
    /// @param from        Address of the sender.
    /// @param to          Address of the receiver.
    /// @param amount      Amount of the ERC20 held.
    event ERC20DepositPending(
        bytes32 indexed id,
        bytes32 uid,
        address indexed localToken,
        address remoteToken,
        address indexed from,
        address to,
        uint256 amount
    );

    /// @notice Emitted when a token withdrawal finalizes into holding rather than paying its
    ///         recipient.
    /// @param id          Identifier of the held withdrawal.
    /// @param uid         Uniqueness source folded into the identifier, the withdrawal's own hash
    ///                    on the normal path.
    /// @param localToken  Address of the ERC20 on this chain.
    /// @param remoteToken Address of the ERC20 on the remote chain.
    /// @param from        Address of the sender.
    /// @param to          Address of the receiver.
    /// @param amount      Amount of the ERC20 held.
    event ERC20WithdrawalHeld(
        bytes32 indexed id,
        bytes32 uid,
        address indexed localToken,
        address remoteToken,
        address indexed from,
        address to,
        uint256 amount
    );

    /// @notice Thrown when a hook-only entry point is called by anyone else.
    error StandardBridge_NotBridgeHook();

    /// @notice Thrown when an item is supplied that this contract never committed to.
    error StandardBridge_UncommittedItem();

    /// @notice Thrown when an item is supplied to the wrong completion entry point.
    error StandardBridge_WrongItemKind();

    /// @notice Only allow EOAs to call the functions. Note that this is not safe against contracts
    ///         calling code within their constructors, but also doesn't really matter since we're
    ///         just trying to prevent users accidentally depositing with smart contract wallets.
    modifier onlyEOA() {
        require(EOA.isSenderEOA(), "StandardBridge: function can only be called from an EOA");
        _;
    }

    /// @notice Ensures that the caller is a cross-chain message from the other bridge.
    modifier onlyOtherBridge() {
        require(
            msg.sender == address(messenger) && messenger.xDomainMessageSender() == address(otherBridge),
            "StandardBridge: function can only be called from the other bridge"
        );
        _;
    }

    /// @notice Initializer.
    /// @param _messenger   Contract for CrossDomainMessenger on this network.
    /// @param _otherBridge Contract for the other StandardBridge contract.
    function __StandardBridge_init(
        ICrossDomainMessenger _messenger,
        StandardBridge _otherBridge
    )
        internal
        onlyInitializing
    {
        messenger = _messenger;
        otherBridge = _otherBridge;
    }

    /// @notice Allows EOAs to bridge ETH by sending directly to the bridge.
    ///         Must be implemented by contracts that inherit.
    receive() external payable virtual;

    /// @notice Getter for messenger contract.
    ///         Public getter is legacy and will be removed in the future. Use `messenger` instead.
    /// @return Contract of the messenger on this domain.
    /// @custom:legacy
    function MESSENGER() external view returns (ICrossDomainMessenger) {
        return messenger;
    }

    /// @notice Getter for the other bridge contract.
    ///         Public getter is legacy and will be removed in the future. Use `otherBridge` instead.
    /// @return Contract of the bridge on the other network.
    /// @custom:legacy
    function OTHER_BRIDGE() external view returns (StandardBridge) {
        return otherBridge;
    }

    /// @notice This function should return true if the contract is paused.
    ///         On L1 this function will check the SuperchainConfig for its paused status.
    ///         On L2 this function should be a no-op.
    /// @return Whether or not the contract is paused.
    function paused() public view virtual returns (bool) {
        return false;
    }

    /// @notice Sends ETH to the sender's address on the other chain.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeETH(uint32 _minGasLimit, bytes calldata _extraData) public payable onlyEOA {
        _initiateBridgeETH(msg.sender, msg.sender, msg.value, _minGasLimit, _extraData);
    }

    /// @notice Sends ETH to a receiver's address on the other chain. Note that if ETH is sent to a
    ///         smart contract and the call fails, the ETH will be temporarily locked in the
    ///         StandardBridge on the other chain until the call is replayed. If the call cannot be
    ///         replayed with any amount of gas (call always reverts), then the ETH will be
    ///         permanently locked in the StandardBridge on the other chain. ETH will also
    ///         be locked if the receiver is the other bridge, because finalizeBridgeETH will revert
    ///         in that case.
    /// @param _to          Address of the receiver.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeETHTo(address _to, uint32 _minGasLimit, bytes calldata _extraData) public payable {
        _initiateBridgeETH(msg.sender, _to, msg.value, _minGasLimit, _extraData);
    }

    /// @notice Sends ERC20 tokens to the sender's address on the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeERC20(
        address _localToken,
        address _remoteToken,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        public
        virtual
        onlyEOA
    {
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @notice Sends ERC20 tokens to a receiver's address on the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        public
        virtual
    {
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

    /// @notice Finalizes an ETH bridge on this chain. Can only be triggered by the other
    ///         StandardBridge contract on the remote chain.
    /// @param _from      Address of the sender.
    /// @param _to        Address of the receiver.
    /// @param _amount    Amount of ETH being bridged.
    /// @param _extraData Extra data to be sent with the transaction. Note that the recipient will
    ///                   not be triggered with this data, but it will be emitted and can be used
    ///                   to identify the transaction.
    function finalizeBridgeETH(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        public
        payable
        onlyOtherBridge
    {
        require(paused() == false, "StandardBridge: paused");
        require(msg.value == _amount, "StandardBridge: amount sent does not match amount required");
        require(_to != address(this), "StandardBridge: cannot send to self");
        require(_to != address(messenger), "StandardBridge: cannot send to messenger");

        // Emit the correct events. By default this will be _amount, but child
        // contracts may override this function in order to emit legacy events as well.
        _emitETHBridgeFinalized(_from, _to, _amount, _extraData);

        bool success = SafeCall.call(_to, gasleft(), _amount, hex"");
        require(success, "StandardBridge: ETH transfer failed");
    }

    /// @notice Finalizes an ERC20 bridge on this chain. Can only be triggered by the other
    ///         StandardBridge contract on the remote chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the ERC20 being bridged.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function finalizeBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        public
        onlyOtherBridge
    {
        require(paused() == false, "StandardBridge: paused");

        bool isMintable = _isOptimismMintableERC20(_localToken);
        if (isMintable) {
            require(
                _isCorrectTokenPair(_localToken, _remoteToken),
                "StandardBridge: wrong remote token for Optimism Mintable ERC20 local token"
            );
        }

        // The one check in scope on the withdrawal side, immediately before value is released on
        // this chain. It exists because designations change during the withdrawal window: an item
        // screened at initiation could have its address designated during the wait and still
        // release.
        if (_isUsingBridgeHook()) {
            if (!_screenERC20Withdrawal(_localToken, _remoteToken, _from, _to, _amount, _extraData, isMintable)) {
                // Held. The recipient is not paid and the value now sits with the hook.
                return;
            }
        }

        if (isMintable) {
            IOptimismMintableERC20(_localToken).mint(_to, _amount);
        } else {
            deposits[_localToken][_remoteToken] = deposits[_localToken][_remoteToken] - _amount;
            IERC20(_localToken).safeTransfer(_to, _amount);
        }

        // Emit the correct events. By default this will be ERC20BridgeFinalized, but child
        // contracts may override this function in order to emit legacy events as well.
        _emitERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Completes a token deposit that the bridge hook held. Only the hook can call this.
    /// @dev Three things separate correct accounting here from a mint from nothing. The commitment
    ///      means the only terms that can complete are the ones the user escrowed, so the hook
    ///      cannot substitute a `remoteToken` and inflate a pairing nobody escrowed against, or
    ///      assert a `from` it does not control. The escrow and the message are both recorded for
    ///      the amount that actually arrived, measured as a balance delta. And only the hook can
    ///      reach this at all.
    /// @param _item The held deposit.
    function completeERC20Deposit(Item memory _item) external {
        if (msg.sender != address(bridgeHook)) revert StandardBridge_NotBridgeHook();
        if (_item.direction != Direction.Deposit || _item.asset != Asset.ERC20) {
            revert StandardBridge_WrongItemKind();
        }

        bytes32 id = BridgeHookItem.hash(_item);
        if (!pendingERC20Deposits[id]) revert StandardBridge_UncommittedItem();

        // Delete the commitment before any external call, so an item completes at most once.
        delete pendingERC20Deposits[id];
        outstandingBridgeHookItems--;

        // Settle custody the way the submission path would have. The two branches want different
        // things, so they take different routes rather than a shared one that suits neither.
        //
        // The mintable branch burns straight out of the hook's balance, undoing the mint that
        // relocated custody there. Nothing has to arrive in this contract first, because there is
        // no escrow to record: what matters is that the amount burned equals the amount messaged
        // to L2, and the commitment already fixes that amount. A short balance reverts, which is
        // the safe direction.
        //
        // The escrow branch has to end up actually holding the tokens, so it pulls them and
        // measures what arrived. Recording escrow for an asserted amount while receiving a
        // different one is the token-side unbacked mint.
        bool isMintable = _isOptimismMintableERC20(_item.localToken);
        uint256 amount;
        if (isMintable) {
            amount = _item.amount;
            IOptimismMintableERC20(_item.localToken).burn(address(bridgeHook), amount);
        } else {
            amount = _pullFromBridgeHook(_item.localToken, _item.amount);
        }

        _finishBridgeERC20(
            _item.localToken,
            _item.remoteToken,
            _item.from,
            _item.to,
            amount,
            uint32(_item.gasLimit),
            _item.data,
            isMintable
        );
    }

    /// @notice Releases a token withdrawal that the bridge hook held, paying its original
    ///         recipient. Only the hook can call this.
    /// @dev The recipient-facing transfer is performed here, from the address the token and the
    ///      receiver expect, because they see `msg.sender`: a hook-sent transfer would break
    ///      caller-gated tokens, caller-checking receive hooks and indexers matching a single
    ///      bridge outflow. Permissioned tokens are both the most likely to gate on the caller and
    ///      the most likely to be on a screening chain.
    ///
    ///      This contract never mints on the release path. Minting stays at finalization, driven
    ///      by a message the messenger already authenticated, because a bridge minting on
    ///      hook-supplied terms would be a new unbacked-issuance surface. `deposits` is not
    ///      touched either: it was decremented when the tokens left for the hook.
    /// @param _item The held withdrawal.
    function completeERC20Withdrawal(Item memory _item) external {
        if (msg.sender != address(bridgeHook)) revert StandardBridge_NotBridgeHook();
        if (_item.direction != Direction.Withdrawal || _item.asset != Asset.ERC20) {
            revert StandardBridge_WrongItemKind();
        }

        // This is the recipient-facing leg that finalizeBridgeERC20 would have performed, and that
        // function is pause-gated, so this one is too. The hook checks the pause as well, but that
        // is a check it must keep through every upgrade rather than a property the protocol
        // enforces. The invariant is that the hook is never a route for value the guardian froze.
        require(paused() == false, "StandardBridge: paused");

        bytes32 id = BridgeHookItem.hash(_item);
        if (!heldERC20Withdrawals[id]) revert StandardBridge_UncommittedItem();

        delete heldERC20Withdrawals[id];
        outstandingBridgeHookItems--;

        uint256 delta = _pullFromBridgeHook(_item.localToken, _item.amount);

        IERC20(_item.localToken).safeTransfer(_item.to, delta);
        _emitERC20BridgeFinalized(_item.localToken, _item.remoteToken, _item.from, _item.to, delta, _item.data);
    }

    /// @notice Screens a token deposit through the bridge hook and, on a hold, commits to its
    ///         terms and hands the tokens over.
    /// @dev The mirror of `_screenERC20Withdrawal`: decide first with nothing moving, then commit,
    ///      then move the value, then tell the hook it is holding.
    /// @param _isMintable Whether the local token is an OptimismMintableERC20, already resolved by
    ///                    the caller so the ERC-165 probes are not repeated.
    /// @return pass_ True if the deposit should proceed, false if it was held.
    function _screenERC20Deposit(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData,
        bool _isMintable
    )
        internal
        returns (bool pass_)
    {
        uint64 nonce = erc20ItemNonce;
        erc20ItemNonce = nonce + 1;

        Item memory item = Item({
            direction: Direction.Deposit,
            asset: Asset.ERC20,
            from: _from,
            aliased: false,
            to: _to,
            localToken: _localToken,
            remoteToken: _remoteToken,
            amount: _amount,
            value: 0,
            gasLimit: _minGasLimit,
            isCreation: false,
            data: _extraData,
            messageNonce: 0,
            uid: bytes32(uint256(nonce))
        });

        pass_ = bridgeHook.screenDeposit(item);
        if (pass_) return true;

        bytes32 id = BridgeHookItem.hash(item);
        pendingERC20Deposits[id] = true;
        outstandingBridgeHookItems++;
        emit ERC20DepositPending(id, bytes32(uint256(nonce)), _localToken, _remoteToken, _from, _to, _amount);

        _holdERC20Deposit(_localToken, _from, _amount, _isMintable);

        bridgeHook.holdDeposit(item);
    }

    /// @notice Screens a token withdrawal through the bridge hook and, on a hold, commits to its
    ///         terms and hands the tokens over.
    /// @dev The escrow branch moves tokens out of this contract; the mintable branch mints to the
    ///      hook, because for a token native to the remote chain nothing exists to take custody of
    ///      until this contract creates it, and minting is bridge-only.
    /// @return pass_ True if the withdrawal should be paid out here, false if it was held.
    function _screenERC20Withdrawal(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData,
        bool _isMintable
    )
        internal
        returns (bool pass_)
    {
        bytes32 uid = _erc20WithdrawalUid();

        Item memory item = Item({
            direction: Direction.Withdrawal,
            asset: Asset.ERC20,
            from: _from,
            aliased: false,
            to: _to,
            localToken: _localToken,
            remoteToken: _remoteToken,
            amount: _amount,
            value: 0,
            gasLimit: 0,
            isCreation: false,
            data: _extraData,
            messageNonce: 0,
            uid: uid
        });

        pass_ = bridgeHook.screenWithdrawal(item);
        if (pass_) return true;

        bytes32 id = BridgeHookItem.hash(item);
        heldERC20Withdrawals[id] = true;
        outstandingBridgeHookItems++;
        emit ERC20WithdrawalHeld(id, uid, _localToken, _remoteToken, _from, _to, _amount);

        if (_isMintable) {
            IOptimismMintableERC20(_localToken).mint(address(bridgeHook), _amount);
        } else {
            deposits[_localToken][_remoteToken] = deposits[_localToken][_remoteToken] - _amount;
            IERC20(_localToken).safeTransfer(address(bridgeHook), _amount);
        }

        bridgeHook.holdWithdrawal(item);
    }

    /// @notice Takes tokens back from the bridge hook on a completion path and returns the amount
    ///         that actually arrived.
    /// @dev Pulled rather than pushed so that the measurement and the transfer are the same act.
    ///      The hook approves this contract for the item's amount immediately before calling.
    /// @param _localToken Token to pull.
    /// @param _amount     Amount the item's committed terms name.
    /// @return delta_ The measured increase in this contract's balance.
    function _pullFromBridgeHook(address _localToken, uint256 _amount) internal returns (uint256 delta_) {
        uint256 balanceBefore = IERC20(_localToken).balanceOf(address(this));
        IERC20(_localToken).safeTransferFrom(address(bridgeHook), address(this), _amount);
        delta_ = IERC20(_localToken).balanceOf(address(this)) - balanceBefore;
    }

    /// @notice Whether this contract should defer to a bridge hook. False here, so every hook path
    ///         in this contract is unreachable, and overridden on L1 where the feature lives.
    /// @return bool True if a bridge hook is configured and its feature is enabled.
    function _isUsingBridgeHook() internal view virtual returns (bool) {
        return false;
    }

    /// @notice The OptimismPortal, read to identify the withdrawal currently being finalized.
    ///         Zero here, and overridden on L1 where a Portal exists.
    /// @return address The Portal, or zero.
    function _optimismPortal() internal view virtual returns (address) {
        return address(0);
    }

    /// @notice What makes a token withdrawal distinct from an otherwise identical one.
    /// @dev A token withdrawal arrives two frames below the Portal, inside a messenger relay, and
    ///      neither frame passes the withdrawal's identity down. The Portal exposes it for exactly
    ///      this, so the item is identified by the protocol's own hash rather than by a counter
    ///      this contract mints. That matters because the hash is derivable from the L2 event the
    ///      moment the withdrawal is initiated, which is what lets a verdict be recorded during
    ///      the challenge window and the withdrawal pay out in one transaction.
    ///
    ///      The counter is the fallback for the one path with no Portal frame: a relay that
    ///      previously failed can be replayed directly at the messenger. Such an item cannot have
    ///      been cleared in advance, so it is held. Counter values are small integers and the
    ///      normal path's are keccak outputs, so the two spaces do not collide.
    /// @return uid_ The uniqueness source for this item.
    function _erc20WithdrawalUid() internal returns (bytes32 uid_) {
        address portal = _optimismPortal();
        if (portal != address(0)) {
            uid_ = IOptimismPortal2(payable(portal)).currentWithdrawalHash();
            if (uid_ != bytes32(0)) return uid_;
        }

        uint64 nonce = erc20ItemNonce;
        erc20ItemNonce = nonce + 1;
        uid_ = bytes32(uint256(nonce));
    }

    /// @notice Initiates a bridge of ETH through the CrossDomainMessenger.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of ETH being bridged.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function _initiateBridgeETH(
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
    {
        // ETH bridged from here is screened at the OptimismPortal, which is where the value ends
        // up and which every route reaches. The hook resolves the parties through the envelope, so
        // the screen names the depositor and the recipient rather than this contract and its
        // counterpart, and a held deposit keeps the ETH at the module.
        //
        // The one cost is ordering: the event below and the messenger's own are emitted before the
        // Portal decides, so a held deposit leaves them behind until it completes. Closing the
        // route would remove that at the price of breaking the entry point for every clean user,
        // which is the worse trade.
        require(msg.value == _amount, "StandardBridge: bridging ETH must include sufficient ETH value");

        // Emit the correct events. By default this will be _amount, but child
        // contracts may override this function in order to emit legacy events as well.
        _emitETHBridgeInitiated(_from, _to, _amount, _extraData);

        messenger.sendMessage{ value: _amount }({
            _target: address(otherBridge),
            _message: abi.encodeWithSelector(this.finalizeBridgeETH.selector, _from, _to, _amount, _extraData),
            _minGasLimit: _minGasLimit
        });
    }

    /// @notice Sends ERC20 tokens to a receiver's address on the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function _initiateBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
    {
        require(msg.value == 0, "StandardBridge: cannot send value");

        bool isMintable = _isOptimismMintableERC20(_localToken);
        if (isMintable) {
            require(
                _isCorrectTokenPair(_localToken, _remoteToken),
                "StandardBridge: wrong remote token for Optimism Mintable ERC20 local token"
            );
        }

        // Screening happens here, before any value moves and before the message is sent, because
        // this is the only place a token deposit can be intercepted at all. By the time the
        // OptimismPortal is reached the tokens are already escrowed or burned and it sees no
        // value, so a gate there could name the parties but never take custody.
        //
        // Nothing has moved yet, so a hold moves the value straight to the hook in one step and a
        // pass does exactly what an unmodified bridge does. Taking custody first and handing it
        // over afterwards would cost an extra transfer on the escrow branch, and on the mintable
        // branch it would force the depositor to approve this contract, which stock does not
        // require because `burn` is `onlyBridge` and takes no allowance.
        if (_isUsingBridgeHook()) {
            bool passed = _screenERC20Deposit(
                _localToken, _remoteToken, _from, _to, _amount, _minGasLimit, _extraData, isMintable
            );

            // Escrow is not recorded and no message is sent, so nothing mints on L2 and this
            // contract's books never learn the item.
            if (!passed) return;
        }

        if (isMintable) {
            IOptimismMintableERC20(_localToken).burn(_from, _amount);
        } else {
            IERC20(_localToken).safeTransferFrom(_from, address(this), _amount);
        }

        _finishBridgeERC20(_localToken, _remoteToken, _from, _to, _amount, _minGasLimit, _extraData, isMintable);
    }

    /// @notice Moves a held token deposit's value to the bridge hook.
    /// @dev The escrow branch sends the depositor's tokens straight to the hook on the allowance
    ///      they already gave this contract. The mintable branch burns from the depositor exactly
    ///      as an unmodified deposit would and mints the same amount to the hook, which is a
    ///      relocation of custody rather than issuance: the amount was burned from the same
    ///      depositor in the same call, on terms this contract received as typed arguments with
    ///      nothing supplied from outside. Doing it this way keeps the stock interface, where a
    ///      mintable deposit needs no approval at all.
    /// @param _localToken Token being deposited.
    /// @param _from       Depositor.
    /// @param _amount     Amount held.
    /// @param _isMintable Whether the local token is an OptimismMintableERC20.
    function _holdERC20Deposit(address _localToken, address _from, uint256 _amount, bool _isMintable) internal {
        if (_isMintable) {
            IOptimismMintableERC20(_localToken).burn(_from, _amount);
            IOptimismMintableERC20(_localToken).mint(address(bridgeHook), _amount);
        } else {
            IERC20(_localToken).safeTransferFrom(_from, address(bridgeHook), _amount);
        }
    }

    /// @notice Records the escrow for a token deposit and sends the L2 message. Reached at
    ///         submission by a deposit that passes, and from `completeERC20Deposit` by one that
    ///         was held.
    /// @dev The escrow and the message are recorded for the same amount, always. Sending for an
    ///      asserted amount while accounting for a measured one is the token-side unbacked mint.
    /// @param _isMintable Whether the local token is an OptimismMintableERC20, already resolved by
    ///                    the caller so the ERC-165 probes are not repeated.
    function _finishBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData,
        bool _isMintable
    )
        internal
    {
        // Custody was already settled by the caller: burned from the depositor on the submission
        // path, or burned from this contract's own balance on the completion path. All that is
        // left here is the escrow accounting, which only the escrow branch has.
        if (!_isMintable) {
            deposits[_localToken][_remoteToken] = deposits[_localToken][_remoteToken] + _amount;
        }

        // Emit the correct events. By default this will be ERC20BridgeInitiated, but child
        // contracts may override this function in order to emit legacy events as well.
        _emitERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);

        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeWithSelector(
                this.finalizeBridgeERC20.selector,
                // Because this call will be executed on the remote chain, we reverse the order of
                // the remote and local token addresses relative to their order in the
                // finalizeBridgeERC20 function.
                _remoteToken,
                _localToken,
                _from,
                _to,
                _amount,
                _extraData
            ),
            _minGasLimit: _minGasLimit
        });
    }

    /// @notice Checks if a given address is an OptimismMintableERC20. Not perfect, but good enough.
    ///         Just the way we like it.
    /// @param _token Address of the token to check.
    /// @return True if the token is an OptimismMintableERC20.
    function _isOptimismMintableERC20(address _token) internal view returns (bool) {
        return ERC165Checker.supportsInterface(_token, type(ILegacyMintableERC20).interfaceId)
            || ERC165Checker.supportsInterface(_token, type(IOptimismMintableERC20).interfaceId);
    }

    /// @notice Checks if the "other token" is the correct pair token for the OptimismMintableERC20.
    ///         Calls can be saved in the future by combining this logic with
    ///         `_isOptimismMintableERC20`.
    /// @param _mintableToken OptimismMintableERC20 to check against.
    /// @param _otherToken    Pair token to check.
    /// @return True if the other token is the correct pair token for the OptimismMintableERC20.
    function _isCorrectTokenPair(address _mintableToken, address _otherToken) internal view returns (bool) {
        if (ERC165Checker.supportsInterface(_mintableToken, type(ILegacyMintableERC20).interfaceId)) {
            return _otherToken == ILegacyMintableERC20(_mintableToken).l1Token();
        } else {
            return _otherToken == IOptimismMintableERC20(_mintableToken).remoteToken();
        }
    }

    /// @notice Emits the ETHBridgeInitiated event and if necessary the appropriate legacy event
    ///         when an ETH bridge is finalized on this chain.
    /// @param _from      Address of the sender.
    /// @param _to        Address of the receiver.
    /// @param _amount    Amount of ETH sent.
    /// @param _extraData Extra data sent with the transaction.
    function _emitETHBridgeInitiated(
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        virtual
    {
        emit ETHBridgeInitiated(_from, _to, _amount, _extraData);
    }

    /// @notice Emits the ETHBridgeFinalized and if necessary the appropriate legacy event when an
    ///         ETH bridge is finalized on this chain.
    /// @param _from      Address of the sender.
    /// @param _to        Address of the receiver.
    /// @param _amount    Amount of ETH sent.
    /// @param _extraData Extra data sent with the transaction.
    function _emitETHBridgeFinalized(
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        virtual
    {
        emit ETHBridgeFinalized(_from, _to, _amount, _extraData);
    }

    /// @notice Emits the ERC20BridgeInitiated event and if necessary the appropriate legacy
    ///         event when an ERC20 bridge is initiated to the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the ERC20 on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the ERC20 sent.
    /// @param _extraData   Extra data sent with the transaction.
    function _emitERC20BridgeInitiated(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        virtual
    {
        emit ERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Emits the ERC20BridgeFinalized event and if necessary the appropriate legacy
    ///         event when an ERC20 bridge is initiated to the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the ERC20 on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the ERC20 sent.
    /// @param _extraData   Extra data sent with the transaction.
    function _emitERC20BridgeFinalized(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        virtual
    {
        emit ERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }
}
