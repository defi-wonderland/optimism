// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { OptimismPortal2 } from "src/L1/OptimismPortal2.sol";

/// @custom:proxied true
/// @title OptimismPortalInterop
/// @notice The OptimismPortal is a low-level contract responsible for passing messages between L1
///         and L2. Messages sent directly to the OptimismPortal have no form of replayability.
///         Users are encouraged to use the L1CrossDomainMessenger for a higher-level interface.
contract OptimismPortalInterop is OptimismPortal2 {
    /// @param _proofMaturityDelaySeconds The proof maturity delay in seconds.
    constructor(uint256 _proofMaturityDelaySeconds) OptimismPortal2(_proofMaturityDelaySeconds) { }

    /// @custom:semver +interop.5
    function version() public pure override returns (string memory) {
        return string.concat(super.version(), "+interop.5");
    }
}
