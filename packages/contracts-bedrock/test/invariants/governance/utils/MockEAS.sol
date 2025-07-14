// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Attestation } from "src/vendor/eas/IEAS.sol";

contract MockEAS {
    mapping(bytes32 => Attestation) public attestations;

    function getAttestation(bytes32 _uid) external view returns (Attestation memory) {
        return attestations[_uid];
    }

    function forTest_setAttestation(bytes32 _uid, Attestation memory _attestation) external {
        attestations[_uid] = _attestation;
    }
}
