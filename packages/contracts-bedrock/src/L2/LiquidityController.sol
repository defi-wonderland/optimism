// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { SafeSend } from "src/universal/SafeSend.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Interfaces
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";

/// @custom:proxied true
/// @custom:predeploy 0x420000000000000000000000000000000000002A
/// @title LiquidityController
/// @notice The LiquidityController contract is responsible for controlling the liquidity of the native asset on the L2
///         chain. Uses the MintBurn precompile at address(0x42) for native asset minting/burning.
contract LiquidityController is ISemver, Initializable {
    /// @notice Address of the MintBurn precompile
    address public constant MINT_BURN_PRECOMPILE = address(0x0101);

    /// @notice Emitted when an address is authorized to mint/burn liquidity
    /// @param minter The address that was authorized
    event MinterAuthorized(address indexed minter);

    /// @notice Emitted when an address is deauthorized to mint/burn liquidity
    /// @param minter The address that was deauthorized
    event MinterDeauthorized(address indexed minter);

    /// @notice Emitted when liquidity is minted
    /// @param minter The address that minted the liquidity
    /// @param to The address that received the minted liquidity
    /// @param amount The amount of liquidity that was minted
    event LiquidityMinted(address indexed minter, address indexed to, uint256 amount);

    /// @notice Emitted when liquidity is burned
    /// @param minter The address that burned the liquidity
    /// @param amount The amount of liquidity that was burned
    event LiquidityBurned(address indexed minter, uint256 amount);

    /// @notice Error for when an address is unauthorized to perform liquidity control operations
    error LiquidityController_Unauthorized();

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    bool public authorized;

    /// @notice Mapping of addresses authorized to control liquidity operations
    mapping(address => bool) public minters;

    /// @notice The name of the native asset
    string public gasPayingTokenName;

    /// @notice The symbol of the native asset
    string public gasPayingTokenSymbol;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _gasPayingTokenName The name of the native asset
    /// @param _gasPayingTokenSymbol The symbol of the native asset
    function initialize(string memory _gasPayingTokenName, string memory _gasPayingTokenSymbol) external initializer {
        gasPayingTokenName = _gasPayingTokenName;
        gasPayingTokenSymbol = _gasPayingTokenSymbol;
    }

    /// @notice Authorizes an address to perform liquidity control operations
    /// @param _minter The address to authorize as a minter
    function authorizeMinter(address _minter) external {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) revert LiquidityController_Unauthorized();
        minters[_minter] = true;
        emit MinterAuthorized(_minter);
    }

    /// @notice Deauthorizes an address from performing liquidity control operations
    /// @param _minter The address to deauthorize as a minter
    function deauthorizeMinter(address _minter) external {
        if (msg.sender != IProxyAdmin(Predeploys.PROXY_ADMIN).owner()) revert LiquidityController_Unauthorized();
        delete minters[_minter];
        emit MinterDeauthorized(_minter);
    }

    /// @notice Mints native asset liquidity and sends it to a specified address
    /// @param _to The address to receive the minted native asset
    /// @param _amount The amount of native asset to mint and send
    function mint(address _to, uint256 _amount) external {
        if (!minters[msg.sender]) revert LiquidityController_Unauthorized();

        // Set transient storage to authorize this contract (address 0x2a) to call the precompile
        assembly {
            tstore(0, 1)
        }

        // Call the MintBurn precompile to mint tokens
        // ABI: mint(address,uint256)
        (bool success,) = MINT_BURN_PRECOMPILE.call(abi.encodeWithSignature("mint(address,uint256)", _to, _amount));
        require(success, "MintBurn precompile call failed");

        emit LiquidityMinted(msg.sender, _to, _amount);
    }

    /// @notice Burns native asset liquidity by sending ETH to the contract
    function burn() external payable {
        if (!minters[msg.sender]) revert LiquidityController_Unauthorized();

        // Set transient storage to authorize this contract (address 0x2a) to call the precompile
        assembly {
            tstore(0, 1)
        }

        // Call the MintBurn precompile to burn tokens
        // ABI: burn(address,uint256)
        (bool success,) =
            MINT_BURN_PRECOMPILE.call(abi.encodeWithSignature("burn(address,uint256)", address(this), msg.value));
        require(success, "MintBurn precompile call failed");

        emit LiquidityBurned(msg.sender, msg.value);
    }
}
