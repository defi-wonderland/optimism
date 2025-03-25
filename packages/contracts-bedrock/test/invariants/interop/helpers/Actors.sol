// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { GhostStorage } from "./GhostStorage.sol";
import { vm } from "../utils/VM.sol";

// Actors handler, reusing the msg.sender used by Medusa (defined in the json)
// and tracking them, allowing to aggregate balances for instance.
contract Actors {
    event ActorsLog(string);

    function directCall(
        address _target,
        uint256 _value,
        bytes memory _payload
    )
        public
        returns (bool _success, bytes memory _returnData)
    {
        emit ActorsLog(string.concat("call using actor: ", vm.toString(address(this))));

        (_success, _returnData) = _target.call{ value: _value }(_payload);

        emit ActorsLog(string.concat("return data: ", vm.toString(_returnData)));
    }

    function ethBalance() public view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable { }
}

contract HandlerActors is GhostStorage {
    function currentActor() public view returns (Actors _actor) {
        uint256 _seed = uint256(uint160(msg.sender));
        _actor = Actors(payable(_ghost_actors[(_seed % _ghost_actors.length) - 1]));
    }

    function randomActor(uint256 _seed) public view returns (Actors _actor) {
        _actor = Actors(payable(_ghost_actors[_seed % _ghost_actors.length]));
    }
}
