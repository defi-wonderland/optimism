// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { GameType, Timestamp, GameStatus } from "src/dispute/lib/Types.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { vm } from "../utils/VM.sol";

contract DisputeGameFactoryMock {
    Timestamp public createdAt;

    constructor() {
        createdAt = Timestamp.wrap(uint64(block.timestamp) + 1);
    }

    function gameAtIndex(uint256)
        external
        view
        returns (GameType gameType_, Timestamp timestamp_, IDisputeGame proxy_)
    {
        GameType gameType;
        Timestamp timestamp;
        address proxy = address(this);
        (gameType_, timestamp_, proxy_) = (gameType, timestamp, IDisputeGame(proxy));
    }

    function status() external view returns (GameStatus) {
        return GameStatus.DEFENDER_WINS;
    }

    function wasRespectedGameTypeWhenCreated() external view returns (bool) {
        return true;
    }
}
