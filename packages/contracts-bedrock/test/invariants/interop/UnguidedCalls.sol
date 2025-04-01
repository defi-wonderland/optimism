// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { FuzzTest } from "./FuzzTest.sol";
import { Types } from "src/libraries/Types.sol";
import { IOptimismPortalMock } from "./interfaces/IOptimismPortalMock.sol";
import { vm } from "./utils/VM.sol";

contract UnguidedCalls is FuzzTest {
    /// @notice Unguided test that doesn't match any specific property, but checks that withdrawal finalization
    ///         checks are correct by making a malicious call on a target contract.
    function test_finalizeWithdrawalReverts_unguided(
        address _caller,
        Types.WithdrawalTransaction memory _tx,
        uint256 _callIndex
    )
        public
        initialize
    {
        // Get the call to be made.
        bytes4 call = WEIRD_TARGET.calls(_callIndex % _ghost_weirdTargetCallsLength);

        _tx.value = clampLte(_tx.value, address(ETH_LOCKBOX).balance);
        _tx.target = address(WEIRD_TARGET);
        _tx.data = abi.encodeWithSelector(call);
        // Gas is limit is out of scope
        _tx.gasLimit = type(uint256).max;

        // Setting not used parameters to empty values
        bytes[] memory withdrawalProof = new bytes[](0);
        Types.OutputRootProof memory outputRootProof;
        uint256 disputeGameIndex = 0;

        // Prove the withdrawal transaction.
        vm.prankHere(address(_caller));
        try IOptimismPortalMock(address(PORTAL)).proveWithdrawalTransaction(
            _tx, disputeGameIndex, outputRootProof, withdrawalProof
        ) { } catch {
            // Make sure the call doesn't revert.
            assert(false);
        }

        // Finalize the withdrawal transaction.
        vm.warp(block.timestamp + PROOF_MATURITY_DELAY_SECONDS + 1);
        try IOptimismPortalMock(address(PORTAL)).finalizeWithdrawalTransaction(_tx) returns (bool success) {
            // Ensure the WeirdTarget call reverts.
            assert(!success);
        } catch { }
    }
}
