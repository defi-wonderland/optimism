// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { StaticConfig } from "src/libraries/StaticConfig.sol";

// Contracts
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { XERC20 } from "@xERC20/contracts/XERC20.sol";

// Interfaces
import { ICrosschainERC20 } from "interfaces/L2/CrosschainERC20/ICrosschainERC20.sol";
import { IERC7802Adapter } from "interfaces/L2/CrosschainERC20/IERC7802Adapter.sol";
import { ICrosschainERC20Factory } from "interfaces/L2/CrosschainERC20/ICrosschainERC20Factory.sol";
import { IXERC20Lockbox } from "@xERC20/interfaces/IXERC20Lockbox.sol";
import { IL1BlockInterop, ConfigType } from "interfaces/L2/IL1BlockInterop.sol";
import { IL2ToL2CrossDomainMessenger, Identifier } from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

/// @title CrosschainERC20_e2e_Base
/// @notice Base contract for end-to-end testing of the CrosschainERC20 paths.
/// @dev This contract provides common setup and helper functions for CrosschainERC20 e2e tests.
/// @dev Tests included in this contract should pass in every setup.
abstract contract CrosschainERC20_e2e_Base is CommonTest {
    // Contracts
    ICrosschainERC20Factory public crosschainERC20Factory;
    ICrosschainERC20 public crosschainERC20;
    IXERC20Lockbox public lockbox;
    IERC7802Adapter public ERC7802Adapter;

    // Defaults
    address public erc7281Bridge = makeAddr("erc7281Bridge");
    address public owner = makeAddr("owner");

    // Constants
    string public constant NAME = "Test";
    string public constant SYMBOL = "TST";
    uint256 public constant MINT_LIMIT = 10e25;
    uint256 public constant BURN_LIMIT = 10e25;
    uint256 public constant DESTINATION_CHAIN_ID = 130;
    bytes32 internal constant _SENT_MESSAGE_EVENT_SELECTOR =
        0x382409ac69001e11931a28435afef442cbfd20d9891907e8fa373ba7d351f320;

    // Structs
    struct Message {
        address from;
        uint256 amount;
        uint256 nonce;
    }

    /// @notice Test setup.
    function setUp() public virtual override {
        super.enableInterop();
        super.setUp();

        vm.prank(IL1BlockInterop(address(l1Block)).DEPOSITOR_ACCOUNT());
        IL1BlockInterop(address(l1Block)).setConfig(ConfigType.ADD_DEPENDENCY, StaticConfig.encodeAddDependency(DESTINATION_CHAIN_ID));

        crosschainERC20Factory =
            ICrosschainERC20Factory(vm.deployCode("src/L2/CrosschainERC20/CrosschainERC20Factory.sol"));
    }

    /// @notice Helper function to get the 7281 and 7802 bridges.
    /// @return bridges_ The bridges.
    function _get7281And7802Bridges() internal view returns (address[] memory bridges_) {
        bridges_ = new address[](2);
        bridges_[0] = erc7281Bridge;
        bridges_[1] = address(superchainTokenBridge);
    }

    /// @notice Helper function to get the bridge with limits.
    /// @param _minterLimit The minter limit.
    /// @param _burnerLimit The burner limit.
    /// @return bridges_ The bridges.
    /// @return minterLimits_ The minter limits.
    /// @return burnerLimits_ The burner limits.
    function _getBridgeWithLimits(
        address[] memory bridges,
        uint256 _minterLimit,
        uint256 _burnerLimit
    )
        internal
        view
        returns (address[] memory bridges_, uint256[] memory minterLimits_, uint256[] memory burnerLimits_)
    {
        // Create the arrays with length matching input bridges
        uint256 length = bridges.length;
        bridges_ = new address[](length);
        minterLimits_ = new uint256[](length);
        burnerLimits_ = new uint256[](length);

        // Set the values for each bridge
        for (uint256 i = 0; i < length; i++) {
            bridges_[i] = bridges[i];
            minterLimits_[i] = _minterLimit;
            burnerLimits_[i] = _burnerLimit;
        }
    }

    /// @notice Helper function to construct a message for ERC7802 minting
    /// @param _message The message struct containing from, amount and nonce
    /// @param _tokenAddress The address of the token to mint
    /// @return sentMessage The encoded message
    function _constructMessage(Message memory _message, address _tokenAddress) internal view returns (bytes memory) {
        address messageTarget = address(superchainTokenBridge);
        bytes memory message = abi.encodeCall(
            superchainTokenBridge.relayERC20, (_tokenAddress, _message.from, alice, _message.amount)
        );
        return abi.encodePacked(
            abi.encode(_SENT_MESSAGE_EVENT_SELECTOR, block.chainid, messageTarget, _message.nonce), // topics
            abi.encode(address(superchainTokenBridge), message) // data
        );
    }

    /// @notice Mints using ERC7281 interface.
    function test_mintERC7281_succeeds() public {
        // Get balance before mint
        uint256 balanceBefore = crosschainERC20.balanceOf(alice);

        // Mint tokens
        vm.prank(erc7281Bridge);
        crosschainERC20.mint(alice, MINT_LIMIT);

        // Get balance after mint
        uint256 balanceAfter = crosschainERC20.balanceOf(alice);

        // Check the balance has increased by the minted amount
        assertEq(balanceAfter - balanceBefore, MINT_LIMIT);
    }

    /// @notice Burns using ERC7281 interface.
    function test_burnERC7281_succeeds() public {
        // Approve the bridge to burn
        vm.prank(alice);
        crosschainERC20.approve(erc7281Bridge, BURN_LIMIT);

        // Burn tokens
        vm.prank(erc7281Bridge);
        crosschainERC20.burn(alice, BURN_LIMIT);

        // Check the balance has decreased by the burned amount
        uint256 balance = crosschainERC20.balanceOf(alice);
        assertEq(balance, 0);
    }

    /// @notice Helper function to get the target address for ERC7802 operations
    function _getERC7802Target() internal view returns (address) {
        return address(ERC7802Adapter) != address(0) 
            ? address(ERC7802Adapter) 
            : address(crosschainERC20);
    }

    /// @notice Mints using ERC7802 interface.
    function test_mintERC7802_succeeds(Identifier memory _id, Message memory _message) public virtual {
        _message.amount = MINT_LIMIT;

        // Ensure the id is valid
        _id.origin = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

        // Get balance before mint
        uint256 balanceBefore = crosschainERC20.balanceOf(alice);

        // Mint tokens using the message
        bytes memory sentMessage = _constructMessage(_message, _getERC7802Target());
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER).relayMessage(_id, sentMessage);

        // Get balance after mint
        uint256 balanceAfter = crosschainERC20.balanceOf(alice);

        // Check the balance has increased by the minted amount
        assertEq(balanceAfter - balanceBefore, MINT_LIMIT);
    }

    /// @notice Burns using ERC7802 interface.
    function test_burnERC7802_succeeds() public virtual {
        address target = _getERC7802Target();
        
        // Approve the bridge to burn
        vm.startPrank(alice);
        crosschainERC20.approve(target, BURN_LIMIT);

        // Burn tokens
        superchainTokenBridge.sendERC20(target, alice, BURN_LIMIT, DESTINATION_CHAIN_ID);
        vm.stopPrank();

        // Check the balance has decreased by the burned amount
        uint256 balance = crosschainERC20.balanceOf(alice);
        assertEq(balance, 0);
    }
}

/// @title CrosschainERC20_e2e_NonDeployedTokenPath_Test
/// @notice Contract for testing the CrosschainERC20 non-deployed token path.
contract CrosschainERC20_e2e_NonDeployedTokenPath_Test is CrosschainERC20_e2e_Base {
    /// @notice Test setup.
    function setUp() public override {
        super.setUp();

        // Get the bridges and limits
        (address[] memory _bridges, uint256[] memory _minterLimits, uint256[] memory _burnerLimits) =
            _getBridgeWithLimits(_get7281And7802Bridges(), MINT_LIMIT, BURN_LIMIT);

        // Deploy the crosschainERC20
        crosschainERC20 = ICrosschainERC20(
            crosschainERC20Factory.deployCrosschainERC20(NAME, SYMBOL, _minterLimits, _burnerLimits, _bridges, owner)
        );

        // Deal tokens to alice
        deal(address(crosschainERC20), alice, BURN_LIMIT);
    }
}

/// @title CrosschainERC20_e2e_DeployedTokenPath_Test
/// @notice Contract for testing the CrosschainERC20 deployed token path.
contract CrosschainERC20_e2e_DeployedTokenPath_Test is CrosschainERC20_e2e_Base {
    /// @notice Test setup.
    function setUp() public override {
        super.setUp();

        // Deploy the ERC20
        ERC20 erc20 = new ERC20("Token", "TKN");

        // Get the bridges and limits
        (address[] memory _bridges, uint256[] memory _minterLimits, uint256[] memory _burnerLimits) =
            _getBridgeWithLimits(_get7281And7802Bridges(), MINT_LIMIT, BURN_LIMIT);

        // Deploy the crosschainERC20 with lockbox
        (address _crosschainERC20, address _lockbox) = crosschainERC20Factory.deployCrosschainERC20WithLockbox(
            NAME, SYMBOL, _minterLimits, _burnerLimits, _bridges, address(erc20), owner
        );
        crosschainERC20 = ICrosschainERC20(_crosschainERC20);
        lockbox = IXERC20Lockbox(_lockbox);

        // Deal base tokens
        deal(address(erc20), alice, BURN_LIMIT);

        // Wrap the ERC20
        vm.startPrank(alice);
        erc20.approve(address(lockbox), BURN_LIMIT);
        lockbox.deposit(BURN_LIMIT);
        vm.stopPrank();
    }
}

contract CrosschainERC20_e2e_DeployedXERC20Path_Test is CrosschainERC20_e2e_Base {
    /// @notice Test setup.
    function setUp() public override {
        super.setUp();

        // Deploy the XERC20
        XERC20 xerc20 = new XERC20("Token", "TKN", bob);

        // Deploy adapter
        ERC7802Adapter = IERC7802Adapter(
            crosschainERC20Factory.deployERC7802Adapter(address(xerc20), address(superchainTokenBridge))
        );

        // Set limits for the bridges
        vm.startPrank(bob);
        xerc20.setLimits(erc7281Bridge, MINT_LIMIT, BURN_LIMIT);
        xerc20.setLimits(address(ERC7802Adapter), MINT_LIMIT, BURN_LIMIT);
        vm.stopPrank();

        // Set the crosschainERC20
        crosschainERC20 = ICrosschainERC20(address(xerc20));

        // Deal tokens
        deal(address(xerc20), alice, BURN_LIMIT);
    }
}
