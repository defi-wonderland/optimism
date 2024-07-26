// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import { Test, StdUtils, Vm } from "forge-std/Test.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";
import { OptimismSuperchainERC20 } from "src/L2/OptimismSuperchainERC20.sol";
import { IL2ToL2CrossDomainMessenger } from "src/L2/IL2ToL2CrossDomainMessenger.sol";

/// @title OptimismSuperchainERC20_User
/// @notice Actor contract that interacts with the OptimismSuperchainERC20 contract.
contract OptimismSuperchainERC20_User is StdUtils {
    /// @notice Cross domain message data.
    struct MessageData {
        bytes32 id;
        uint256 amount;
    }

    /// @notice Flag to indicate if the test has failed.
    bool public failed = false;

    /// @notice The Vm contract.
    Vm internal vm;

    /// @notice The OptimismSuperchainERC20 contract.
    OptimismSuperchainERC20 internal superchainERC20;

    /// @notice Mapping of sent messages.
    mapping(bytes32 => bool) internal sent;

    /// @notice Array of unrelayed messages.
    MessageData[] internal unrelayed;

    /// @param _vm The Vm contract.
    /// @param _superchainERC20 The OptimismSuperchainERC20 contract.
    /// @param _balance The initial balance of the contract.
    constructor(Vm _vm, OptimismSuperchainERC20 _superchainERC20, uint256 _balance) {
        vm = _vm;
        superchainERC20 = _superchainERC20;

        // Mint balance to this actor.
        vm.prank(Predeploys.L2_STANDARD_BRIDGE);
        superchainERC20.mint(address(this), _balance);
    }

    /// @notice Send ERC20 tokens to another chain.
    /// @param _amount The amount of ERC20 tokens to send.
    /// @param _chainId The chain ID to send the tokens to.
    /// @param _messageId The message ID.
    function sendERC20(uint256 _amount, uint256 _chainId, bytes32 _messageId) public {
        // Make sure we aren't reusing a message ID.
        if (sent[_messageId]) {
            return;
        }

        // Bound send amount to our ERC20 balance.
        _amount = bound(_amount, 0, superchainERC20.balanceOf(address(this)));

        // Send the amount.
        try superchainERC20.sendERC20(address(this), _amount, _chainId) {
            // Success.
        } catch {
            failed = true;
        }

        // Mark message as sent.
        sent[_messageId] = true;
        unrelayed.push(MessageData({ id: _messageId, amount: _amount }));
    }

    /// @notice Relay a message from another chain.
    function relayMessage() public {
        // Make sure there are unrelayed messages.
        if (unrelayed.length == 0) {
            return;
        }

        // Grab the latest unrelayed message.
        MessageData memory message = unrelayed[unrelayed.length - 1];

        // Simulate the cross-domain message.
        // Make sure the cross-domain message sender is set to this contract.
        vm.mockCall(
            Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
            abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
            abi.encode(address(superchainERC20))
        );

        // Prank the relayERC20 function.
        // Balance will just go back to our own account.
        vm.prank(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        try superchainERC20.relayERC20(address(this), message.amount) {
            // Success.
        } catch {
            failed = true;
        }

        // Remove the message from the unrelayed list.
        unrelayed.pop();
    }
}

/// @title OptimismSuperchainERC20_SendSucceeds_Invariant
/// @notice Invariant test that checks that sending OptimismSuperchainERC20 always succeeds if the actor has a
///         sufficient balance to do so and that the actor's balance does not increase out of nowhere.
contract OptimismSuperchainERC20_SendSucceeds_Invariant is Test {
    /// @notice Starting balance of the contract.
    uint256 internal constant STARTING_BALANCE = type(uint256).max;

    /// @notice The OptimismSuperchainERC20_User actor.
    OptimismSuperchainERC20_User internal actor;

    /// @notice The OptimismSuperchainERC20 contract.
    OptimismSuperchainERC20 internal optimismSuperchainERC20;

    /// @notice Test setup.
    function setUp() public {
        // Deploy the L2ToL2CrossDomainMessenger contract.
        address _impl = _setImplementationCode(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        _setProxyCode(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, _impl);

        // Create a new OptimismSuperchainERC20
        optimismSuperchainERC20 = new OptimismSuperchainERC20(address(0x123), "Supertoken", "SUP", 18);

        // Create a new OptimismSuperchainERC20_User actor.
        actor = new OptimismSuperchainERC20_User(vm, optimismSuperchainERC20, STARTING_BALANCE);

        // Set the target contract.
        targetContract(address(actor));

        // Set the target selectors.
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = actor.sendERC20.selector;
        selectors[1] = actor.relayMessage.selector;
        FuzzSelector memory selector = FuzzSelector({ addr: address(actor), selectors: selectors });
        targetSelector(selector);
    }

    /// @notice Sets the bytecode in the implementation address.
    function _setImplementationCode(address _addr) internal returns (address) {
        string memory cname = Predeploys.getName(_addr);
        address impl = Predeploys.predeployToCodeNamespace(_addr);
        vm.etch(impl, vm.getDeployedCode(string.concat(cname, ".sol:", cname)));
        return impl;
    }

    /// @notice Sets the bytecode in the proxy address.
    function _setProxyCode(address _addr, address _impl) internal {
        bytes memory code = vm.getDeployedCode("Proxy.sol:Proxy");
        vm.etch(_addr, code);
        EIP1967Helper.setAdmin(_addr, Predeploys.PROXY_ADMIN);
        EIP1967Helper.setImplementation(_addr, _impl);
    }

    /// @notice Invariant that checks that sending OptimismSuperchainERC20 always succeeds.
    /// @custom:invariant Calls to sendERC20 should always succeed as long as the actor has enough balance.
    ///                   Actor's balance should also not increase out of nowhere.
    function invariant_sendERC20_succeeds() public view {
        // Assert that the actor has not failed to send OptimismSuperchainERC20.
        assertEq(actor.failed(), false);

        // Assert that the actor's balance has not somehow increased.
        assertLe(optimismSuperchainERC20.balanceOf(address(actor)), STARTING_BALANCE);
        assertLe(optimismSuperchainERC20.totalSupply(), STARTING_BALANCE);
    }
}
