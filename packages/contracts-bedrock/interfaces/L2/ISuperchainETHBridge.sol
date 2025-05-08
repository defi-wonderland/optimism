// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISemver } from "interfaces/universal/ISemver.sol";

interface ISuperchainETHBridge is ISemver {
    error Unauthorized();
    error InvalidCrossDomainSender();
    error ZeroAddress();
    error AmountTooHigh();
    error NoBucketAvailability();

    event SendETH(address indexed from, address indexed to, uint256 amount, uint256 destination);

    event RelayETH(address indexed from, address indexed to, uint256 amount, uint256 source);

    function ETH_RATE_LIMIT_ACTIVATION() external view returns (uint256);

    function MAX_FEE_PERCENTAGE() external view returns (uint256);

    function CURVE_EXPONENT() external view returns (uint256);

    function BASE_FEE() external view returns (uint256);

    function REFILL_TIME_WINDOW() external view returns (uint256);

    function bucketCapacity() external view returns (uint256);

    function maxTxETHAmount() external view returns (uint256);

    function bucketAvailable() external view returns (uint256 bucketAvailable_, uint256 bucketRefillAmount_);

    function calculateFee(uint256 amount) external view returns (uint256);

    function sendETH(address _to, uint256 _chainId) external payable returns (bytes32 msgHash_);
    function relayETH(address _from, address _to, uint256 _amount) external;

    function __constructor__() external;
}
