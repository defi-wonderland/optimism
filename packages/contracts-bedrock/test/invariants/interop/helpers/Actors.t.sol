// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { GhostStorage } from "./GhostStorage.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IStdCheats } from "../interfaces/IStdCheats.sol";

// Actors handler, reusing the msg.sender used by Medusa (defined in the json)
// and tracking them, allowing to aggregate balances for instance.
//
// Also allows to call the superchain token bridge and the L2 to L2 messenger.
contract Actors {
    event ActorsLog(string);

    IStdCheats internal _vm = IStdCheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address public superchainTokenBridge = Predeploys.SUPERCHAIN_TOKEN_BRIDGE;
    address public l2ToL2ToCDM = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    function callSuperchainTokenBridge(bytes memory _payload) public returns (bool _success, bytes memory _ret) {
        emit ActorsLog(string.concat("call using actor: ", _vm.toString(address(this))));
        emit ActorsLog(string.concat("stoken bridge address: ", _vm.toString(superchainTokenBridge)));

        (_success, _ret) = superchainTokenBridge.call(_payload);
        emit ActorsLog(_vm.toString(_ret));

        if (!_success) {
            emit ActorsLog(_vm.toString(_ret));
            return (_success, _ret);
        }

        // TODO: Check if needed in the campaign afterwards
        if (_ret.length != 0) {
            _ret = abi.decode(_ret, (bytes));
        }

        return (_success, _ret);
    }

    function callL2ToL2Messenger(bytes memory _payload) public returns (bool _success, bytes memory _ret) {
        emit ActorsLog(string.concat("call using actor: ", _vm.toString(address(this))));

        (_success, _ret) = l2ToL2ToCDM.call(_payload);

        if (!_success) {
            emit ActorsLog(_vm.toString(_ret));
            return (_success, _ret);
        }

        // TODO: Check if needed in the campaign afterwards
        if (_ret.length != 0) {
            _ret = abi.decode(_ret, (bytes));
        }

        return (_success, _ret);
    }

    function directCall(
        address _target,
        uint256 _msgValue,
        bytes memory _payload
    )
        public
        returns (bool _success, bytes memory _returnData)
    {
        emit ActorsLog(string.concat("call using actor: ", _vm.toString(address(this))));

        _vm.deal(payable(address(this)), _msgValue);

        (_success, _returnData) = _target.call{ value: _msgValue }(_payload);
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
