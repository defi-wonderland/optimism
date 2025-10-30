// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { L2ContractsManager } from "src/L2/L2ContractsManager.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { IL1ChugSplashProxy } from "interfaces/legacy/IL1ChugSplashProxy.sol";
import { IAddressManager } from "interfaces/legacy/IAddressManager.sol";
import { Constants } from "src/libraries/Constants.sol";

/// @title XForkContractsManager
/// @notice The XForkContractsManager is responsible for orquestrating the upgrades of the L2 contracts during xFork
/// hardforks.
contract XForkContractsManager is L2ContractsManager {
    /// @notice Hook called before execution.
    function _beforeExecution() internal override { }

    /// @notice Hook called after execution.
    function _afterExecution(bytes memory returnData) internal override { }

    /// @notice Performs the actual execution logic.
    /// @dev Inlines the upgrade logic from ProxyAdmin to avoid external call frames.
    ///      Since we execute via delegatecall in ProxyAdmin's context, we can access
    ///      ProxyAdmin's storage and call upgrade methods directly.
    /// @param _data Encoded arrays of predeploy addresses and their new implementation addresses.
    /// @return returnData Encoded boolean indicating success.
    function _performExecute(bytes memory _data) internal override returns (bytes memory returnData) {
        (address[] memory predeploysAddresses, address[] memory predeploysImplAddresses) =
            abi.decode(_data, (address[], address[]));

        for (uint256 i = 0; i < predeploysAddresses.length; i++) {
            address payable proxy = payable(predeploysAddresses[i]);
            address implementation = predeploysImplAddresses[i];

            // Access ProxyAdmin's proxyType storage via public getter (we're in its context)
            IProxyAdmin.ProxyType ptype = IProxyAdmin(address(this)).proxyType(proxy);

            if (ptype == IProxyAdmin.ProxyType.ERC1967) {
                IProxy(proxy).upgradeTo(implementation);
            } else if (ptype == IProxyAdmin.ProxyType.CHUGSPLASH) {
                IL1ChugSplashProxy(proxy).setStorage(
                    Constants.PROXY_IMPLEMENTATION_ADDRESS, bytes32(uint256(uint160(implementation)))
                );
            } else if (ptype == IProxyAdmin.ProxyType.RESOLVED) {
                string memory name = IProxyAdmin(address(this)).implementationName(proxy);
                IAddressManager(IProxyAdmin(address(this)).addressManager()).setAddress(name, implementation);
            } else {
                // Should not be possible, but matches ProxyAdmin's assert(false)
                revert("XForkContractsManager: unknown proxy type");
            }
        }

        return abi.encode(true);
    }
}
