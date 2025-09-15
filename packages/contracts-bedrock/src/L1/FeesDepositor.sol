// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IOptimismPortal2 as IOptimismPortal } from "interfaces/L1/IOptimismPortal2.sol";
import { ProxyAdminOwnedBase } from "src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "src/universal/ReinitializableBase.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @custom:proxied true
/// @title FeesDepositor
/// @notice A contract that deposits fees to the L2 recipient when the deposit threshold is reached.
contract FeesDepositor is ProxyAdminOwnedBase, Initializable, ReinitializableBase, ISemver {
    /// @notice The threshold at which fees are deposited.
    uint256 public depositThreshold;

    /// @notice The L2 recipient of the fees.
    address public l2Recipient;

    /// @notice The gas limit for the deposit transaction.
    uint64 public gasLimit;

    /// @notice The portal contract.
    IOptimismPortal public portal;

    /// @notice The data for the deposit transaction.
    bytes public depositData;

    /// @notice Emitted when fees are received.
    /// @param portal The portal contract that is finalizing the withdrawal.
    /// @param l2sender The L2 sender of the fees.
    /// @param amount The amount of fees received.
    event FeesReceived(address indexed portal, address indexed l2sender, uint256 amount);

    /// @notice Emitted when fees are deposited.
    /// @param amount The amount of fees deposited.
    /// @param l2Recipient The L2 recipient of the fees.
    event FeesDeposited(address indexed l2Recipient, uint256 amount);

    /// @notice Emitted when the deposit threshold is updated.
    /// @param oldDepositThreshold The old deposit threshold.
    /// @param newDepositThreshold The new deposit threshold.
    event DepositThresholdUpdated(uint256 oldDepositThreshold, uint256 newDepositThreshold);

    /// @notice Emitted when the L2 recipient is updated.
    /// @param oldL2Recipient The old L2 recipient.
    /// @param newL2Recipient The new L2 recipient.
    event L2RecipientUpdated(address oldL2Recipient, address newL2Recipient);

    /// @notice Emitted when the gas limit is updated.
    /// @param oldGasLimit The old gas limit.
    /// @param newGasLimit The new gas limit.
    event GasLimitUpdated(uint64 oldGasLimit, uint64 newGasLimit);

    /// @notice Emitted when the deposit data is updated.
    /// @param oldDepositData The old deposit data.
    /// @param newDepositData The new deposit data.
    event DepositDataUpdated(bytes oldDepositData, bytes newDepositData);

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Constructs the FeesDepositor contract.
    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Initializes the FeesDepositor contract.
    /// @param _depositThreshold The threshold at which fees are deposited.
    /// @param _l2Recipient The L2 recipient of the fees.
    /// @param _portal The portal contract.
    /// @param _gasLimit The gas limit for the deposit transaction.
    /// @param _depositData The deposit data for the deposit transaction.
    function initialize(
        uint256 _depositThreshold,
        address _l2Recipient,
        IOptimismPortal _portal,
        uint64 _gasLimit,
        bytes memory _depositData
    )
        external
        reinitializer(initVersion())
    {
        // Initialization transactions must come from the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        portal = _portal;
        depositThreshold = _depositThreshold;
        l2Recipient = _l2Recipient;
        gasLimit = _gasLimit;
        depositData = _depositData;
    }

    /// @notice Receives ETH and deposits it to the L2 recipient through the portal when the threshold is reached.
    receive() external payable {
        uint256 balance = address(this).balance;
        emit FeesReceived(msg.sender, IOptimismPortal(payable(msg.sender)).l2Sender(), balance);

        if (balance >= depositThreshold) {
            address recipient = l2Recipient;
            portal.depositTransaction{ value: balance }(recipient, balance, gasLimit, false, depositData);
            emit FeesDeposited(recipient, balance);
        }
    }

    /// @notice Updates the deposit threshold.
    /// @param _depositThreshold The new deposit threshold.
    function setDepositThreshold(uint256 _depositThreshold) external {
        _assertOnlyProxyAdminOwner();
        uint256 oldDepositThreshold = depositThreshold;
        depositThreshold = _depositThreshold;
        emit DepositThresholdUpdated(oldDepositThreshold, _depositThreshold);
    }

    /// @notice Updates the L2 recipient for the deposit transaction.
    /// @param _l2Recipient The new L2 recipient.
    function setL2Recipient(address _l2Recipient) external {
        _assertOnlyProxyAdminOwner();
        address oldL2Recipient = l2Recipient;
        l2Recipient = _l2Recipient;
        emit L2RecipientUpdated(oldL2Recipient, _l2Recipient);
    }

    /// @notice Updates the gas limit for the deposit transaction.
    /// @param _gasLimit The new gas limit.
    function setGasLimit(uint64 _gasLimit) external {
        _assertOnlyProxyAdminOwner();
        uint64 oldGasLimit = gasLimit;
        gasLimit = _gasLimit;
        emit GasLimitUpdated(oldGasLimit, _gasLimit);
    }

    /// @notice Updates the deposit data.
    /// @param _depositData The new deposit data.
    function setDepositData(bytes memory _depositData) external {
        _assertOnlyProxyAdminOwner();
        bytes memory oldDepositData = depositData;
        depositData = _depositData;
        emit DepositDataUpdated(oldDepositData, _depositData);
    }
}
