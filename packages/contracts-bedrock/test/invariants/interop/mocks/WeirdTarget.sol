// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IETHLockbox } from "interfaces/L1/IETHLockbox.sol";
import { IProxyAdminOwnedBase } from "interfaces/L1/IProxyAdminOwnedBase.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { Types } from "src/libraries/Types.sol";

/// @notice Target of a withdrawal transaction that tries to bypass safety checks on the system
///         and tries to perform malicious or unexpected actions.
contract WeirdTarget {
    IOptimismPortal2 public immutable PORTAL;
    IETHLockbox public immutable ETH_LOCKBOX;

    // The selectors of the functions that can be called.
    bytes4[] public calls;

    constructor(address _portal, address _ethLockbox) {
        PORTAL = IOptimismPortal2(payable(_portal));
        ETH_LOCKBOX = IETHLockbox(_ethLockbox);
    }

    function exposeCalls() external returns (uint256 length_) {
        calls.push(this.callLockboxUnlockETH.selector);
        calls.push(this.callPortalFinalize.selector);
        calls.push(this.callPortalMigrateLiquidity.selector);
        length_ = calls.length;
    }

    function callLockboxUnlockETH() external payable {
        ETH_LOCKBOX.unlockETH(msg.value);
    }

    function callPortalFinalize(Types.WithdrawalTransaction memory _tx) external payable {
        _tx.value = msg.value;
        PORTAL.finalizeWithdrawalTransaction(_tx);
    }

    function callPortalMigrateLiquidity() external {
        PORTAL.migrateLiquidity();
    }

    receive() external payable { }

    fallback() external payable { }

    // Bypass the proxy admin owner check.
    function proxyAdminOwner() external view returns (address) {
        return IProxyAdminOwnedBase(PORTAL).proxyAdminOwner();
    }

    // Bypass the superchain config check.
    function superchainConfig() external view returns (ISuperchainConfig) {
        return IOptimismPortal2(PORTAL).superchainConfig();
    }
}
