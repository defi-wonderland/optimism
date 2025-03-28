// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { ICrossL2Inbox } from "interfaces/L2/ICrossL2Inbox.sol";

interface ICrossL2InboxWithSlotWarming is ICrossL2Inbox {
    function warmSlot(bytes32 _slot) external view returns (uint256 res_);

    function isWarm(bytes32 _slot) external view returns (bool isWarm_, uint256 value_);
}
