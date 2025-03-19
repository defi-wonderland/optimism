// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { GhostStorage } from "./GhostStorage.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";
import { ISuperchainWETH } from "interfaces/L2/ISuperchainWETH.sol";
import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { vm } from "../utils/VM.sol";

interface ICrossL2InboxWithSlotWarming {
    function warmSlot(bytes32 _slot) external view returns (uint256 res_);

    function isWarm(bytes32 _slot) external view returns (bool isWarm_, uint256 value_);

    function calculateChecksum(Identifier memory _id, bytes32 _msgHash) external pure returns (bytes32 checksum_);
}

// Actors handler, reusing the msg.sender used by Medusa (defined in the json)
// and tracking them, allowing to aggregate balances for instance.
//
// Also allows to call the superchain token bridge and the L2 to L2 messenger.
contract Actors {
    event ActorsLog(string);

    address public immutable SUPERCHAIN_TOKEN_BRIDGE = Predeploys.SUPERCHAIN_TOKEN_BRIDGE;
    address public immutable L2_TO_L2_CROSS_DOMAIN_MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;
    address public immutable SUPERCHAIN_WETH = Predeploys.SUPERCHAIN_WETH;

    function callBridgeRelayERC20(address _token, address _from, address _to, uint256 _amount) public returns (bool) {
        try ISuperchainTokenBridge(SUPERCHAIN_TOKEN_BRIDGE).relayERC20(_token, _from, _to, _amount) {
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
        try ISuperchainTokenBridge(SUPERCHAIN_TOKEN_BRIDGE).sendERC20(_token, _to, _amount, _chainId) {
            return true;
        } catch {
            return false;
        }
    }

    function callL2ToL2MessengerRelayMessage(
        Identifier memory _id,
        bytes memory _message,
        bytes32 _slot
    )
        public
        returns (bool _success)
    {
        if (_slot != bytes32(0)) {
            ICrossL2InboxWithSlotWarming(L2_TO_L2_CROSS_DOMAIN_MESSENGER).warmSlot(_slot);
        }

        // NOTE: Need to use low-level call or otherwise medusa compiler complains about the identifier type, even
        // though it's the same as the one used in the interface.
        (_success,) = L2_TO_L2_CROSS_DOMAIN_MESSENGER.call(
            abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.relayMessage.selector, _id, _message)
        );
    }

    function callSuperchainWETHSendETH(address _to, uint256 _chainId) public payable returns (bool _success) {
        try ISuperchainWETH(payable(SUPERCHAIN_WETH)).sendETH{ value: msg.value }(_to, _chainId) {
            return true;
        } catch {
            return false;
        }
    }

    function directCall(
        address _target,
        uint256 _msgValue,
        bytes memory _payload
    )
        public
        returns (bool _success, bytes memory _returnData)
    {
        emit ActorsLog(string.concat("call using actor: ", vm.toString(address(this))));

        (_success, _returnData) = _target.call{ value: _msgValue }(_payload);

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
