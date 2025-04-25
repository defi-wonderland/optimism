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
    /// @notice The bucket checkpoint struct
    /// @param timestamp The timestamp of the last bucket usage checkpoint
    /// @param usage The amount of ETH used from the bucket since the last checkpoint
    /// @dev Packing both values in a single storage slot to save gas
    struct BucketCheckpoint {
        uint128 timestamp;
        uint128 usage;
    }

    /// @notice Thrown when attempting to relay a message and the cross domain message sender is not
    /// SuperchainETHBridge.
    error InvalidCrossDomainSender();

    /// @notice Thrown when there is no enough bucket availability for the given ETH amount.
    error NoBucketAvailability();

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
    /// @custom:semver 1.1.0
    string public constant version = "1.1.0";

    /// @notice The timestamp of the rate limit activation, used to increase the bucket capacity as time passes
    uint256 public constant ETH_RATE_LIMIT_ACTIVATION = 1745340856; // 22 apr

    // TODO: Define proper fee and bucket config values
    /// @notice The maximum fee percentage of the ETH amount calculation
    uint256 public constant MAX_FEE_PERCENTAGE = 0.02e18; // 2%
    /// @notice The curve exponent for the fee calculation
    uint256 public constant CURVE_EXPONENT = 8;
    /// @notice The base fee for the fee calculation
    uint256 public constant BASE_FEE = 100_000;
    /// @notice The refill time window for the bucket
    uint256 public constant REFILL_TIME_WINDOW = 1 hours;

    /// @notice The maximum amount of ETH that can be sent in a single transaction, 70% of the bucket capacity
    uint256 public maxTxETHAmount = 70 * bucketCapacity() / 100;

    /// @notice The last checkpoint of the bucket usage state
    BucketCheckpoint public lastBucketCheckpoint = BucketCheckpoint({ timestamp: uint128(block.timestamp), usage: 0 });

    /// @notice Returns the bucket capacity based on the time since the rate limit activation
    // TODO: Define proper bucket capacity values
    function bucketCapacity() public view returns (uint256) {
        uint256 timeSinceActivation = block.timestamp - ETH_RATE_LIMIT_ACTIVATION;

        if (timeSinceActivation > 30 days) {
            return 2000 ether;
        } else if (timeSinceActivation > 14 days) {
            return 1000 ether;
        } else if (timeSinceActivation > 7 days) {
            return 500 ether;
        } else if (timeSinceActivation > 1 days) {
            return 100 ether;
        } else {
            return 10_000 ether;
        }
    }

    /// @notice Returns the bucket available amount and the bucket refill amount since the last bucket usage checkpoint
    /// @return bucketAvailable_ The available bucket capacity at the current timestamp
    /// @return bucketRefillAmount_ The potential refill amount since the last bucket usage checkpoint
    function bucketAvailable() public view returns (uint256 bucketAvailable_, uint256 bucketRefillAmount_) {
        uint256 elapsedTime = block.timestamp - lastBucketCheckpoint.timestamp;
        // If the time elapsed is greater than the refill time window, the bucket usage is fully available
        if (elapsedTime > REFILL_TIME_WINDOW) {
            return (bucketAvailable_ = bucketCapacity(), bucketRefillAmount_ = lastBucketCheckpoint.usage);
        }

        // Calculate the refill amount based on the time elapsed since the last refill
        uint256 bucketRefillRate = bucketCapacity() / REFILL_TIME_WINDOW;
        bucketRefillAmount_ = elapsedTime * bucketRefillRate;

        // Calculate the new bucket usage
        uint256 newBucketUsage;
        if (bucketRefillAmount_ > lastBucketCheckpoint.usage) {
            // The bucket is fully refilled
            newBucketUsage = 0;
        } else {
            // The bucket is partially refilled
            newBucketUsage = lastBucketCheckpoint.usage - bucketRefillAmount_;
        }

        // Return the current bucket availibility
        bucketAvailable_ = bucketCapacity() - newBucketUsage;
    }

    /// @notice Calculates the fee for the given amount.
    /// @param amount The amount to calculate the fee for.
    /// @return fee The fee for the given amount.
    function calculateFee(uint256 amount) public view returns (uint256) {
        return Fee.calculateFee(amount, maxTxETHAmount, CURVE_EXPONENT, MAX_FEE_PERCENTAGE, BASE_FEE);
    }

    /// @notice Sends ETH to some target address on another chain.
    /// @param _to       Address to send ETH to.
    /// @param _chainId  Chain ID of the destination chain.
    /// @return msgHash_ Hash of the message sent.
    function sendETH(address _to, uint256 _chainId) external payable returns (bytes32 msgHash_) {
        if (_to == address(0)) revert ZeroAddress();
        if (msg.value > maxTxETHAmount) revert AmountTooHigh();

        uint256 amountToSend =
            msg.value - Fee.calculateFee(msg.value, maxTxETHAmount, CURVE_EXPONENT, MAX_FEE_PERCENTAGE, BASE_FEE);

        // NOTE: 'burn' will soon change to 'deposit'.
        IETHLiquidity(Predeploys.ETH_LIQUIDITY).burn{ value: msg.value }();

        msgHash_ = IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).sendMessage({
            _destination: _chainId,
            _target: address(this),
            _message: abi.encodeCall(this.relayETH, (msg.sender, _to, amountToSend))
        });

        emit SendETH(msg.sender, _to, amountToSend, _chainId);
    }

    /// @notice Relays ETH received from another chain.
    /// @param _from       Address of the msg.sender of sendETH on the source chain.
    /// @param _to         Address to relay ETH to.
    /// @param _amount     Amount of ETH to relay.
    function relayETH(address _from, address _to, uint256 _amount) external {
        if (msg.sender != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) revert Unauthorized();

        // Check that the amount is within the rate limit
        if (_amount > maxTxETHAmount) revert AmountTooHigh();
        (uint256 bucketAvailableAmount, uint256 bucketRefillAmount) = bucketAvailable();
        if (_amount > bucketAvailableAmount) revert NoBucketAvailability();

        // Check that the cross domain message sender is valid
        (address crossDomainMessageSender, uint256 source) =
            IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).crossDomainMessageContext();
        if (crossDomainMessageSender != address(this)) revert InvalidCrossDomainSender();

        // Update the bucket usage and timestamp
        if (bucketAvailableAmount == bucketCapacity()) {
            lastBucketCheckpoint.usage = uint128(_amount);
        } else {
            lastBucketCheckpoint.usage += uint128(_amount) - uint128(bucketRefillAmount);
        }
        lastBucketCheckpoint.timestamp = uint128(block.timestamp);

        // NOTE: 'mint' will soon change to 'withdraw'.
        IETHLiquidity(Predeploys.ETH_LIQUIDITY).mint(_amount);

        // This is a forced ETH send to the recipient, the recipient should NOT expect to be called.
        new SafeSend{ value: _amount }(payable(_to));

        emit RelayETH(_from, _to, _amount, source);
    }
}
