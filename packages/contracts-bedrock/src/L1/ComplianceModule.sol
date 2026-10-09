// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ProxyAdminOwnedBase } from "src/universal/ProxyAdminOwnedBase.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { AddressAliasHelper } from "src/vendor/AddressAliasHelper.sol";
import { Asset, BridgeHookItem, Direction, Item } from "src/libraries/BridgeHookItem.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IBridgeHook } from "interfaces/universal/IBridgeHook.sol";
import { IPolicy } from "interfaces/L1/IPolicy.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IL1StandardBridge } from "interfaces/L1/IL1StandardBridge.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IStandardBridge } from "interfaces/universal/IStandardBridge.sol";

/// @custom:proxied true
/// @title ComplianceModule
/// @notice Implements the bridge hook. Owns the verdict registry, all custody, completion and
///         release, and the protocol decoding needed to name the real parties. It is the only
///         contract here that holds value.
/// @dev The module knows exactly one compliance address, the policy. The module owns identity,
///      custody, accounting and protocol decoding; the policy owns rules, lists, sources, roles
///      and timing. Nothing crosses that line: the module has no screening-service role, no
///      officer role, no list writer and no guardian, because an automated clearance and an
///      officer's clearance are the same event to it, a clear verdict for one item.
///
///      Whoever can upgrade this contract can change how frozen value is treated, so that key is
///      the custodian in every sense that matters and must sit on a proxy admin separate from the
///      chain's. The policy pointer is gated at exactly that authority, because a permissive
///      policy is indistinguishable in effect from an upgrade that stops screening.
contract ComplianceModule is Initializable, ProxyAdminOwnedBase, IBridgeHook, ISemver {
    using SafeERC20 for IERC20;

    /// @notice The state the module keeps per item. Item fields are never stored: they are
    ///         emitted in full in `Held` and re-supplied when value moves, the same pattern the
    ///         protocol uses for proving withdrawals. That keeps unbounded calldata out of
    ///         storage and is what makes backlog recovery work.
    /// @custom:field heldAt    Non-zero means the item exists and is held.
    /// @custom:field clearedAt Non-zero means a clear verdict is recorded, and when.
    struct Record {
        uint64 heldAt;
        uint64 clearedAt;
    }

    /// @notice Address of the OptimismPortal. Holds the ETH call sites.
    /// @dev Immutable rather than storage. All three are read on every screen, so as storage they
    ///      cost three cold SLOADs on the hottest path in the system, and on withdrawals that is
    ///      headroom taken from the withdrawal's own gas limit. A module serves one chain and one
    ///      customer, so fixing them at implementation-deploy time costs no reusability. They live
    ///      in the implementation's code rather than the proxy's storage, so an upgrade carries
    ///      them forward only if the new implementation is deployed with the same values.
    IOptimismPortal2 public immutable portal;

    /// @notice Address of the L1StandardBridge. Holds the ERC-20 call sites.
    IL1StandardBridge public immutable bridge;

    /// @notice Address of the L1CrossDomainMessenger, recognised when decoding an envelope.
    ICrossDomainMessenger public immutable l1CrossDomainMessenger;

    /// @notice The only compliance address the module knows.
    address public policy;

    /// @notice Emergency disable. While set, screening approves everything and nothing new is
    ///         held, so the chain behaves as stock for anything entering or leaving from here on.
    /// @dev It does not reach backwards. An item already held still needs a clear verdict and the
    ///      policy's approval to move, which is what stops a disable from being a release valve
    ///      for value that was already flagged. No timestamp comparison is needed to express that:
    ///      once this is set nothing new can be held, so every held item necessarily predates it.
    bool public disabled;

    /// @notice The verdict registry, one place for both directions. This holds verdicts; the
    ///         protocol's own mappings hold terms commitments. Two different facts about the same
    ///         item.
    mapping(bytes32 => Record) public items;

    /// @notice Set while this contract is between the two frames of one token deposit: the bridge
    ///         call where it approved the item, and the Portal call asking about the messenger
    ///         envelope the bridge sends immediately afterwards. Recording the decision is
    ///         cheaper and safer than rediscovering it by decoding that envelope's calldata.
    /// @dev It never has to survive a transaction. Every path that sets it continues, in the same
    ///      call chain, into the Portal frame that clears it, and a revert rolls it back. It is
    ///      only ever set once the Portal is known to be pointed at this contract, so it cannot be
    ///      left standing by a chain that screens at the bridge and not at the Portal.
    ///
    ///      It is not an authorisation on its own. The checks in `_isBridgeOriginatedMessage` that
    ///      rest on fields a caller cannot choose are kept, so a token that re-enters during the
    ///      transfer and deposits directly cannot consume it.
    bool internal _bridgeApprovedDeposit;

    /// @notice Emitted when an item is taken into custody. Carries the full preimage, which is
    ///         what makes the backlog reconstructible from L1 alone with no privileged access.
    /// @dev The calldata is emitted in full rather than hashed, deliberately. It is the same
    ///      choice `TransactionDeposited` makes when it packs the whole deposit into `opaqueData`
    ///      so the rollup node can derive from logs: an automated offchain consumer should not
    ///      have to fetch transaction bodies to rebuild state. The screening service is that kind
    ///      of consumer, and holding it to a weaker standard than the derivation pipeline would be
    ///      a bad trade for the few thousand gas a realistic item's calldata costs to log.
    /// @param id   Identifier of the item.
    /// @param item The item.
    event Held(bytes32 indexed id, Item item);

    /// @notice Emitted when a clear verdict is recorded.
    /// @param id Identifier of the item.
    /// @param at Time the verdict was written.
    event Cleared(bytes32 indexed id, uint64 at);

    /// @notice Emitted when a clear verdict is taken back.
    /// @param id Identifier of the item.
    event ClearanceRevoked(bytes32 indexed id);

    /// @notice Emitted when a held deposit completes.
    /// @param id Identifier of the item.
    event Completed(bytes32 indexed id);

    /// @notice Emitted when a held withdrawal is released to its original recipient.
    /// @param id Identifier of the item.
    event Released(bytes32 indexed id);

    /// @notice Emitted when the policy pointer is set.
    /// @param policy Address of the policy.
    event PolicySet(address indexed policy);

    /// @notice Emitted when screening is disabled or re-enabled.
    /// @param disabled Whether screening is disabled.
    event DisabledSet(bool disabled);

    /// @notice Thrown when a hook function is called by anything other than its call site.
    error ComplianceModule_NotCallSite();

    /// @notice Thrown when a verdict function is called by anything other than the policy.
    error ComplianceModule_NotPolicy();

    /// @notice Thrown when the item supplied has no held record.
    error ComplianceModule_NotHeld();

    /// @notice Thrown when the item supplied carries no clear verdict.
    error ComplianceModule_NotCleared();

    /// @notice Thrown when the policy declines to let the value move.
    error ComplianceModule_ReleaseDeclined();

    /// @notice Thrown when value would move while the system is paused.
    error ComplianceModule_Paused();

    /// @notice Thrown when the value arriving does not match the item's terms.
    error ComplianceModule_ValueMismatch();

    /// @notice Thrown when the policy pointer is set to the zero address.
    error ComplianceModule_ZeroAddress();

    /// @notice Semantic version.
    /// @custom:semver 0.1.0
    function version() public pure virtual returns (string memory) {
        return "0.1.0";
    }

    /// @notice Constructs the ComplianceModule contract.
    /// @param _portal                 Address of the OptimismPortal.
    /// @param _bridge                 Address of the L1StandardBridge.
    /// @param _l1CrossDomainMessenger Address of the L1CrossDomainMessenger.
    constructor(
        IOptimismPortal2 _portal,
        IL1StandardBridge _bridge,
        ICrossDomainMessenger _l1CrossDomainMessenger
    ) {
        portal = _portal;
        bridge = _bridge;
        l1CrossDomainMessenger = _l1CrossDomainMessenger;

        _disableInitializers();
    }

    /// @notice Initializer. Only the policy is set here; the call sites are immutable and come
    ///         from the constructor.
    /// @param _policy Address of the policy.
    function initialize(address _policy) external initializer {
        _assertOnlyProxyAdminOrProxyAdminOwner();

        if (_policy == address(0)) revert ComplianceModule_ZeroAddress();
        policy = _policy;
        emit PolicySet(_policy);
    }

    /// @notice Points the module at a different policy. Gated at the upgrade authority and
    ///         nothing weaker: a permissive policy is indistinguishable in effect from upgrading
    ///         the module to stop screening, so gating it lower would hand a lesser role the whole
    ///         system.
    /// @param _policy Address of the new policy.
    function setPolicy(address _policy) external {
        _assertOnlyProxyAdminOwner();

        if (_policy == address(0)) revert ComplianceModule_ZeroAddress();
        policy = _policy;
        emit PolicySet(_policy);
    }

    /// @notice Disables or re-enables screening. This is the emergency stop, and it lives here
    ///         rather than in the protocol for two reasons: unsetting the hook address on the call
    ///         sites would gate every release path on an address that no longer exists and strand
    ///         everything already held, and the protocol should not have to know that compliance
    ///         is the thing being switched off.
    /// @dev Gated at the same authority as the policy pointer, because a disable and a permissive
    ///      policy are the same act by a different route. Re-enabling restores screening with no
    ///      loss of state: held items were never touched.
    /// @param _disabled Whether to disable screening.
    function setDisabled(bool _disabled) external {
        _assertOnlyProxyAdminOwner();

        disabled = _disabled;
        emit DisabledSet(_disabled);
    }

    /// @inheritdoc IBridgeHook
    function screenDeposit(Item calldata _item) external returns (bool pass_) {
        _assertCallSite(_item);

        // Disabled means stock behaviour from here on: everything entering passes, nothing new is
        // held, and the policy is not consulted at all. Checked before anything else so a broken
        // policy cannot keep deposits from flowing, which is the whole point of having a stop.
        if (disabled) return true;

        // A token deposit reaches the Portal a second time, as the messenger envelope carrying the
        // L2 message the bridge sends once the item is clear. That envelope was already screened
        // at the bridge, where the parties arrive as typed arguments, so screening it again would
        // be a second verdict and a second identifier for one economic event, and a decline would
        // strand the escrow with no L2 credit.
        if (_isBridgeOriginatedMessage(_item)) return true;

        pass_ = IPolicy(policy).screen(_item, effectiveParties(_item));

        // A token deposit that passes here is about to send its L2 message through the messenger,
        // which reaches the Portal, which asks again about the same economic event. Remember the
        // decision so that second question is answered from it. Only the bridge can present a
        // token item, so this is reachable from nowhere else, and the flag is not set at all
        // unless the Portal is pointed here and will therefore consume it.
        if (pass_ && _item.asset == Asset.ERC20 && address(portal.bridgeHook()) == address(this)) {
            _bridgeApprovedDeposit = true;
        }
    }

    /// @inheritdoc IBridgeHook
    function holdDeposit(Item calldata _item) external payable {
        _assertCallSite(_item);
        _assertValueMatchesItem(_item);
        _hold(_item);
    }

    /// @inheritdoc IBridgeHook
    function screenWithdrawal(Item calldata _item) external returns (bool pass_) {
        _assertCallSite(_item);

        // Same stop as on the deposit side. A withdrawal that reaches finalization while disabled
        // pays out exactly as it would on a stock chain, and no new withdrawal is routed into
        // holding. Items already held keep needing a verdict.
        if (disabled) return true;

        // A token withdrawal reaches L1 as a value-less envelope addressed to the bridge, and the
        // bridge is where it has to be judged: that is where its value actually moves and where
        // the parties arrive as typed arguments instead of buried in calldata. Deferring is not
        // waiving the screen, it is choosing which of the two call sites performs it. The mirror
        // of the deposit side, where the message the bridge sends is skipped because the bridge
        // already screened it.
        if (_isBridgeBoundERC20Withdrawal(_item)) return true;

        bytes32 id = BridgeHookItem.hash(_item);

        address[] memory parties = effectiveParties(_item);
        uint64 clearedAt = items[id].clearedAt;

        // A verdict may already exist from the challenge window, in which case the policy is
        // being asked whether a clearance of that age still stands. Zero means no verdict, and a
        // policy seeing zero declines, which routes the withdrawal into holding.
        //
        // On the bridge leg the policy is not permitted to reject, and this is where that rule is
        // enforced rather than left to the policy's discipline. A withdrawal has no sender to
        // return value to, so a rejection has nothing it could mean. What it would actually do is
        // revert inside `finalizeBridgeERC20`, which the messenger swallows into a failed message
        // rather than bubbling: the Portal has already marked the withdrawal finalized by then, so
        // the value would sit in the bridge with no held record against it. Catching turns that
        // into the hold it should have been.
        //
        // The Portal leg is deliberately left to revert. There the failure unwinds the whole
        // finalization, nothing is consumed, and the withdrawal stays finalizable later.
        if (_item.asset == Asset.ERC20) {
            try IPolicy(policy).screenRelease(_item, parties, clearedAt) returns (bool allowed_) {
                pass_ = allowed_;
            } catch {
                pass_ = false;
            }
        } else {
            pass_ = IPolicy(policy).screenRelease(_item, parties, clearedAt);
        }

        // A verdict written ahead of a withdrawal that then passes has served its purpose, so it
        // is not left behind in the registry.
        if (pass_ && items[id].heldAt == 0) delete items[id];
    }

    /// @inheritdoc IBridgeHook
    function holdWithdrawal(Item calldata _item) external payable {
        _assertCallSite(_item);
        _assertValueMatchesItem(_item);
        _hold(_item);
    }

    /// @notice Records a clear verdict for one item. Policy-only: the policy decides who may cause
    ///         a verdict and emits the attribution. An officer's clearance and an automated
    ///         clearance are the same state transition here, and only the authority and the
    ///         attribution differ.
    /// @dev A verdict may be recorded before its item exists, which is how a withdrawal is cleared
    ///      during the challenge window so that finalization pays out normally.
    /// @param _id Identifier of the item.
    function recordVerdict(bytes32 _id) external {
        if (msg.sender != policy) revert ComplianceModule_NotPolicy();

        uint64 at = uint64(block.timestamp);
        items[_id].clearedAt = at;
        emit Cleared(_id, at);
    }

    /// @notice Takes back a clear verdict.
    /// @dev Best-effort. Revocation and completion can land in the same block and completion is
    ///      permissionless, so the race-free way to stop an already-cleared item is a deny entry
    ///      inside the policy, which is read again at the moment value moves.
    /// @param _id Identifier of the item.
    function revokeVerdict(bytes32 _id) external {
        if (msg.sender != policy) revert ComplianceModule_NotPolicy();

        items[_id].clearedAt = 0;
        emit ClearanceRevoked(_id);
    }

    /// @notice Completes a held deposit, permissionlessly. The caller chooses only which item
    ///         moves, never its terms, and no fee can be taken from held value.
    /// @param _item The held deposit.
    function completeDeposit(Item calldata _item) external {
        bytes32 id = _consumeMovable(_item);

        emit Completed(id);

        if (_item.asset == Asset.ETH) {
            portal.completeDepositTransaction{ value: _item.amount }(_item);
        } else {
            // The bridge pulls on the escrow branch and burns straight out of this contract on
            // the mintable one, so the allowance is not always consumed. It is cleared afterwards
            // either way rather than left standing.
            _setBridgeAllowance(_item.localToken, _item.amount);

            // Completion sends the same L2 message a passing deposit would have, so the Portal
            // asks the same second question and is answered the same way. Cleared afterwards
            // rather than relied on being consumed, because this path is entered from outside.
            _bridgeApprovedDeposit = true;
            bridge.completeERC20Deposit(_item);
            delete _bridgeApprovedDeposit;

            _setBridgeAllowance(_item.localToken, 0);
        }
    }

    /// @notice Releases a held withdrawal to its original recipient, permissionlessly.
    /// @dev Both releases re-enter the contract that would have paid on a stock chain, because
    ///      the recipient-facing action has to come from the contract the recipient expects.
    /// @param _item The held withdrawal.
    function releaseWithdrawal(Item calldata _item) external {
        // The module is never a route for value the guardian has frozen. Held value sits outside
        // the protocol's own perimeter, so the module has to opt back into it here. Deposit
        // completion is deliberately not gated, since `depositTransaction` has no pause check
        // either.
        //
        // The question is asked of the call site that owns the asset rather than resolved here,
        // because the two do not answer it the same way: the Portal reads the pause from the
        // ETHLockbox and the bridge reads it from the SystemConfig. Deriving it independently
        // would mean the module could release into a contract that considers itself paused.
        // Asking the contract the value is about to re-enter cannot drift from it.
        if (_item.asset == Asset.ETH ? portal.paused() : bridge.paused()) {
            revert ComplianceModule_Paused();
        }

        bytes32 id = _consumeMovable(_item);

        emit Released(id);

        if (_item.asset == Asset.ETH) {
            portal.completeWithdrawalTransaction{ value: _item.amount }(
                BridgeHookItem.toWithdrawalTransaction(_item)
            );
        } else {
            _setBridgeAllowance(_item.localToken, _item.amount);
            bridge.completeERC20Withdrawal(_item);
            _setBridgeAllowance(_item.localToken, 0);
        }
    }

    /// @notice Resolves the parties a policy should screen.
    /// @dev Any policy needs to know who the real parties are and the outer fields do not always
    ///      say: an item routed through the messenger arrives with system contracts as sender and
    ///      recipient, and the user one layer down in the calldata. Deriving them depends on the
    ///      shape of a relayMessage envelope and the selectors of the canonical bridge, which is
    ///      protocol knowledge rather than policy knowledge, so it is resolved once here and every
    ///      policy sees the same set.
    ///
    ///      An unwrap replaces the pair rather than adding to it, and that loses nothing: an
    ///      unwrap only ever happens when the outer pair is the two messengers, and the second
    ///      one only when the inner pair is the two canonical bridges. Every address discarded is
    ///      a system contract, which must never be screened as a party in the first place.
    ///      Accumulating instead would put the messenger and the bridge in front of the policy on
    ///      every routed item, which is no signal and obliges the policy to allowlist the
    ///      protocol's own plumbing before anything can pass.
    ///
    ///      The decode is deliberately narrow: fixed contracts, fixed selectors, no recursion, no
    ///      simulation. Anything it cannot decode falls back to the outer parties and proceeds,
    ///      which is the stated best-effort posture. Token addresses are not parties unless they
    ///      are themselves target or recipient.
    /// @param _item The item.
    /// @return parties_ The effective sender and recipient.
    function effectiveParties(Item memory _item) public view returns (address[] memory parties_) {
        address from = _item.from;
        address to = _item.to;

        // Only an ETH item can be carrying an envelope. A token item names its parties outright,
        // because the bridge screens it after the relay has already been unwrapped.
        //
        // The envelope has to be authenticated before anything inside it is believed. `from` is
        // derived by the call site from its own `msg.sender`, so it is the one field a submitter
        // cannot choose: only the messenger produces an item whose `from` is the messenger.
        // Without that check anyone could hand this contract a relayMessage-shaped blob naming
        // whatever parties they liked and have the policy screen those instead of themselves.
        if (_item.asset == Asset.ETH && _isFromMessenger(_item)) {
            // A deposit's envelope targets the L2 messenger predeploy and its inner call the L2
            // bridge; a withdrawal's target the L1 pair. Same shape, different addresses.
            address canonicalBridge = _item.direction == Direction.Deposit
                ? Predeploys.L2_STANDARD_BRIDGE
                : address(bridge);

            // The counterpart that legitimately produces a finalizer message for that bridge. An
            // L1 to L2 envelope can only have been written by the L1 bridge, an L2 to L1 one by
            // the L2 bridge, because the messenger stamps the inner sender as its own caller.
            address canonicalSender = _item.direction == Direction.Deposit
                ? address(bridge)
                : Predeploys.L2_STANDARD_BRIDGE;

            if (_selector(_item.data) == ICrossDomainMessenger.relayMessage.selector) {
                try this.decodeRelayMessage(_item.data) returns (
                    address sender_, address target_, bytes memory message_
                ) {
                    from = sender_;
                    to = target_;

                    // One more unwrap, and only for the canonical bridge's own finalizers. Without
                    // it the parties would be the two bridges rather than the user, and system
                    // contracts must never be treated as parties.
                    //
                    // The inner sender is checked as well, and it is what makes the unwrap safe
                    // rather than merely convenient. The target and the payload are both chosen by
                    // whoever called `sendMessage`, so on their own they prove nothing: anyone
                    // could address the canonical bridge and hand over a finalizer payload naming
                    // two clean addresses, and the policy would screen those instead of them. The
                    // inner sender is the one field the messenger writes itself, so requiring it
                    // to be the counterpart bridge is what ties the payload to the only contract
                    // that could have produced it honestly.
                    if (sender_ == canonicalSender && target_ == canonicalBridge) {
                        (bool found_, address f_, address t_) = _finalizerParties(message_);
                        if (found_) {
                            from = f_;
                            to = t_;
                        }
                    }
                } catch { }
            }
        }

        parties_ = new address[](2);
        parties_[0] = from;
        parties_[1] = to;
    }

    /// @notice Whether an item is the messenger envelope the L1StandardBridge sends after a token
    ///         deposit has already been screened here, in which case it needs no second verdict.
    /// @dev The exemption rests on this contract's own memory of the decision it made one frame
    ///      earlier, rather than on rediscovering that decision by decoding the envelope. Both are
    ///      answering "did I approve the deposit this message carries", and remembering is the
    ///      cheaper and stricter way to answer it: a payload can be shaped to look like anything,
    ///      a recorded decision cannot. It also removes the need to check that the bridge is still
    ///      pointed here, since a bridge that is not screening never sets the flag in the first
    ///      place.
    ///
    ///      The flag alone is not the exemption. The two fields a submitter cannot choose are
    ///      still required, and they are what confine it to the one message it is meant for. The
    ///      Portal derives `from` from its own caller, so `from` is the aliased messenger only if
    ///      the messenger called `depositTransaction`; and a token message never carries value.
    ///      Together they mean a token that re-enters during the bridge's transfer and deposits
    ///      directly cannot consume the flag, and the bridge's own ETH entry points, which carry
    ///      value, fail it too.
    ///
    ///      Fail-closed in every direction. This grants the module no capability it lacks, since
    ///      as the hook it can already return true for anything.
    /// @param _item The item.
    /// @return bool True if the item may skip screening.
    function _isBridgeOriginatedMessage(Item calldata _item) internal returns (bool) {
        if (!_bridgeApprovedDeposit) return false;
        if (_item.direction != Direction.Deposit || _item.asset != Asset.ETH) return false;
        if (_item.amount != 0) return false;
        if (!_isFromMessenger(_item)) return false;

        // Consumed, so one approval exempts exactly one envelope.
        delete _bridgeApprovedDeposit;
        return true;
    }

    /// @notice Whether an item is the value-less envelope of a canonical token withdrawal, which
    ///         the bridge will screen when it unwraps it.
    /// @dev The exemption rests on two fields nobody can choose and one the bridge controls. The
    ///      withdrawal's `sender` is whatever called `initiateWithdrawal` on L2, committed in the
    ///      hash and proven, so it is the L2 messenger only if the messenger sent this. The
    ///      envelope's inner sender is written by that messenger as its own caller, so it is the
    ///      L2 bridge only if the bridge sent this. Together they mean the L2 standard bridge
    ///      produced the message, and the only thing it sends to the L1 bridge with no value is a
    ///      token withdrawal.
    ///
    ///      The inner target and selector are checked as well, so an ETH bridge message of zero
    ///      amount does not slip through the same door, and the bridge is checked to still be
    ///      pointed at this contract, so a half-configured chain cannot end up deferring to a call
    ///      site that is no longer screening. A forged payload fails on the first field and a
    ///      decode failure falls through to normal screening.
    /// @param _item The item.
    /// @return bool True if the bridge will screen this item instead.
    function _isBridgeBoundERC20Withdrawal(Item calldata _item) internal view returns (bool) {
        if (_item.direction != Direction.Withdrawal || _item.asset != Asset.ETH) return false;
        if (_item.amount != 0) return false;
        if (!_isFromMessenger(_item)) return false;
        if (_selector(_item.data) != ICrossDomainMessenger.relayMessage.selector) return false;
        if (address(bridge.bridgeHook()) != address(this)) return false;

        try this.decodeRelayMessage(_item.data) returns (address sender_, address target_, bytes memory message_) {
            return sender_ == Predeploys.L2_STANDARD_BRIDGE && target_ == address(bridge)
                && _selector(message_) == IStandardBridge.finalizeBridgeERC20.selector;
        } catch {
            return false;
        }
    }

    /// @notice Whether an item was genuinely produced by the canonical messenger relaying a
    ///         message, rather than by someone handing a call site a payload shaped like one.
    /// @dev The Portal derives a deposit's `from` from its own caller, aliasing it because the
    ///      messenger is a contract, and a withdrawal's `from` is the L2 sender the proof
    ///      committed to. Neither is choosable by a submitter, which is what makes this an
    ///      authentication rather than a heuristic.
    /// @param _item The item.
    /// @return bool True if the messenger produced this item.
    function _isFromMessenger(Item memory _item) internal view returns (bool) {
        if (_item.direction == Direction.Deposit) {
            return _item.to == Predeploys.L2_CROSS_DOMAIN_MESSENGER
                && _item.from == AddressAliasHelper.applyL1ToL2Alias(address(l1CrossDomainMessenger));
        }
        return _item.to == address(l1CrossDomainMessenger) && _item.from == Predeploys.L2_CROSS_DOMAIN_MESSENGER;
    }

    /// @notice Decodes a relayMessage envelope. External so that a malformed payload is a caught
    ///         revert rather than a failed item.
    /// @param _data The envelope calldata, selector included.
    /// @return sender_  The inner sender.
    /// @return target_  The inner target.
    /// @return message_ The inner message.
    function decodeRelayMessage(bytes calldata _data)
        external
        pure
        returns (address sender_, address target_, bytes memory message_)
    {
        (, sender_, target_,,, message_) =
            abi.decode(_data[4:], (uint256, address, address, uint256, uint256, bytes));
    }

    /// @notice Reads the sender and recipient out of a canonical bridge finalizer call.
    /// @dev The two addresses sit at fixed offsets in the head of the ABI encoding, so they are
    ///      read directly rather than through `abi.decode` behind an external call. That removes
    ///      one self-call from the hot path, which on a withdrawal is headroom the withdrawal's own
    ///      gas limit would otherwise lose.
    ///
    ///      Reading at fixed offsets is safe here for two reasons. The length is checked first, so
    ///      a short payload is rejected rather than read past. And this is only ever reached once
    ///      the inner sender has been shown to be the counterpart bridge, so the encoding is the
    ///      bridge's own and its address words are clean; a payload that is not the bridge's never
    ///      gets here. Anything unrecognised returns false and the caller keeps the outer parties.
    /// @param _message The inner message, selector included.
    /// @return found_ Whether a known finalizer was recognised and decoded.
    /// @return from_  The sender named in the call.
    /// @return to_    The recipient named in the call.
    function _finalizerParties(bytes memory _message)
        internal
        pure
        returns (bool found_, address from_, address to_)
    {
        bytes4 selector = _selector(_message);

        // Argument index of `from` in each finalizer. `to` always follows it.
        uint256 index;
        if (selector == IStandardBridge.finalizeBridgeETH.selector) {
            index = 0; // finalizeBridgeETH(from, to, amount, extraData)
        } else if (selector == IStandardBridge.finalizeBridgeERC20.selector) {
            index = 2; // finalizeBridgeERC20(localToken, remoteToken, from, to, amount, extraData)
        } else {
            return (false, address(0), address(0));
        }

        // Selector plus every head word up to and including `to`.
        if (_message.length < 4 + (index + 2) * 32) return (false, address(0), address(0));

        assembly ("memory-safe") {
            let head := add(add(_message, 0x20), 4)
            from_ := shr(96, shl(96, mload(add(head, mul(index, 0x20)))))
            to_ := shr(96, shl(96, mload(add(head, mul(add(index, 1), 0x20)))))
        }
        found_ = true;
    }

    /// @notice Records a hold and emits the preimage.
    /// @param _item The item taken into custody.
    function _hold(Item calldata _item) internal {
        bytes32 id = BridgeHookItem.hash(_item);
        items[id].heldAt = uint64(block.timestamp);
        emit Held(id, _item);
    }

    /// @notice Asserts that an item is held, cleared, and that the policy will let it move, and
    ///         consumes the record. The same three checks and the same consumption on both
    ///         value-moving paths.
    /// @dev The one compliance-shaped rule the module keeps of its own, and only because it owns
    ///      the registry: value never moves out of a hold without a recorded clearance. What a
    ///      clearance's age means and whether a party is denied are the policy's answers.
    ///
    ///      The record is deleted before the policy is asked, not after. The policy is an external
    ///      contract on the far side of the only trust boundary this contract has, and asking it
    ///      first would leave a live record in place across a call that can re-enter: a policy
    ///      that called back into a value-moving path would pass these checks a second time and
    ///      move the same item twice. The protocol's own commitment is deleted a frame later and
    ///      would make the outer call revert, so the double move does not survive today, but that
    ///      is the Portal's bookkeeping covering for this contract's. Consuming first makes the
    ///      re-entrant call fail here, on `heldAt == 0`, which is where it should fail.
    /// @param _item The item.
    /// @return id_ Identifier of the item.
    function _consumeMovable(Item calldata _item) internal returns (bytes32 id_) {
        id_ = BridgeHookItem.hash(_item);

        Record memory record = items[id_];
        if (record.heldAt == 0) revert ComplianceModule_NotHeld();
        if (record.clearedAt == 0) revert ComplianceModule_NotCleared();

        delete items[id_];

        if (!IPolicy(policy).screenRelease(_item, effectiveParties(_item), record.clearedAt)) {
            revert ComplianceModule_ReleaseDeclined();
        }
    }

    /// @notice Asserts that the caller is the call site that owns this item's asset class. ETH is
    ///         always held at the Portal, whichever route it took, and tokens are always held at
    ///         the bridge: the contract that has the value is the contract that hands it over.
    /// @param _item The item.
    function _assertCallSite(Item calldata _item) internal view {
        address expected = _item.asset == Asset.ETH ? address(portal) : address(bridge);
        if (msg.sender != expected) revert ComplianceModule_NotCallSite();
    }

    /// @notice Asserts that the ETH arriving with a custody handover is the amount the item names.
    /// @dev The module stores no amounts, so it cannot verify its own solvency after the fact. It
    ///      can at least refuse to record a hold for value it did not receive, which keeps its
    ///      accounting consistent with its balance without trusting the call site's word. Tokens
    ///      arrive by transfer rather than with the call, so only the ETH leg is checkable here.
    /// @param _item The item.
    function _assertValueMatchesItem(Item calldata _item) internal view {
        uint256 expected = _item.asset == Asset.ETH ? _item.amount : 0;
        if (msg.value != expected) revert ComplianceModule_ValueMismatch();
    }

    /// @notice Approves the bridge to pull an item's tokens back on a completion path.
    /// @param _token  Token to approve.
    /// @param _amount Amount to approve.
    function _setBridgeAllowance(address _token, uint256 _amount) internal {
        IERC20(_token).safeApprove(address(bridge), 0);
        if (_amount > 0) IERC20(_token).safeApprove(address(bridge), _amount);
    }

    /// @notice Reads the leading selector of a calldata blob, or zero if it is too short.
    /// @param _data The blob.
    /// @return selector_ The selector.
    function _selector(bytes memory _data) internal pure returns (bytes4 selector_) {
        if (_data.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector_ := mload(add(_data, 0x20))
        }
    }
}
