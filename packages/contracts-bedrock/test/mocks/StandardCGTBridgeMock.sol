// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { StandardCGTBridge } from "src/universal/StandardCGTBridge.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";

/// @title MockStandardCGTBridge
/// @notice Simple wrapper around the StandardCGTBridge contract that exposes
///         internal functions and provides concrete implementations for virtual functions
///         so they can be more easily tested directly.
contract StandardCGTBridgeMock is StandardCGTBridge {
    /// @notice Initialize the contract for testing
    function init(
        address _cgtToken,
        ICrossDomainMessenger _messenger,
        StandardCGTBridge _otherBridge
    )
        external
        initializer
    {
        __StandardCGTBridge_init(_cgtToken, _messenger, _otherBridge);
    }

    /// @notice Expose finalizeBridgeCGT function for testing
    function finalizeBridgeCGT(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        override
        onlyOtherBridge
    {
        // Empty implementation for testing modifiers only
        // Actual implementation will be in L1/L2 specific contracts
    }
}
