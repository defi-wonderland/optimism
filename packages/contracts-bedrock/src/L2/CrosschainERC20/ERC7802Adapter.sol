// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Unauthorized } from "src/libraries/errors/CommonErrors.sol";

// Interfaces
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IERC7802, IERC165 } from "interfaces/L2/IERC7802.sol";
import { IXERC20 } from "@xERC20/interfaces/IXERC20.sol";

/// @title ERC7802Adapter
/// @notice Adapter for minting/burning xERC20 tokens using a bridge by implementing
/// the ERC7802 interface.
contract ERC7802Adapter is IERC7802, ISemver {
    IXERC20 public immutable XERC20;
    address public immutable BRIDGE;

    /// @notice Constructs the ERC7802Adapter.
    ///
    /// @param _xerc20 The xERC20 contract to adapt.
    /// @param _bridge The bridge address.
    constructor(IXERC20 _xerc20, address _bridge) {
        XERC20 = _xerc20;
        BRIDGE = _bridge;
    }

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-beta.1
    function version() external view virtual returns (string memory) {
        return "1.0.0-beta.1";
    }

    /// @notice Allows the bridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function crosschainMint(address _to, uint256 _amount) external {
        if (msg.sender != BRIDGE) revert Unauthorized();

        XERC20.mint(_to, _amount);

        emit CrosschainMint(_to, _amount, msg.sender);
    }

    /// @notice Allows the bridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function crosschainBurn(address _from, uint256 _amount) external {
        if (msg.sender != BRIDGE) revert Unauthorized();

        XERC20.burn(_from, _amount);

        emit CrosschainBurn(_from, _amount, msg.sender);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceId) public view virtual returns (bool) {
        return _interfaceId == type(IERC7802).interfaceId || _interfaceId == type(IERC165).interfaceId;
    }
}
