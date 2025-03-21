pragma solidity ^0.8.0;

contract GhostStorage {
    uint256 public constant NUMBER_OF_ACTORS = 10;
    address[] internal _ghost_actors;
    uint256 internal _ghost_superWethBalancesSum;
    // Amount of Ether sent to the SuperchainWETH contract, that doesn't modify total supply.
    uint256 internal _ghost_superWethEtherSent;

    // Whether the L1 and L2 proxies have been initialized`
    bool internal _ghost_isInitialized;

    // The number of calls that can be made to the WeirdTarget.
    uint256 internal _ghost_weirdTargetCallsLength;

    mapping(address => bool) internal _ghost_isL1Contract;
    mapping(address => bool) internal _ghost_isL2Contract;
}
