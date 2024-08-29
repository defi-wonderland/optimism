// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IOptimismSuperchainERC20Extension } from "src/L2/IOptimismSuperchainERC20.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { SuperchainERC20 } from "src/L2/SuperchainERC20.sol";

/// @notice Thrown when attempting to mint or burn tokens and the function caller is not the StandardBridge.
error OnlyBridge();

/// @notice Thrown when attempting to mint or burn tokens and the account is the zero address.
error ZeroAddress();

/// @custom:proxied
/// @title OptimismSuperchainERC20
/// @notice OptimismSuperchainERC20 is a standard extension of the base ERC20 token contract that unifies ERC20 token
///         bridging to make it fungible across the Superchain. This construction allows the L2StandardBridge to burn
///         and mint tokens. This makes it possible to convert a valid OptimismMintableERC20 token to a SuperchainERC20
///         token, turning it fungible and interoperable across the superchain. Likewise, it also enables the inverse
///         conversion path.
///         Moreover, it builds on top of the L2ToL2CrossDomainMessenger for both replay protection and domain binding.
contract OptimismSuperchainERC20 is IOptimismSuperchainERC20Extension, SuperchainERC20 {
    /// @notice Address of the StandardBridge Predeploy.
    address internal constant BRIDGE = Predeploys.L2_STANDARD_BRIDGE;

    /// @notice Storage slot that the OptimismSuperchainERC20Metadata struct is stored at.
    /// keccak256(abi.encode(uint256(keccak256("optimismSuperchainERC20.metadata")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant OPTIMISM_SUPERCHAIN_ERC20_METADATA_SLOT =
        0x07f04e84143df95a6373fcf376312ae41da81a193a3089073a54f47a74d8fb00;

    /// @notice Storage struct for the OptimismSuperchainERC20 metadata.
    /// @custom:storage-location erc7201:optimismSuperchainERC20.metadata
    struct OptimismSuperchainERC20Metadata {
        /// @notice Address of the corresponding version of this token on the remote chain.
        address remoteToken;
    }

    /// @notice Returns the storage for the OptimismSuperchainERC20Metadata.
    function _getStorage() private pure returns (OptimismSuperchainERC20Metadata storage _storage) {
        assembly {
            _storage.slot := OPTIMISM_SUPERCHAIN_ERC20_METADATA_SLOT
        }
    }

    /// @notice A modifier that only allows the bridge to call
    modifier onlyBridge() {
        if (msg.sender != BRIDGE) revert OnlyBridge();
        _;
    }

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-beta.1
    function version() public pure override returns (string memory) {
        return "1.0.0-beta.1";
    }

    /// @notice Constructs the OptimismSuperchainERC20 contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    /// @param _remoteToken    Address of the corresponding remote token.
    /// @param _name           ERC20 name.
    /// @param _symbol         ERC20 symbol.
    /// @param _decimals       ERC20 decimals.
    function initialize(
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        external
        initializer
    {
        super.initialize(_name, _symbol, _decimals);

        OptimismSuperchainERC20Metadata storage _storage = _getStorage();
        _storage.remoteToken = _remoteToken;
    }

    /// @notice Allows the L2StandardBridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function mint(address _to, uint256 _amount) external virtual onlyBridge {
        if (_to == address(0)) revert ZeroAddress();

        _mint(_to, _amount);

        emit Mint(_to, _amount);
    }

    /// @notice Allows the L2StandardBridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function burn(address _from, uint256 _amount) external virtual onlyBridge {
        if (_from == address(0)) revert ZeroAddress();

        _burn(_from, _amount);

        emit Burn(_from, _amount);
    }

    /// @notice Returns the address of the corresponding version of this token on the remote chain.
    function remoteToken() public view override returns (address) {
        return _getStorage().remoteToken;
    }

    /// @notice ERC165 interface check function.
    /// @param _interfaceId Interface ID to check.
    /// @return Whether or not the interface is supported by this contract.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return
            _interfaceId == type(IOptimismSuperchainERC20Extension).interfaceId || super.supportsInterface(_interfaceId);
    }
}
