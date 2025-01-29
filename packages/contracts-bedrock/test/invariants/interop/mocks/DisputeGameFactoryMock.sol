// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { GameType, Timestamp } from "src/dispute/lib/Types.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { vm } from "../utils/VM.sol";

contract DisputeGameFactoryMock {
    function gameAtIndex(uint256)
        external
        view
        returns (GameType gameType_, Timestamp timestamp_, IDisputeGame proxy_)
    {
        GameType gameType;
        Timestamp timestamp;
        address proxy = address(uint160(uint256(keccak256("gameProxy"))));
        (gameType_, timestamp_, proxy_) = (gameType, timestamp, IDisputeGame(proxy));
    }
}
