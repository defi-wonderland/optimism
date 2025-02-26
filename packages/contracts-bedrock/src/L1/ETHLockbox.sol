// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Contracts
import { Initializable } from "@openzeppelin/contracts-v5/proxy/utils/Initializable.sol";

// Libraries
import { Unauthorized, Paused } from "src/libraries/errors/CommonErrors.sol";
import { Storage } from "src/libraries/Storage.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IOptimismPortal2 as IOptimismPortal } from "interfaces/L1/IOptimismPortal2.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { Constants } from "src/libraries/Constants.sol";

/// @custom:proxied true
/// @title ETHLockbox
/// @notice Manages ETH liquidity locking and unlocking for authorized OptimismPortals, enabling unified ETH liquidity
///         management across chains in the superchain cluster.
contract ETHLockbox is Initializable, ISemver {
    /// @notice Thrown when attempting to unlock ETH from the lockbox through a withdrawal transaction.
    error NoWithdrawalTransactions();

    /// @notice Thrown when an already authorized portal or lockbox attempts to be authorized again.
    error AlreadyAuthorized();

    /// @notice Emitted when ETH is locked in the lockbox by an authorized portal.
    /// @param portal The address of the portal that locked the ETH.
    /// @param amount The amount of ETH locked.
    event ETHLocked(address indexed portal, uint256 amount);

    /// @notice Emitted when ETH is unlocked from the lockbox by an authorized portal.
    /// @param portal The address of the portal that unlocked the ETH.
    /// @param amount The amount of ETH unlocked.
    event ETHUnlocked(address indexed portal, uint256 amount);

    /// @notice Emitted when a portal is authorized to lock and unlock ETH.
    /// @param portal The address of the portal that was authorized.
    event PortalAuthorized(address indexed portal);

    /// @notice Emitted when an ETH lockbox is authorized to migrate its liquidity to the current ETH lockbox.
    /// @param lockbox The address of the ETH lockbox that was authorized.
    event LockboxAuthorized(address indexed lockbox);

    /// @notice Emitted when ETH liquidity is migrated from the current ETH lockbox to another.
    /// @param lockbox The address of the ETH lockbox that was migrated.
    event LiquidityMigrated(address indexed lockbox);

    /// @notice Emitted when ETH liquidity is received during an authorized lockbox migration.
    /// @param lockbox The address of the ETH lockbox that received the liquidity.
    event LiquidityReceived(address indexed lockbox);

    /// @notice The address of the SuperchainConfig contract.
    bytes32 internal constant SUPERCHAIN_CONFIG_SLOT = bytes32(uint256(keccak256("ETHLockbox.superchainConfig")) - 1);

    /// @notice Mapping of authorized portals.
    mapping(address => bool) public authorizedPortals;

    /// @notice Mapping of authorized lockboxes.
    mapping(address => bool) public authorizedLockboxes;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-beta.1
    function version() public view virtual returns (string memory) {
        return "1.0.0-beta.1";
    }

    /// @notice Constructs the ETHLockbox contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _superchainConfig The address of the SuperchainConfig contract.
    function initialize(address _superchainConfig) external initializer {
        Storage.setAddress(SUPERCHAIN_CONFIG_SLOT, _superchainConfig);
    }

    /// @notice Getter for the SuperchainConfig contract.
    function superchainConfig() public view returns (ISuperchainConfig superchainConfig_) {
        superchainConfig_ = ISuperchainConfig(Storage.getAddress(SUPERCHAIN_CONFIG_SLOT));
    }

    /// @notice Getter for the owner of the proxy admin.
    ///         The ProxyAdmin is the owner of the Proxy contract, which is the proxy used for the ETHLockbox.
    function adminOwner() public view returns (address) {
        // Get the proxy admin address reading for the reserved slot it has on the Proxy contract.
        IProxyAdmin proxyAdmin = IProxyAdmin(Storage.getAddress(Constants.PROXY_OWNER_ADDRESS));
        // Return the owner of the proxy admin.
        return proxyAdmin.owner();
    }

    /// @notice Getter for the current paused status.
    function paused() public view returns (bool) {
        return superchainConfig().paused();
    }

    /// @notice Receives the ETH liquidity migrated from an authorized lockbox.
    function receiveLiquidity() external payable {
        if (!authorizedLockboxes[msg.sender]) revert Unauthorized();
        emit LiquidityReceived(msg.sender);
    }

    /// @notice Locks ETH in the lockbox.
    ///         Called by an authorized portal on a deposit to lock the ETH value.
    function lockETH() external payable {
        if (!authorizedPortals[msg.sender]) revert Unauthorized();
        emit ETHLocked(msg.sender, msg.value);
    }

    /// @notice Unlocks ETH from the lockbox.
    ///         Called by an authorized portal when finalizing a withdrawal that requires ETH.
    ///         Cannot be called if the lockbox is paused.
    /// @param _value The amount of ETH to unlock.
    function unlockETH(uint256 _value) external {
        if (paused()) revert Paused();
        if (!authorizedPortals[msg.sender]) revert Unauthorized();
        if (IOptimismPortal(payable(msg.sender)).l2Sender() != Constants.DEFAULT_L2_SENDER) {
            revert NoWithdrawalTransactions();
        }

        // Using `donateETH` to avoid triggering a deposit
        IOptimismPortal(payable(msg.sender)).donateETH{ value: _value }();
        emit ETHUnlocked(msg.sender, _value);
    }

    /// @notice Authorizes a portal to lock and unlock ETH.
    /// @param _portal The address of the portal to authorize.
    function authorizePortal(address _portal) external {
        if (msg.sender != adminOwner()) revert Unauthorized();
        if (authorizedPortals[_portal]) revert AlreadyAuthorized();

        authorizedPortals[_portal] = true;
        emit PortalAuthorized(_portal);
    }

    /// @notice Authorizes an ETH lockbox to migrate its liquidity to the current ETH lockbox.
    /// @param _lockbox The address of the ETH lockbox to authorize.
    function authorizeLockbox(address _lockbox) external {
        if (msg.sender != adminOwner()) revert Unauthorized();
        if (authorizedLockboxes[_lockbox]) revert AlreadyAuthorized();

        authorizedLockboxes[_lockbox] = true;
        emit LockboxAuthorized(_lockbox);
    }

    /// @notice Migrates liquidity from the current ETH lockbox to another.
    /// @param _lockbox The address of the ETH lockbox to migrate liquidity to.
    function migrateLiquidity(address _lockbox) external {
        if (msg.sender != adminOwner()) revert Unauthorized();
        if (adminOwner() != ETHLockbox(_lockbox).adminOwner()) revert Unauthorized();

        ETHLockbox(_lockbox).receiveLiquidity{ value: address(this).balance }();
        emit LiquidityMigrated(_lockbox);
    }
}
