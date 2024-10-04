// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IOptimismERC20Factory } from "./IOptimismERC20Factory.sol";
import { ISemver } from "src/universal/interfaces/ISemver.sol";

/// @title IOptimismSuperchainERC20Factory
/// @notice Interface for OptimismSuperchainERC20Factory.
interface IOptimismSuperchainERC20Factory is IOptimismERC20Factory, ISemver {
    /// @notice Emitted when an OptimismSuperchainERC20 is deployed.
    /// @param superchainToken  Address of the OptimismSuperchainERC20 deployment.
    /// @param remoteToken      Address of the corresponding token on the remote chain.
    /// @param deployer         Address of the account that deployed the token.
    event OptimismSuperchainERC20Created(
        address indexed superchainToken, address indexed remoteToken, address deployer
    );

    /// @notice Deploys a OptimismSuperchainERC20 Beacon Proxy using CREATE3.
    /// @param _remoteToken      Address of the remote token.
    /// @param _name             Name of the OptimismSuperchainERC20.
    /// @param _symbol           Symbol of the OptimismSuperchainERC20.
    /// @param _decimals         Decimals of the OptimismSuperchainERC20.
    /// @return superchainERC20_ Address of the OptimismSuperchainERC20 deployment.
    function deploy(
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        external
        returns (address superchainERC20_);

    function __constructor__() external;
}
