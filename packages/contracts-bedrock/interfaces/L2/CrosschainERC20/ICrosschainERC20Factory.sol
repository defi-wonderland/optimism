// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ICrosschainERC20Factory
/// @notice This interface is available on the CrosschainERC20Factory contract.
interface ICrosschainERC20Factory {
    error InvalidLength();

    event CrosschainERC20Deployed(address indexed crosschainERC20, string name, string symbol, address owner);
    event LockboxDeployed(address indexed lockbox, address indexed crosschainERC20, address indexed baseToken);
    event ERC7802AdapterDeployed(address indexed adapter, address indexed xerc20, address indexed bridge);

    function deployCrosschainERC20(string memory _name, string memory _symbol, uint256[] memory _minterLimits, uint256[] memory _burnerLimits, address[] memory _bridges, address _owner) external returns (address crosschainERC20_);

    function deployCrosschainERC20WithLockbox(string memory _name, string memory _symbol, uint256[] memory _minterLimits, uint256[] memory _burnerLimits, address[] memory _bridges, address _baseToken, address _owner) external returns (address crosschainERC20_, address crosschainERC20Lockbox_);

    function deployERC7802Adapter(address _xerc20, address _bridge) external returns (address erc7802Adapter_);
}