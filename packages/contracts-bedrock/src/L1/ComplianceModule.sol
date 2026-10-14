// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ProxyAdminOwnedBase } from "src/universal/ProxyAdminOwnedBase.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { AddressAliasHelper } from "src/vendor/AddressAliasHelper.sol";
import { Asset, BridgeHookItem, Direction, Item } from "src/libraries/BridgeHookItem.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IBridgeHook } from "interfaces/universal/IBridgeHook.sol";
import { IPolicy } from "interfaces/L1/IPolicy.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IOptimismMintableERC20 } from "interfaces/universal/IOptimismMintableERC20.sol";
import { ILegacyMintableERC20 } from "interfaces/legacy/ILegacyMintableERC20.sol";

/// @custom:proxied true
/// @title ComplianceModule
/// @notice Bridge hook that holds the value of the items its policy does not clear, keeps their
///         verdicts, and completes them on their original terms once they are cleared.
contract ComplianceModule is Initializable, ProxyAdminOwnedBase, IBridgeHook, ISemver {
    using SafeERC20 for IERC20;

    /// @notice State of an item in the verdict registry.
    /// @custom:field heldAt    When the item was held, zero if it is not held.
    /// @custom:field clearedAt When a clear verdict was recorded, zero if there is none.
    struct Record {
        uint64 heldAt;
        uint64 clearedAt;
    }

    /// @notice The OptimismPortal, the only caller of the hook functions.
    IOptimismPortal2 public immutable portal;

    /// @notice The L1StandardBridge, approved to take tokens back when a token item completes.
    address public immutable bridge;

    /// @notice The L1CrossDomainMessenger, whose envelopes the module unwraps.
    address public immutable l1CrossDomainMessenger;

    /// @notice The only address verdicts are taken from.
    address public policy;

    /// @notice While set, every new item proceeds without asking the policy.
    bool public disabled;

    /// @notice Verdict registry, keyed by item identifier.
    mapping(bytes32 => Record) public items;

    /// @notice Tokens held per L1 token and L2 token, like the L1StandardBridge's deposits.
    mapping(address => mapping(address => uint256)) public heldTokens;

    /// @notice Tokens held per L1 token, across its L2 tokens.
    mapping(address => uint256) public heldTokenTotal;

    /// @notice Emitted when an item is held.
    /// @param id   Identifier of the item.
    /// @param item The item.
    event Held(bytes32 indexed id, Item item);

    /// @notice Emitted when a clear verdict is recorded.
    /// @param id Identifier of the item.
    /// @param at Time the verdict was recorded.
    event Cleared(bytes32 indexed id, uint64 at);

    /// @notice Emitted when a clear verdict is revoked.
    /// @param id Identifier of the item.
    event ClearanceRevoked(bytes32 indexed id);

    /// @notice Emitted when a held item completes.
    /// @param id Identifier of the item.
    event Completed(bytes32 indexed id);

    /// @notice Emitted when the policy is set.
    /// @param policy Address of the policy.
    event PolicySet(address indexed policy);

    /// @notice Emitted when the module is disabled or enabled.
    /// @param disabled Whether the module is disabled.
    event DisabledSet(bool disabled);

    /// @notice Thrown when a hook function is not called by the OptimismPortal, with this module as
    ///         its bridge hook.
    error ComplianceModule_NotPortal();

    /// @notice Thrown when a verdict function is not called by the policy.
    error ComplianceModule_NotPolicy();

    /// @notice Thrown when completing an item that is not held.
    error ComplianceModule_NotHeld();

    /// @notice Thrown when completing an item that has no clear verdict.
    error ComplianceModule_NotCleared();

    /// @notice Thrown when the policy declines a completion.
    error ComplianceModule_Declined();

    /// @notice Thrown when the ETH sent with a hold does not match the item.
    error ComplianceModule_ValueMismatch();

    /// @notice Thrown when the policy is set to the zero address.
    error ComplianceModule_ZeroAddress();

    /// @notice Thrown when the module's balance of a token does not cover what it holds.
    error ComplianceModule_Undelivered();

    /// @notice Thrown when a token item's data is not a token transfer.
    error ComplianceModule_NotTokenTransfer();

    /// @notice Semantic version.
    /// @custom:semver 0.1.0
    function version() public pure virtual returns (string memory) {
        return "0.1.0";
    }

    /// @param _portal                 The OptimismPortal.
    /// @param _bridge                 The L1StandardBridge.
    /// @param _l1CrossDomainMessenger The L1CrossDomainMessenger.
    constructor(IOptimismPortal2 _portal, address _bridge, address _l1CrossDomainMessenger) {
        portal = _portal;
        bridge = _bridge;
        l1CrossDomainMessenger = _l1CrossDomainMessenger;
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _policy Address of the policy.
    function initialize(address _policy) external initializer {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        _setPolicy(_policy);
    }

    /// @notice Sets the policy. Only callable by the ProxyAdmin owner.
    /// @param _policy Address of the policy.
    function setPolicy(address _policy) external {
        _assertOnlyProxyAdminOwner();
        _setPolicy(_policy);
    }

    /// @notice Disables or enables screening of new items. Only callable by the ProxyAdmin owner.
    /// @param _disabled Whether the module is disabled.
    function setDisabled(bool _disabled) external {
        _assertOnlyProxyAdminOwner();
        disabled = _disabled;
        emit DisabledSet(_disabled);
    }

    /// @inheritdoc IBridgeHook
    function screenDeposit(Item calldata _item) external returns (bool pass_) {
        _assertPortal();
        if (disabled) return true;
        pass_ = IPolicy(policy).screen(_item, effectiveParties(_item));
    }

    /// @inheritdoc IBridgeHook
    function holdDeposit(Item calldata _item) external payable {
        _assertPortal();
        _hold(_item);
    }

    /// @inheritdoc IBridgeHook
    /// @dev The module keeps no timing rule. When to hold is the policy's call, from `_finalizableAt`.
    function screenWithdrawal(Item calldata _item, uint256 _finalizableAt) external returns (bool pass_) {
        _assertPortal();
        if (disabled) return true;

        bytes32 id = BridgeHookItem.hash(_item);
        pass_ = IPolicy(policy).screenRelease(_item, effectiveParties(_item), items[id].clearedAt, _finalizableAt);

        // A verdict recorded before finalization is not needed once the withdrawal is paid.
        if (pass_) delete items[id];
    }

    /// @inheritdoc IBridgeHook
    function holdWithdrawal(Item calldata _item) external payable {
        _assertPortal();
        _hold(_item);
    }

    /// @notice Records a clear verdict for an item, which may not exist yet. Only callable by the
    ///         policy.
    /// @param _id Identifier of the item.
    function recordVerdict(bytes32 _id) external {
        if (msg.sender != policy) revert ComplianceModule_NotPolicy();

        uint64 at = uint64(block.timestamp);
        items[_id].clearedAt = at;
        emit Cleared(_id, at);
    }

    /// @notice Revokes the clear verdict of an item. Only callable by the policy.
    /// @param _id Identifier of the item.
    function revokeVerdict(bytes32 _id) external {
        if (msg.sender != policy) revert ComplianceModule_NotPolicy();

        items[_id].clearedAt = 0;
        emit ClearanceRevoked(_id);
    }

    /// @notice Completes a held deposit once it is cleared. Anyone can call it, and the terms come
    ///         from the item itself.
    /// @param _item The held deposit.
    function completeDeposit(Item calldata _item) external {
        bytes32 id = _consume(_item);
        emit Completed(id);

        address approved = _releaseTokens(_item);
        portal.completeDepositTransaction{ value: _item.ethAmount }(_item);
        if (approved != address(0)) _approveBridge(approved, 0);
    }

    /// @notice Completes a held withdrawal once it is cleared. Anyone can call it, and the terms
    ///         come from the item itself.
    /// @param _item The held withdrawal.
    function completeWithdrawal(Item calldata _item) external {
        bytes32 id = _consume(_item);
        emit Completed(id);

        address approved = _releaseTokens(_item);
        portal.completeWithdrawalTransaction{ value: _item.ethAmount }(_item);
        if (approved != address(0)) _approveBridge(approved, 0);
    }

    /// @notice Resolves the parties the policy screens: the item's sender and target, or the ones
    ///         inside it when it is a messenger envelope, down to the user for a standard bridge
    ///         transfer. Anything that does not decode keeps the outer parties. An aliased sender
    ///         is passed unaliased, so the policy's lists hold L1 addresses.
    /// @param _item The item.
    /// @return parties_ The initiator and the recipient.
    function effectiveParties(Item memory _item) public view returns (address[] memory parties_) {
        address from = _item.aliased ? AddressAliasHelper.undoL1ToL2Alias(_item.from) : _item.from;
        address to = _item.to;

        if (_isFromMessenger(_item)) {
            (bool ok, address sender, address target, bytes memory message) =
                BridgeHookItem.decodeRelayMessage(_item.data);
            if (ok) {
                from = sender;
                to = target;

                if (_isBetweenBridges(_item.direction, sender, target)) {
                    (bool found, address bridgeFrom, address bridgeTo) = BridgeHookItem.decodeFinalizeParties(message);
                    if (found) {
                        from = bridgeFrom;
                        to = bridgeTo;
                    }
                }
            }
        }

        parties_ = new address[](2);
        parties_[0] = from;
        parties_[1] = to;
    }

    /// @notice Records a hold. Checks that the item's ETH came with the call, and that the module's
    ///         balance covers the tokens it now holds.
    /// @param _item The held item.
    function _hold(Item calldata _item) internal {
        if (msg.value != _item.ethAmount) revert ComplianceModule_ValueMismatch();

        // The bridge sent the tokens just before this call.
        if (_item.asset == Asset.ERC20) {
            (address localToken, address remoteToken, uint256 amount) = _tokenTransfer(_item);
            if (_isEscrowed(localToken)) {
                heldTokens[localToken][remoteToken] += amount;
                uint256 total = heldTokenTotal[localToken] += amount;
                if (IERC20(localToken).balanceOf(address(this)) < total) revert ComplianceModule_Undelivered();
            }
        }

        bytes32 id = BridgeHookItem.hash(_item);
        items[id].heldAt = uint64(block.timestamp);
        emit Held(id, _item);
    }

    /// @notice Deletes the record of a held, cleared item once the policy allows it to move.
    /// @param _item The held item.
    /// @return id_ Identifier of the item.
    function _consume(Item calldata _item) internal returns (bytes32 id_) {
        id_ = BridgeHookItem.hash(_item);

        Record memory record = items[id_];
        if (record.heldAt == 0) revert ComplianceModule_NotHeld();
        if (record.clearedAt == 0) revert ComplianceModule_NotCleared();

        delete items[id_];

        if (!IPolicy(policy).screenRelease(_item, effectiveParties(_item), record.clearedAt, 0)) {
            revert ComplianceModule_Declined();
        }
    }

    /// @notice Drops a held token item from the token totals and approves the bridge to pull its
    ///         tokens back.
    /// @param _item The held item.
    /// @return approved_ The token approved, or zero for ETH and tokens native to L2.
    function _releaseTokens(Item calldata _item) internal returns (address approved_) {
        if (_item.asset != Asset.ERC20) return address(0);

        (address localToken, address remoteToken, uint256 amount) = _tokenTransfer(_item);
        if (!_isEscrowed(localToken)) return address(0);

        heldTokens[localToken][remoteToken] -= amount;
        heldTokenTotal[localToken] -= amount;
        _approveBridge(localToken, amount);
        approved_ = localToken;
    }

    /// @notice Reads the tokens and the amount of a token item from its data.
    /// @param _item A token item.
    /// @return localToken_  L1 token.
    /// @return remoteToken_ L2 token.
    /// @return amount_      Amount transferred.
    function _tokenTransfer(Item calldata _item)
        internal
        pure
        returns (address localToken_, address remoteToken_, uint256 amount_)
    {
        bool ok;
        (ok, localToken_, remoteToken_, amount_) = BridgeHookItem.decodeTokenTransfer(_item);

        // The Portal only marks an item as a token transfer after decoding the same message.
        if (!ok) revert ComplianceModule_NotTokenTransfer();
    }

    /// @notice Whether the L1StandardBridge escrows a token, by the same check it makes. A token
    ///         native to L2 is burned and minted instead, so its hold moves nothing.
    /// @param _token The L1 token.
    /// @return True if the bridge escrows the token.
    function _isEscrowed(address _token) internal view returns (bool) {
        return !ERC165Checker.supportsInterface(_token, type(ILegacyMintableERC20).interfaceId)
            && !ERC165Checker.supportsInterface(_token, type(IOptimismMintableERC20).interfaceId);
    }

    /// @notice Sets the bridge's allowance for a token. The bridge only pulls escrowed tokens, so
    ///         the allowance is reset after each completion.
    /// @param _token  Token to approve.
    /// @param _amount Amount to approve.
    function _approveBridge(address _token, uint256 _amount) internal {
        IERC20(_token).safeApprove(bridge, 0);
        if (_amount > 0) IERC20(_token).safeApprove(bridge, _amount);
    }

    /// @notice Sets the policy.
    /// @param _policy Address of the policy.
    function _setPolicy(address _policy) internal {
        if (_policy == address(0)) revert ComplianceModule_ZeroAddress();
        policy = _policy;
        emit PolicySet(_policy);
    }

    /// @notice Reverts if the caller is not the OptimismPortal, or if this module is not its bridge
    ///         hook. A former hook is no longer an unsafe target, so a withdrawal could call it.
    function _assertPortal() internal view {
        if (msg.sender != address(portal) || address(portal.bridgeHook()) != address(this)) {
            revert ComplianceModule_NotPortal();
        }
    }

    /// @notice Checks if an item is an envelope from one messenger to the other.
    /// @param _item The item.
    /// @return True if the item is a messenger envelope.
    function _isFromMessenger(Item memory _item) internal view returns (bool) {
        if (_item.direction == Direction.Deposit) {
            return _item.aliased && _item.to == Predeploys.L2_CROSS_DOMAIN_MESSENGER
                && _item.from == AddressAliasHelper.applyL1ToL2Alias(l1CrossDomainMessenger);
        }
        return _item.to == l1CrossDomainMessenger && _item.from == Predeploys.L2_CROSS_DOMAIN_MESSENGER;
    }

    /// @notice Checks if an envelope's inner sender and target are the two standard bridges.
    /// @param _direction Direction of the item.
    /// @param _sender    Inner sender.
    /// @param _target    Inner target.
    /// @return True if the envelope is a message between the standard bridges.
    function _isBetweenBridges(Direction _direction, address _sender, address _target) internal view returns (bool) {
        if (_direction == Direction.Deposit) {
            return _sender == bridge && _target == Predeploys.L2_STANDARD_BRIDGE;
        }
        return _sender == Predeploys.L2_STANDARD_BRIDGE && _target == bridge;
    }
}
