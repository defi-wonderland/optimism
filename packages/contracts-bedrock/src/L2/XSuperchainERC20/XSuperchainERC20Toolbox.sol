// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Contracts
import { SuperchainXERC20Lockbox } from "src/L2/XSuperchainERC20/SuperchainXERC20Lockbox.sol";
import { XSuperchainERC20 } from "src/L2/XSuperchainERC20/XSuperchainERC20.sol";
import { SuperchainXERC20Adapter } from "src/L2/XSuperchainERC20/SuperchainXERC20Adapter.sol";

// Libraries
import { CREATE3 } from "isolmate/utils/CREATE3.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";

contract XSuperchainERC20Toolbox {
    error InvalidLength();

    /// @notice Deploys a new XSuperchainERC20 contract and returns the address
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @return _xSuperchainERC20 The address of the new XSuperchainERC20 contract
    function deployXSuperchainERC20(
        string memory _name,
        string memory _symbol
    )
        external
        returns (address _xSuperchainERC20)
    {
        _xSuperchainERC20 = _deployXSuperchainERC20(_name, _symbol);
    }

    /// @notice Deploys a new XSuperchainERC20Lockbox and XSuperchainERC20
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @param _xERC20 The address of the XERC20 contract
    /// @return _xSuperchainERC20 The address of the new XSuperchainERC20 contract
    /// @return _superchainXERC20Lockbox The address of the new XSuperchainERC20Lockbox contract
    function deploySuperchainXERC20Lockbox(
        string memory _name,
        string memory _symbol,
        address _xERC20
    )
        external
        returns (address _xSuperchainERC20, address _superchainXERC20Lockbox)
    {
        _xSuperchainERC20 = _deployXSuperchainERC20(_name, _symbol);
        _superchainXERC20Lockbox = _deployLockbox(_xSuperchainERC20, _xERC20);
    }

    /// @notice Deploys a new SuperchainXERC20Adapter
    /// @param _xERC20 The address of the XERC20 contract
    /// @return _superchainXERC20Adapter The address of the new SuperchainXERC20Adapter contract
    function deploySuperchainXERC20Adapter(address _xERC20) external returns (address _superchainXERC20Adapter) {
        _superchainXERC20Adapter = _deploySuperchainXERC20Adapter(_xERC20);
    }

    function _deployXSuperchainERC20(
        string memory _name,
        string memory _symbol
    )
        internal
        returns (address _xSuperchainERC20)
    {
        bytes32 _salt = keccak256(abi.encodePacked(_name, _symbol, msg.sender));
        bytes memory _creation = type(XSuperchainERC20).creationCode;
        bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_name, _symbol, address(this)));

        _xSuperchainERC20 = CREATE3.deploy(_salt, _bytecode, 0);

        // Set the limits to the max value to allow for unlimited minting and burning
        uint256 _limit = type(uint256).max >> 1;

        // Allow the SuperchainTokenBridge as default minter and burner
        XSuperchainERC20(_xSuperchainERC20).setLimits(Predeploys.SUPERCHAIN_TOKEN_BRIDGE, _limit, _limit);

        XSuperchainERC20(_xSuperchainERC20).transferOwnership(msg.sender);
    }

    function _deployLockbox(address _xSuperchainERC20, address _xerc20) internal returns (address payable _lockbox) {
        bytes32 _salt = keccak256(abi.encodePacked(_xSuperchainERC20, _xerc20, msg.sender));
        bytes memory _creation = type(SuperchainXERC20Lockbox).creationCode;
        bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_xSuperchainERC20, _xerc20));

        _lockbox = payable(CREATE3.deploy(_salt, _bytecode, 0));

        XSuperchainERC20(_xSuperchainERC20).setLockbox(address(_lockbox));
    }

    function _deploySuperchainXERC20Adapter(address _xSuperchainERC20)
        internal
        returns (address _superchainXERC20Adapter)
    {
        bytes32 _salt = keccak256(abi.encodePacked(_xSuperchainERC20, msg.sender));
        bytes memory _creation = type(SuperchainXERC20Adapter).creationCode;
        bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_xSuperchainERC20));

        _superchainXERC20Adapter = CREATE3.deploy(_salt, _bytecode, 0);
    }
}
