// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";

interface ICrossL2InboxWithSlotWarming {
    function warmSlot(bytes32 _slot) external view returns (uint256 res_);

    function isWarm(bytes32 _slot) external view returns (bool isWarm_, uint256 value_);

    function calculateChecksum(Identifier memory _id, bytes32 _msgHash) external pure returns (bytes32 checksum_);
}
