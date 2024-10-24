// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IOptimismMintableERC20Factory } from "./IOptimismMintableERC20Factory.sol";

interface IOptimismMintableERC20FactoryInterop is IOptimismMintableERC20Factory {
    error HashOnionAlreadySet();

    error DeploymentsAlreadyStored();

    error TokensLengthMismatch();

    error InvalidProof();

    error Unauthorized();

    event DeploymentStored(address indexed localToken, address indexed remoteToken);

    event HashOnionUpdated(bytes32 newHashOnion, bytes32 previousHashOnion);

    function hashOnion() external view returns (bytes32 hashOnion_);

    function verifyAndStore(
        address[] calldata _localTokens,
        address[] calldata _remoteTokens,
        bytes32 _startingInnerLayer
    )
        external;

    function setHashOnion(bytes32 _hashOnion) external;
}
