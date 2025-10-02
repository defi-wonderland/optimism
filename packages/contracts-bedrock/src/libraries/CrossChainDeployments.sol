// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";

/// @title CrossChainDeployments
/// @notice Library for cross-chain deployment utilities, including address precalculation
///         and cross-chain factory deployment.
library CrossChainDeployments {
    /// @notice Precalculates the address of a contract deployed with CREATE opcode.
    /// @param _deployer The address of the deployer contract.
    /// @param _nonce The nonce of the deployer at deployment time.
    /// @return The precalculated address.
    function precalculateCreateAddress(address _deployer, uint256 _nonce) internal pure returns (address) {
        if (_nonce == 0x00) {
            return address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _deployer, bytes1(0x80)))))
            );
        }
        if (_nonce <= 0x7f) {
            return address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _deployer, uint8(_nonce)))))
            );
        }
        if (_nonce <= 0xff) {
            return address(
                uint160(
                    uint256(
                        keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), _deployer, bytes1(0x81), uint8(_nonce)))
                    )
                )
            );
        }
        if (_nonce <= 0xffff) {
            return address(
                uint160(
                    uint256(
                        keccak256(abi.encodePacked(bytes1(0xd8), bytes1(0x94), _deployer, bytes1(0x82), uint16(_nonce)))
                    )
                )
            );
        }
        if (_nonce <= 0xffffff) {
            return address(
                uint160(
                    uint256(
                        keccak256(abi.encodePacked(bytes1(0xd9), bytes1(0x94), _deployer, bytes1(0x83), uint24(_nonce)))
                    )
                )
            );
        }
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), _deployer, bytes1(0x84), uint32(_nonce)))
                )
            )
        );
    }

    /// @notice Precalculates the address of a contract deployed with CREATE2 opcode.
    /// @param _deployer The address of the deployer contract.
    /// @param _salt The salt used for CREATE2.
    /// @param _initCodeHash The hash of the initialization code.
    /// @return The precalculated address.
    function precalculateCreate2Address(
        address _deployer,
        bytes32 _salt,
        bytes32 _initCodeHash
    )
        internal
        pure
        returns (address)
    {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), _deployer, _salt, _initCodeHash)))));
    }

    /// @notice Deploys a factory contract on L2 through cross-domain messaging.
    /// @param _factoryInitCode The complete initialization code for the L2 factory.
    /// @param _salt The salt for CREATE2 deployment.
    /// @param _l1Messenger The L1 cross-domain messenger.
    /// @param _l2Create2Deployer The L2 CREATE2 deployer address.
    /// @param _minGasLimit The minimum gas limit for the cross-domain message.
    /// @return The precalculated address of the L2 factory.
    function deployL2Factory(
        bytes memory _factoryInitCode,
        bytes32 _salt,
        address _l1Messenger,
        address _l2Create2Deployer,
        uint32 _minGasLimit
    )
        internal
        returns (address)
    {
        // Get the init code hash for the L2 factory
        bytes32 _initCodeHash = keccak256(_factoryInitCode);

        // Precalculate the L2 factory address
        address _l2Factory = precalculateCreate2Address(_l2Create2Deployer, _salt, _initCodeHash);

        // Send the deployment message to L2
        ICrossDomainMessenger(_l1Messenger).sendMessage({
            _target: _l2Create2Deployer,
            _message: abi.encodeWithSignature(
                "deploy(uint256,bytes32,bytes)",
                0, // value
                _salt,
                _factoryInitCode
            ),
            _minGasLimit: _minGasLimit
        });

        return _l2Factory;
    }
}
