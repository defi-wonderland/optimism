// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { GhostStorage } from "./GhostStorage.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { IStdCheats } from "../interfaces/IStdCheats.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";
import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

// Actors handler, reusing the msg.sender used by Medusa (defined in the json)
// and tracking them, allowing to aggregate balances for instance.
//
// Also allows to call the superchain token bridge and the L2 to L2 messenger.
contract Actors {
    event ActorsLog(string);

    IStdCheats internal _vm = IStdCheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address public superchainTokenBridge = Predeploys.SUPERCHAIN_TOKEN_BRIDGE;
    address public l2ToL2ToCDM = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    function callBridgeRelayERC20(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        uint256 _source
    )
        public
        returns (bool)
    {
        try ISuperchainTokenBridge(superchainTokenBridge).relayERC20(_token, _from, _to, _amount) {
            return true;
        } catch {
            return false;
        }
    }

    function callBridgeSendERC20(
        address _token,
        address _to,
        uint256 _amount,
        uint256 _chainId
    )
        public
        returns (bool)
    {
        try ISuperchainTokenBridge(superchainTokenBridge).sendERC20(_token, _to, _amount, _chainId) {
            return true;
        } catch {
            return false;
        }
    }

    function callL2ToL2MessengerRelayMessage(
        Identifier memory _id,
        bytes memory _message
    )
        public
        returns (bool _success)
    {
        // NOTE: Need to use low-level call or otherwise medusa compiler complains about the identifier type, even
        // though it's the same as the one used in the interface.
        (_success,) =
            l2ToL2ToCDM.call(abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.relayMessage.selector, _id, _message));
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
