// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { Storage } from "src/libraries/Storage.sol";
import { Constants } from "src/libraries/Constants.sol";

/// @notice Base contract for ProxyAdmin-owned contracts. It's main goal is to expose the ProxyAdmin owner address on
///         a function and also to check if the current contract and a given proxy have the same ProxyAdmin owner.
abstract contract ProxyAdminOwnedBase {
    /// @notice Getter for the owner of the ProxyAdmin.
    ///         The ProxyAdmin is the owner of the current proxy contract.
    function proxyAdminOwner() public view returns (address) {
        console.log("here 1");
        // Get the proxy admin address reading for the reserved slot it has on the Proxy contract.
        IProxyAdmin proxyAdmin = IProxyAdmin(Storage.getAddress(Constants.PROXY_OWNER_ADDRESS));
        console.log("here 2");
        // Return the owner of the proxy admin.
        console.log("3 proxy admin owner", proxyAdmin.owner());
        return proxyAdmin.owner();
        console.log("here 3");
    }

    /// @notice Checks if the ProxyAdmin owner of the current contract is the same as the ProxyAdmin owner of the given
    ///         proxy.
    /// @param _proxy The address of the proxy to check.
    function _sameProxyAdminOwner(address _proxy) internal view returns (bool) {
        console.log("proxy admin owner alfa", proxyAdminOwner());
        console.log("proxy address", _proxy);
        console.log("proxy admin owner proxy", ProxyAdminOwnedBase(_proxy).proxyAdminOwner());
        return proxyAdminOwner() == ProxyAdminOwnedBase(_proxy).proxyAdminOwner();
    }
}

import "forge-std/console.sol";
