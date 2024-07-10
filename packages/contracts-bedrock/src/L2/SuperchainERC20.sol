// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ISuperchainERC20 } from "src/L2/ISuperchainERC20.sol";
import { IL2ToL2CrossDomainMessenger } from "src/L2/IL2ToL2CrossDomainMessenger.sol";
import { ISemver } from "src/universal/ISemver.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";

/// @notice Thrown when attempting to relay a message and the function caller (msg.sender) is not
/// L2ToL2CrossDomainMessenger.
error RelayMessageCallerNotL2ToL2CrossDomainMessenger();

/// @notice Thrown when attempting to relay a message and the cross domain message sender is not this SuperchainERC20.
error MessageSenderNotThisSuperchainERC20();

/// @notice Thrown when while relaying tokens the external call fails.
error ExternalCallFailed();

/// @custom:proxied
/// @title SuperchainERC20
/// @notice SuperchainERC20 is a standard extension of the base ERC20 token contract that unifies ERC20 token bridging
///         to make it fungible across the Superchain. It builds on top of the messaging protocol, as the most trust
///         minimized bridging solution. This construction builds on top of the L2ToL2CrossDomainMessenger for both
///         replay protection and domain binding.
contract SuperchainERC20 is ISuperchainERC20, ERC20, ISemver {
    /// @notice Address of the L2ToL2CrossDomainMessenger.
    address private immutable MESSENGER;

    /// @notice Decimals of the token
    uint8 private immutable DECIMALS;

    /// @notice Emitted whenever tokens are sent to another chain.
    /// @param from    Address of the sender.
    /// @param to      Address of the recipient.
    /// @param amount  Amount of tokens sent.
    /// @param chainId Chain ID of the destination chain.
    /// @param data    Data to be sent with the message.
    event SentERC20(address indexed from, address indexed to, uint256 amount, uint256 chainId, bytes data);

    /// @notice Emitted whenever tokens are successfully relayed on this chain.
    /// @param to     Address of the recipient.
    /// @param amount Amount of tokens relayed.
    /// @param data   Data sent with the message.
    event RelayedERC20(address indexed to, uint256 amount, bytes data);

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @param _messenger   Address of the L2ToL2CrossDomainMessenger.
    /// @param _name        ERC20 name.
    /// @param _symbol      ERC20 symbol.
    /// @param _decimals    ERC20 decimals.
    constructor(
        address _messenger,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        ERC20(_name, _symbol)
    {
        MESSENGER = _messenger;
        DECIMALS = _decimals;
    }

    /// @notice Sends tokens to some target address on another chain.
    /// @param _to      Address to send tokens to.
    /// @param _amount  Amount of tokens to send.
    /// @param _chainId Chain ID of the destination chain.
    /// @param _data    Data to be sent with the message.
    function sendERC20(address _to, uint256 _amount, uint256 _chainId, bytes memory _data) external override {
        _burn(msg.sender, _amount);

        bytes memory _message = abi.encodeCall(this.relayERC20, (_to, _amount, _data));
        IL2ToL2CrossDomainMessenger(MESSENGER).sendMessage(_chainId, address(this), _message);

        emit SentERC20(msg.sender, _to, _amount, _chainId, _data);
    }

    /// @notice Relays tokens received from another chain.
    /// @param _to     Address to relay tokens to.
    /// @param _amount Amount of tokens to relay.
    /// @param _data   Data sent with the message.
    function relayERC20(address _to, uint256 _amount, bytes memory _data) external override {
        if (msg.sender != MESSENGER) revert RelayMessageCallerNotL2ToL2CrossDomainMessenger();

        if (IL2ToL2CrossDomainMessenger(MESSENGER).crossDomainMessageSender() != address(this)) {
            revert MessageSenderNotThisSuperchainERC20();
        }

        _mint(_to, _amount);

        if (_data.length > 0) {
            bool success = SafeCall.call(_to, 0, _data);
            if (!success) revert ExternalCallFailed();
        }

        emit RelayedERC20(_to, _amount, _data);
    }

    /// @notice ERC165 interface check function.
    /// @param _interfaceId Interface ID to check.
    /// @return Whether or not the interface is supported by this contract.
    function supportsInterface(bytes4 _interfaceId) external pure virtual returns (bool) {
        bytes4 iface1 = type(IERC165).interfaceId;
        bytes4 iface2 = type(ISuperchainERC20).interfaceId;
        return _interfaceId == iface1 || _interfaceId == iface2;
    }

    /// @notice Returns the address of the L2ToL2CrossDomainMessenger.
    function messenger() external view override returns (address) {
        return MESSENGER;
    }

    /// @notice Returns the number of decimals used to get its user representation.
    /// For example, if `decimals` equals `2`, a balance of `505` tokens should
    /// be displayed to a user as `5.05` (`505 / 10 ** 2`).
    /// NOTE: This information is only used for _display_ purposes: it in
    /// no way affects any of the arithmetic of the contract, including
    /// {IERC20-balanceOf} and {IERC20-transfer}.
    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }
}
