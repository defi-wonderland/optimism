// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { GhostStorage } from "./GhostStorage.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { ISuperchainTokenBridge } from "interfaces/L2/ISuperchainTokenBridge.sol";
import { ISuperchainWETH } from "interfaces/L2/ISuperchainWETH.sol";
import { Identifier } from "interfaces/L2/ICrossL2Inbox.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { vm } from "../utils/VM.sol";
import { Hashing } from "src/libraries/Hashing.sol";

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
    struct CallRelayParams {
        Identifier id;
        bytes messageSent;
        bytes message;
        uint256 nonce;
    }

    event ActorsLog(string);

    address public immutable SUPERCHAIN_TOKEN_BRIDGE = Predeploys.SUPERCHAIN_TOKEN_BRIDGE;
    address public immutable L2_TO_L2_CROSS_DOMAIN_MESSENGER = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;
    address public immutable SUPERCHAIN_WETH = Predeploys.SUPERCHAIN_WETH;
    address public immutable CROSS_L2_INBOX = Predeploys.CROSS_L2_INBOX;

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

    function callSuperchainWETHSendETH(address _to, uint256 _chainId) public payable returns (bool _success) {
        try ISuperchainWETH(payable(SUPERCHAIN_WETH)).sendETH{ value: msg.value }(_to, _chainId) {
            return true;
        } catch {
            return false;
        }
    }

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
