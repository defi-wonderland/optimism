pragma solidity ^0.8.0;

contract GhostStorage {
    uint256 public numberOfActors = 10;
    address[] internal _ghost_actors;
    uint256 internal _ghost_superWethBalancesSum;
    // Amount of Ether sent to the SuperchainWETH contract, that doesn't modify total supply.
    uint256 internal _ghost_superWethEtherSent;
}
