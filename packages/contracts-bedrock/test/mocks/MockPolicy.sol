// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Libraries
import { Item } from "src/libraries/BridgeHookItem.sol";

// Interfaces
import { IPolicy } from "interfaces/L1/IPolicy.sol";

/// @title MockPolicy
/// @notice A policy standing in for whatever a chain actually deploys behind the module. It is
///         deliberately trivial: the point of the design is that the module does not know what
///         shape a policy has, so a test policy only has to be a policy.
/// @dev Defaults to the asynchronous shape, which is what a sanctions policy is: hold everything
///      at submission and let verdicts arrive later. Set `passDeposits` to get the synchronous
///      shape, where nothing is ever held.
contract MockPolicy is IPolicy {
    /// @notice The module this policy writes verdicts to.
    IComplianceModuleVerdicts public module;

    /// @notice Whether `screen` passes items at submission.
    bool public passDeposits;

    /// @notice Whether `screenRelease` lets a cleared item move.
    bool public passReleases = true;

    /// @notice Whether `screen` reverts, which is how a policy rejects an item outright.
    bool public rejectDeposits;

    /// @notice Whether `screenRelease` reverts. A policy has no business rejecting a withdrawal,
    ///         but nothing stops it trying, which is exactly what the module has to absorb.
    bool public rejectReleases;

    /// @notice Addresses that are denied. A deny beats a prior clearance, because the module
    ///         consults the policy again at the moment value moves.
    mapping(address => bool) public denied;

    /// @notice Thrown when an item is rejected at submission.
    error MockPolicy_Rejected();

    /// @notice Sets the module this policy writes verdicts to.
    function setModule(IComplianceModuleVerdicts _module) external {
        module = _module;
    }

    /// @notice Sets whether items pass at submission.
    function setPassDeposits(bool _pass) external {
        passDeposits = _pass;
    }

    /// @notice Sets whether cleared items are allowed to move.
    function setPassReleases(bool _pass) external {
        passReleases = _pass;
    }

    /// @notice Sets whether items are rejected outright at submission.
    function setRejectDeposits(bool _reject) external {
        rejectDeposits = _reject;
    }

    /// @notice Sets whether the policy reverts when asked to let value move.
    function setRejectReleases(bool _reject) external {
        rejectReleases = _reject;
    }

    /// @notice Adds or removes a deny entry.
    function setDenied(address _party, bool _denied) external {
        denied[_party] = _denied;
    }

    /// @notice Stands in for the screening service and the compliance officer alike. Both cause
    ///         the same state transition; only the authority and the attribution differ, and both
    ///         are questions this contract answers rather than the module.
    function clear(bytes32 _id) external {
        module.recordVerdict(_id);
    }

    /// @notice Takes a clearance back.
    function revoke(bytes32 _id) external {
        module.revokeVerdict(_id);
    }

    /// @notice How many times `screen` has been called, so a test can assert that one economic
    ///         event produces exactly one verdict.
    uint256 public screenCalls;

    /// @notice The parties the last `screen` call was given.
    address[] public lastParties;

    /// @inheritdoc IPolicy
    function screen(Item calldata, address[] calldata _parties) external returns (bool pass_) {
        screenCalls++;
        lastParties = _parties;

        if (rejectDeposits) revert MockPolicy_Rejected();
        if (_anyDenied(_parties)) return false;
        pass_ = passDeposits;
    }

    /// @inheritdoc IPolicy
    function screenRelease(
        Item calldata,
        address[] calldata _parties,
        uint64 _clearedAt
    )
        external
        view
        returns (bool pass_)
    {
        if (rejectReleases) revert MockPolicy_Rejected();

        // No verdict means no release. At a withdrawal call site this is what routes an item that
        // was never screened into holding.
        if (_clearedAt == 0) return false;

        // An on-chain deny beats anything the screening service wrote.
        if (_anyDenied(_parties)) return false;

        pass_ = passReleases;
    }

    /// @notice Whether any effective party is denied.
    function _anyDenied(address[] calldata _parties) internal view returns (bool) {
        for (uint256 i; i < _parties.length; i++) {
            if (denied[_parties[i]]) return true;
        }
        return false;
    }
}

/// @notice The slice of the module a policy needs. Verdicts are the policy's to cause; the
///         module's whole authorisation surface for them is `msg.sender == policy`.
interface IComplianceModuleVerdicts {
    function recordVerdict(bytes32 _id) external;
    function revokeVerdict(bytes32 _id) external;
}
