// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { IShareCalculator } from "interfaces/L2/IShareCalculator.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

// OpenZeppelin
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:proxied
/// @title SharesCalculator
/// @notice Calculator for Superchain revenue share. It pays a fixed 2.5% on gross revenue and 15%
///         on net revenue (gross minus L1 fees) to the configured share recipient. The second
///         configured recipient receives the full remainder via FeeSplitter's remainder send.
contract SharesCalculator is ISemver, Initializable {
    /// @notice Emitted when the share recipient is updated.
    /// @param shareRecipient The new share recipient address.
    event ShareRecipientUpdated(address indexed shareRecipient);

    /// @notice Emitted when the remainder recipient is updated.
    /// @param remainderRecipient The new remainder recipient address.
    event RemainderRecipientUpdated(address indexed remainderRecipient);

    /// @notice Thrown when the caller is not the ProxyAdmin owner.
    error SharesCalculator_OnlyProxyAdminOwner();

    /// @notice Thrown when a configured recipient is the zero address.
    error SharesCalculator_RecipientZeroAddress();

    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Basis points scale.
    uint32 public constant BASIS_POINT_SCALE = 10_000;

    /// @notice Gross revenue share in basis points (2.5%).
    uint32 public constant GROSS_SHARE_BPS = 250;

    /// @notice Net revenue share in basis points (15%).
    uint32 public constant NET_SHARE_BPS = 1_500;

    /// @notice Address of the FeeSplitter contract.
    address public constant FEE_SPLITTER = 0x4200000000000000000000000000000000000029;

    /// @notice Address that receives the Superchain revenue share.
    address payable public shareRecipient;

    /// @notice Address that receives the remainder of the revenue.
    address payable public remainderRecipient;

    /// @notice Modifier that restricts access to the ProxyAdmin owner.
    modifier onlyProxyAdminOwner() {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) {
            revert SharesCalculator_OnlyProxyAdminOwner();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with an initial configuration.
    /// @param _shareRecipient Recipient of the Superchain revenue share.
    /// @param _remainderRecipient Recipient of the remainder.
    function initialize(
        address payable _shareRecipient,
        address payable _remainderRecipient
    )
        external
        initializer
        onlyProxyAdminOwner
    {
        shareRecipient = _shareRecipient;
        remainderRecipient = _remainderRecipient;
    }

    /// @notice Returns the recipients and values for fee distribution.
    /// @param _sequencerFeeRevenue Revenue from sequencer fees.
    /// @param _baseFeeRevenue Revenue from base fees.
    /// @param _operatorFeeRevenue Revenue from operator fees.
    /// @param _l1FeeRevenue Revenue from L1 fees.
    /// @return recipients_ Array of recipient addresses.
    /// @return values_ Array of values corresponding to each recipient.
    function getRecipientsAndValues(
        uint256 _sequencerFeeRevenue,
        uint256 _baseFeeRevenue,
        uint256 _operatorFeeRevenue,
        uint256 _l1FeeRevenue
    )
        external
        view
        returns (address payable[] memory recipients_, uint256[] memory values_)
    {
        // Two recipients: share recipient first (explicit amount), remainder recipient second (0; FeeSplitter sends
        // remainder)
        recipients_ = new address payable[](2);
        recipients_[0] = shareRecipient;
        recipients_[1] = remainderRecipient;

        // Gross component: 2.5% of total revenue.
        uint256 grossRevenue = address(FEE_SPLITTER).balance;
        uint256 grossShare = (grossRevenue * uint256(GROSS_SHARE_BPS)) / BASIS_POINT_SCALE;

        // Net component: 15% of (total - L1 fees), floored at zero.
        uint256 netRevenue = grossRevenue - _l1FeeRevenue;
        uint256 netShare = (netRevenue * uint256(NET_SHARE_BPS)) / BASIS_POINT_SCALE;

        uint256 amountToShareRecipient = grossShare > netShare ? grossShare : netShare;

        // Set the share amount and the remainder to 0.
        values_ = new uint256[](2);
        values_[0] = amountToShareRecipient;
        values_[1] = grossRevenue - amountToShareRecipient;
    }

    function setShareRecipient(address payable _shareRecipient) external onlyProxyAdminOwner {
        shareRecipient = _shareRecipient;
        emit ShareRecipientUpdated(_shareRecipient);
    }

    function setRemainderRecipient(address payable _remainderRecipient) external onlyProxyAdminOwner {
        remainderRecipient = _remainderRecipient;
        emit RemainderRecipientUpdated(_remainderRecipient);
    }
}
