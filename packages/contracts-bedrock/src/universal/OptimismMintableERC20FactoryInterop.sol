// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { OptimismMintableERC20Factory, OptimismMintableERC20 } from "src/universal/OptimismMintableERC20Factory.sol";
import { IOptimismERC20Factory } from "src/L2/IOptimismERC20Factory.sol";
import { CREATE3 } from "@rari-capital/solmate/src/utils/CREATE3.sol";

/// @custom:proxied
/// @custom:predeployed 0x4200000000000000000000000000000000000012
/// @title OptimismMintableERC20FactoryInterop
/// @notice OptimismMintableERC20FactoryInterop is a factory contract that generates OptimismMintableERC20
///         contracts on the network it's deployed to, using CREATE3. Simplifies the deployment process for users
///         who may be less familiar with deploying smart contracts. Designed to be backwards
///         compatible with the older OptimismMintableERC20Factory contract.
contract OptimismMintableERC20FactoryInterop is OptimismMintableERC20Factory, IOptimismERC20Factory {
    /// @notice Storage slot that the OptimismMintableERC20FactoryInteropStorage struct is stored at.
    /// keccak256(abi.encode(uint256(keccak256("optimismMintableERC20FactoryInterop.storage")) - 1)) &
    /// ~bytes32(uint256(0xff));
    bytes32 internal constant OPTIMISM_MINTABLE_ERC20_FACTORY_INTEROP_SLOT =
        0xb6fdf24dfda35722597f70f86628ef4ce6db853b20879bdd2d61f0f5d169b100;

    /// @notice Storage struct for the OptimismMintableERC20FactoryInterop storage.
    /// @custom:storage-location erc7201:optimismMintableERC20FactoryInterop.storage
    struct OptimismMintableERC20FactoryInteropStorage {
        /// @notice Mapping of local token address to remote token address.
        mapping(address => address) deployments;
    }

    /// @notice Returns the storage for the OptimismMintableERC20FactoryInteropStorage.
    function _getStorage() private pure returns (OptimismMintableERC20FactoryInteropStorage storage _storage) {
        assembly {
            _storage.slot := OPTIMISM_MINTABLE_ERC20_FACTORY_INTEROP_SLOT
        }
    }

    /// @notice Creates an instance of the OptimismMintableERC20 contract, with specified decimals using CREATE3.
    /// @param _remoteToken Address of the token on the remote chain.
    /// @param _name        ERC20 name.
    /// @param _symbol      ERC20 symbol.
    /// @param _decimals    ERC20 decimals.
    /// @return _localToken Address of the newly created token.
    function createWithCreate3(
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        public
        override
        returns (address _localToken)
    {
        require(_remoteToken != address(0), "OptimismMintableERC20Factory: must provide remote token address");

        bytes memory creationCode = abi.encodePacked(
            type(OptimismMintableERC20).creationCode, abi.encode(bridge, _remoteToken, _name, _symbol, _decimals)
        );

        bytes32 salt = keccak256(abi.encode(_remoteToken, _name, _symbol, _decimals));

        _localToken = CREATE3.deploy({ salt: salt, creationCode: creationCode, value: 0 });

        _getStorage().deployments[_localToken] = _remoteToken;

        // Emit the old event too for legacy support.
        emit StandardL2TokenCreated(_remoteToken, _localToken);

        // Emit the updated event. The arguments here differ from the legacy event, but
        // are consistent with the ordering used in StandardBridge events.
        emit OptimismMintableERC20Created(_localToken, _remoteToken, msg.sender);
    }

    /// @notice Returns the address of the token on the remote chain if the deployment exists,
    ///         else returns `address(0)`.
    /// @param _localToken Address of the token on the local chain.
    /// @return _remoteToken Address of the token on the remote chain.
    function deployments(address _localToken) external view override returns (address _remoteToken) {
        return _getStorage().deployments[_localToken];
    }
}
