// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Libraries
import { Unauthorized, ZeroAddress } from "src/libraries/errors/CommonErrors.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { SafeSend } from "src/universal/SafeSend.sol";
import { Fee } from "src/libraries/Fee.sol";
// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IL2ToL2CrossDomainMessenger } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import { IETHLiquidity } from "interfaces/L2/IETHLiquidity.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000024
/// @title SuperchainETHBridge
/// @notice SuperchainETHBridge enables ETH transfers between chains within an interop cluster.
contract SuperchainETHBridge is ISemver {
    /// @notice Thrown when attempting to relay a message and the cross domain message sender is not
    /// SuperchainETHBridge.
    error InvalidCrossDomainSender();

    /// @notice Thrown when the rate limit is exceeded.
    error RateLimitExceeded();

    /// @notice Thrown when the amount is too high.
    error AmountTooHigh();

    /// @notice Emitted when ETH is sent from one chain to another.
    /// @param from          Address of the sender.
    /// @param to            Address of the recipient.
    /// @param amount        Amount of ETH sent.
    /// @param destination   Chain ID of the destination chain.
    event SendETH(address indexed from, address indexed to, uint256 amount, uint256 destination);

    /// @notice Emitted whenever ETH is successfully relayed on this chain.
    /// @param from          Address of the msg.sender of sendETH on the source chain.
    /// @param to            Address of the recipient.
    /// @param amount        Amount of ETH relayed.
    /// @param source        Chain ID of the source chain.
    event RelayETH(address indexed from, address indexed to, uint256 amount, uint256 source);

    /// @notice Semantic version.
    /// @custom:semver 1.0.1
    string public constant version = "1.0.1";

    uint256 public constant INTEROP_LAUNCH = 1745340856; // 22 apr

    /// Fee calculation parameters
    uint256 public constant MAX_FEE_PERCENTAGE = 0.02e18; // 2%
    uint256 public constant MAX_PERMITTED_AMOUNT = 200 ether;
    uint256 public constant CURVE_EXPONENT = 8;
    uint256 public constant BASE_FEE = 0.0001 ether;

    /// Token bucket parameters
    uint256 public constant REFILL_RATE = 1 ether; // 1 ether per second
    uint256 public tokens = 100 ether;
    uint256 public lastRefillTime = block.timestamp;

    function _bucketCapacity() internal view returns (uint256) {
        if (block.timestamp - INTEROP_LAUNCH > 7 days) {
            return 500 ether;
        } else if (block.timestamp - INTEROP_LAUNCH > 14 days) {
            return 1000 ether;
        } else if (block.timestamp - INTEROP_LAUNCH > 21 days) {
            return 2000 ether;
        } else {
            return 10_000 ether;
        }
    }

    function _refill() internal {
        uint256 nowTime = block.timestamp;
        uint256 elapsed = nowTime - lastRefillTime;
        uint256 refillAmount = elapsed * REFILL_RATE;
        tokens = _min(_bucketCapacity(), tokens + refillAmount);
        lastRefillTime = nowTime;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Sends ETH to some target address on another chain.
    /// @param _to       Address to send ETH to.
    /// @param _chainId  Chain ID of the destination chain.
    /// @return msgHash_ Hash of the message sent.
    function sendETH(address _to, uint256 _chainId) external payable returns (bytes32 msgHash_) {
        if (_to == address(0)) revert ZeroAddress();
        if (msg.value > MAX_PERMITTED_AMOUNT) revert AmountTooHigh();

        uint256 amountToSend =
            msg.value - Fee.calculateFee(msg.value, MAX_PERMITTED_AMOUNT, CURVE_EXPONENT, MAX_FEE_PERCENTAGE, BASE_FEE);

        // NOTE: 'burn' will soon change to 'deposit'.
        IETHLiquidity(Predeploys.ETH_LIQUIDITY).burn{ value: msg.value }();

        msgHash_ = IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).sendMessage({
            _destination: _chainId,
            _target: address(this),
            _message: abi.encodeCall(this.relayETH, (msg.sender, _to, amountToSend))
        });

        emit SendETH(msg.sender, _to, msg.value, _chainId);
    }

    /// @notice Relays ETH received from another chain.
    /// @param _from       Address of the msg.sender of sendETH on the source chain.
    /// @param _to         Address to relay ETH to.
    /// @param _amount     Amount of ETH to relay.
    function relayETH(address _from, address _to, uint256 _amount) external {
        if (msg.sender != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) revert Unauthorized();

        (address crossDomainMessageSender, uint256 source) =
            IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).crossDomainMessageContext();

        if (crossDomainMessageSender != address(this)) revert InvalidCrossDomainSender();

        // NOTE: 'mint' will soon change to 'withdraw'.
        IETHLiquidity(Predeploys.ETH_LIQUIDITY).mint(_amount);

        _refill();

        if (_amount > tokens) revert RateLimitExceeded();

        unchecked {
            tokens -= _amount;
        }

        // This is a forced ETH send to the recipient, the recipient should NOT expect to be called.
        new SafeSend{ value: _amount }(payable(_to));

        emit RelayETH(_from, _to, _amount, source);
    }
}
