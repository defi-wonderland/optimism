// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISuperchainConfig {
    enum UpdateType {
        GUARDIAN
    }

    event ConfigUpdate(UpdateType indexed updateType, bytes data);
    event Initialized(uint8 version);
    event Paused(string identifier);
    event Unpaused();

    function GUARDIAN_SLOT() external view returns (bytes32);
    function PAUSED_SLOT() external view returns (bytes32);
    function guardian() external view returns (address guardian_);
    function initialize(address _guardian, bool _paused, address _sharedLockbox) external;
    function pause(string memory _identifier) external;
    function paused() external view returns (bool paused_);
    function unpause() external;
    function version() external view returns (string memory);
    function addChain(uint256 chainId, address systemConfig) external;
    function dependencySet(uint256 chainId) external view returns (uint256);
    function isInDependencySet(uint256 chainId) external view returns (bool);

    function __constructor__() external;
}
