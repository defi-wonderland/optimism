// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Contracts
import { XERC20Lockbox } from "@xERC20/contracts/XERC20Lockbox.sol";
import { CrosschainERC20 } from "src/L2/CrosschainERC20/CrosschainERC20.sol";
import { ERC7802Adapter } from "src/L2/CrosschainERC20/ERC7802Adapter.sol";

// Libraries
import { CREATE3 } from "isolmate/utils/CREATE3.sol";

contract CrosschainERC20Factory {
    /// @notice Thrown when the length of the minter limits, burner limits, or bridges arrays are not equal
    error InvalidLength();

    /// @notice Deploys a new CrosschainERC20 contract and returns the address
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @return _crosschainERC20 The address of the new CrosschainERC20 contract
    function deployCrosschainERC20(
        string memory _name,
        string memory _symbol,
        uint256[] memory _minterLimits,
        uint256[] memory _burnerLimits,
        address[] memory _bridges
    )
        external
        returns (address _crosschainERC20)
    {
        _crosschainERC20 = _deployCrosschainERC20(_name, _symbol, _minterLimits, _burnerLimits, _bridges);
    }

    /// @notice Deploys a new CrosschainERC20Lockbox and CrosschainERC20
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @param _ERC20 The address of the ERC20 contract
    /// @return _crosschainERC20 The address of the new CrosschainERC20 contract
    /// @return _crosschainERC20Lockbox The address of the new crosschainERC20Lockbox contract
    function deployCrosschainERC20WithLockbox(
        string memory _name,
        string memory _symbol,
        uint256[] memory _minterLimits,
        uint256[] memory _burnerLimits,
        address[] memory _bridges,
        address _ERC20
    )
        external
        returns (address _crosschainERC20, address _crosschainERC20Lockbox)
    {
        _crosschainERC20 = _deployCrosschainERC20(_name, _symbol, _minterLimits, _burnerLimits, _bridges);
        _crosschainERC20Lockbox = _deployLockbox(_crosschainERC20, _ERC20);
    }

    /// @notice Deploys a new ERC7802Adapter
    /// @param _crosschainERC20 The address of the CrosschainERC20 contract
    /// @param _bridge The address of the bridge
    /// @return _erc7802Adapter The address of the new ERC7802Adapter contract
    function deployERC7802Adapter(address _crosschainERC20, address _bridge) external returns (address _erc7802Adapter) {
        _erc7802Adapter = _deployERC7802Adapter(_crosschainERC20, _bridge);
    }

    function _deployCrosschainERC20(
        string memory _name,
        string memory _symbol,
        uint256[] memory _minterLimits,
        uint256[] memory _burnerLimits,
        address[] memory _bridges
    )
        internal
        returns (address _crosschainERC20)
    {
        uint256 _bridgesLength = _bridges.length;
        if (_minterLimits.length != _bridgesLength || _burnerLimits.length != _bridgesLength) {
            revert InvalidLength();
        }
        bytes32 _salt = keccak256(abi.encodePacked(_name, _symbol, msg.sender));
        bytes memory _creation = type(CrosschainERC20).creationCode;
        bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_name, _symbol, address(this)));

        _crosschainERC20 = CREATE3.deploy(_salt, _bytecode, 0);

        for (uint256 _i; _i < _bridgesLength; ++_i) {
            CrosschainERC20(_crosschainERC20).setLimits(_bridges[_i], _minterLimits[_i], _burnerLimits[_i]);
        }

        CrosschainERC20(_crosschainERC20).transferOwnership(msg.sender);
    }

    function _deployLockbox(
        address _crosschainERC20,
        address _baseToken
    )
        internal
        returns (address payable _lockbox)
    {
        bytes32 _salt = keccak256(abi.encodePacked(_crosschainERC20, _baseToken, msg.sender));
        bytes memory _creation = type(XERC20Lockbox).creationCode;
        bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_crosschainERC20, _baseToken, false));

        _lockbox = payable(CREATE3.deploy(_salt, _bytecode, 0));

        CrosschainERC20(_crosschainERC20).setLockbox(address(_lockbox));
    }

    function _deployERC7802Adapter(address _crosschainERC20, address _bridge) internal returns (address _erc7802Adapter) {
        bytes32 _salt = keccak256(abi.encodePacked(_crosschainERC20, _bridge, msg.sender));
        bytes memory _creation = type(ERC7802Adapter).creationCode;
        bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_crosschainERC20, _bridge));

        _erc7802Adapter = CREATE3.deploy(_salt, _bytecode, 0);
    }
}
