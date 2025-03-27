// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IOptimismPortal2 as IOptimismPortal } from "interfaces/L1/IOptimismPortal2.sol";
import { IETHLockbox } from "interfaces/L1/IETHLockbox.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";

contract GhostStorage {
    struct Chain {
        IOptimismPortal portal;
        IETHLockbox ethLockbox;
        address anchorRegistry;
    }

    // The salt counter for the deployment of the chains contracts.
    uint256 internal _ghost_saltCounter;

    /// NOTE: A higher number results in an OOG error while deploying the chains. They can't be deployed and initialized
    ///       on the tests or handlers because Medusa fails there.
    // The number of chains that have been deployed and initialized.
    uint256 internal _GHOST_NUMBER_OF_CHAINS = 15;

    // The number of actors that will be used to fuzz the test.
    uint256 public constant NUMBER_OF_ACTORS = 10;
    address[] internal _ghost_actors;
    uint256 internal _ghost_superWethBalancesSum;
    // Amount of Ether sent to the SuperchainWETH contract, that doesn't modify total supply.
    uint256 internal _ghost_superWethEtherSent;

    // Whether the L1 and L2 proxies have been initialized`
    bool internal _ghost_isInitialized;

    // The number of calls that can be made to the WeirdTarget.
    uint256 internal _ghost_weirdTargetCallsLength;

    // Tracks the last chain that was added or migrated to the current `ETHLockbox`.
    uint256 internal _ghost_lastAddedChain;

    // The chains that have been added or migrated to the current `ETHLockbox`.
    mapping(uint256 => Chain) internal _ghost_chains;

    // Whether the chains have been initialized.
    bool internal _ghost_chainsInitialized;

    mapping(address => bool) internal _ghost_isL1Contract;
    mapping(address => bool) internal _ghost_isL2Contract;
}
