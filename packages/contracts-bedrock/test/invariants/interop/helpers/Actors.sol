// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Predeploys } from "src/libraries/Predeploys.sol";
import { GhostStorage } from "./GhostStorage.sol";
import { vm } from "../utils/VM.sol";

// Actors handler, reusing the msg.sender used by Medusa (defined in the json)
// and tracking them, allowing to aggregate balances for instance.
contract Actors {
    /// NOTE: Leaving here to avoid stack underflow failures while calling `Permit2Mock` contract.
    address public immutable SUPERCHAIN_TOKEN_BRIDGE = Predeploys.SUPERCHAIN_TOKEN_BRIDGE;
    address public immutable L2_TO_L2_CROSS_DOMAIN_MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;
    address public immutable SUPERCHAIN_WETH = Predeploys.SUPERCHAIN_WETH;
    address public immutable CROSS_L2_INBOX = Predeploys.CROSS_L2_INBOX;

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
