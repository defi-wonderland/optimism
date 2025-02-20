// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Contracts
import { XERC20Lockbox } from "@xERC20/contracts/XERC20Lockbox.sol";
import { CrosschainERC20 } from "src/L2/CrosschainERC20/CrosschainERC20.sol";
import { ERC7802Adapter } from "src/L2/CrosschainERC20/ERC7802Adapter.sol";

// Libraries
import { CREATE3 } from "isolmate/utils/CREATE3.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

contract CrosschainERC20Factory {
    error InvalidLength();

    /// @notice Deploys a new CrosschainERC20 contract and returns the address
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @return _crosschainERC20 The address of the new CrosschainERC20 contract
    function deployCrosschainERC20(
        string memory _name,
        string memory _symbol
    )
        external
        returns (address _crosschainERC20)
    {
        _crosschainERC20 = _deployCrosschainERC20(_name, _symbol);
    }

    /// @notice Deploys a new CrosschainERC20Lockbox and CrosschainERC20
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @param _ERC20 The address of the ERC20 contract
    /// @return _crosschainERC20 The address of the new CrosschainERC20 contract
    /// @return _xERC20Lockbox The address of the new xERC20Lockbox contract
    function deployXERC20Lockbox(
        string memory _name,
        string memory _symbol,
        address _ERC20
    )
        external
        returns (address _crosschainERC20, address _xERC20Lockbox)
    {
        _crosschainERC20 = _deployCrosschainERC20(_name, _symbol);
        _xERC20Lockbox = _deployLockbox(_crosschainERC20, _ERC20);
    }

    /// @notice Deploys a new ERC7802Adapter
    /// @param _xERC20 The address of the XERC20 contract
    /// @return _erc7802Adapter The address of the new ERC7802Adapter contract
    function deployERC7802Adapter(address _xERC20) external returns (address _erc7802Adapter) {
        _erc7802Adapter = _deployERC7802Adapter(_xERC20);
    }

    function _deployCrosschainERC20(
        string memory _name,
        string memory _symbol
    )
        internal
        returns (address _crosschainERC20)
    {
        bytes32 _salt = keccak256(abi.encodePacked(_name, _symbol, msg.sender));
        bytes memory _creation = type(CrosschainERC20).creationCode;
        bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_name, _symbol, address(this)));

        _crosschainERC20 = CREATE3.deploy(_salt, _bytecode, 0);

        // Set the limits to the max value to allow for unlimited minting and burning
        uint256 _limit = type(uint256).max >> 1;

        // Allow the SuperchainTokenBridge as default minter and burner
        CrosschainERC20(_crosschainERC20).setLimits(Predeploys.SUPERCHAIN_TOKEN_BRIDGE, _limit, _limit);

        CrosschainERC20(_crosschainERC20).transferOwnership(msg.sender);
    }

    function _deployLockbox(address _crosschainERC20, address _xerc20) internal returns (address payable _lockbox) {
        bytes32 _salt = keccak256(abi.encodePacked(_crosschainERC20, _xerc20, msg.sender));
        bytes memory _creation = type(XERC20Lockbox).creationCode;
        bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_crosschainERC20, _xerc20, false));

        _lockbox = payable(CREATE3.deploy(_salt, _bytecode, 0));

        CrosschainERC20(_crosschainERC20).setLockbox(address(_lockbox));
    }

    function _deployERC7802Adapter(address _crosschainERC20)
        internal
        returns (address _erc7802Adapter)
    {
        bytes32 _salt = keccak256(abi.encodePacked(_crosschainERC20, msg.sender));
        bytes memory _creation = type(ERC7802Adapter).creationCode;
        bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_crosschainERC20));

        _erc7802Adapter = CREATE3.deploy(_salt, _bytecode, 0);
    }
}
