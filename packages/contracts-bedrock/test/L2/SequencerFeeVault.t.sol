// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";
import { Reverter } from "test/mocks/Callers.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";

// Contracts
import { ISequencerFeeVault } from "interfaces/L2/ISequencerFeeVault.sol";

// Interfaces
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { IFeeVault } from "interfaces/L2/IFeeVault.sol";

// Libraries
import { Hashing } from "src/libraries/Hashing.sol";
import { Types } from "src/libraries/Types.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { DeployUtils } from "scripts/libraries/DeployUtils.sol";

/// @title SequencerFeeVault_TestInit
/// @notice Reusable test initialization for `SequencerFeeVault` tests.
contract SequencerFeeVault_TestInit is CommonTest {
    address recipient;

    /// @dev Sets up the test suite.
    function setUp() public virtual override {
        super.setUp();
        recipient = deploy.cfg().sequencerFeeVaultRecipient();
    }
}

/// @title SequencerFeeVault_Constructor_Test
/// @notice Tests the `constructor` function of the `SequencerFeeVault` contract.
contract SequencerFeeVault_Constructor_Test is SequencerFeeVault_TestInit {
    /// @notice Tests that the l1 fee wallet is correct.
    function test_constructor_succeeds() external view {
        assertEq(sequencerFeeVault.l1FeeWallet(), recipient);
        assertEq(sequencerFeeVault.RECIPIENT(), recipient);
        assertEq(sequencerFeeVault.recipient(), recipient);
        assertEq(sequencerFeeVault.MIN_WITHDRAWAL_AMOUNT(), deploy.cfg().sequencerFeeVaultMinimumWithdrawalAmount());
        assertEq(sequencerFeeVault.minWithdrawalAmount(), deploy.cfg().sequencerFeeVaultMinimumWithdrawalAmount());
        assertEq(uint8(sequencerFeeVault.WITHDRAWAL_NETWORK()), uint8(Types.WithdrawalNetwork.L1));
        assertEq(uint8(sequencerFeeVault.withdrawalNetwork()), uint8(Types.WithdrawalNetwork.L1));
    }
}

/// @title SequencerFeeVault_Receive_Test
/// @notice Tests the `receive` function of the `SequencerFeeVault` contract.
contract SequencerFeeVault_Receive_Test is SequencerFeeVault_TestInit {
    /// @notice Tests that the fee vault is able to receive ETH.
    function test_receive_succeeds() external {
        uint256 balance = address(sequencerFeeVault).balance;

        vm.prank(alice);
        (bool success,) = address(sequencerFeeVault).call{ value: 100 }(hex"");

        assertEq(success, true);
        assertEq(address(sequencerFeeVault).balance, balance + 100);
    }
}

/// @title SequencerFeeVault_Withdraw_Test
/// @notice Tests the `withdraw` function of the `SequencerFeeVault` contract.
contract SequencerFeeVault_Withdraw_Test is SequencerFeeVault_TestInit {
    /// @notice Helper function to set up L2 withdrawal configuration.
    function _setupL2Withdrawal() internal {
        // Alter the deployment to use WithdrawalNetwork.L2
        vm.etch(
            EIP1967Helper.getImplementation(Predeploys.SEQUENCER_FEE_WALLET),
            address(
                DeployUtils.create1({
                    _name: "SequencerFeeVault",
                    _args: DeployUtils.encodeConstructor(
                        abi.encodeCall(
                            ISequencerFeeVault.__constructor__,
                            (
                                deploy.cfg().sequencerFeeVaultRecipient(),
                                deploy.cfg().sequencerFeeVaultMinimumWithdrawalAmount(),
                                Types.WithdrawalNetwork.L2
                            )
                        )
                    )
                })
            ).code
        );

        recipient = deploy.cfg().sequencerFeeVaultRecipient();
    }

    /// @notice Tests that `withdraw` reverts if the balance is less than the minimum withdrawal
    ///         amount.
    function test_withdraw_notEnough_reverts() external {
        assert(address(sequencerFeeVault).balance < sequencerFeeVault.MIN_WITHDRAWAL_AMOUNT());

        vm.expectRevert("FeeVault: withdrawal amount must be greater than minimum withdrawal amount");
        sequencerFeeVault.withdraw();
    }

    /// @notice Tests that `withdraw` successfully initiates a withdrawal to L1.
    function test_withdraw_toL1_succeeds() external {
        uint256 amount = sequencerFeeVault.MIN_WITHDRAWAL_AMOUNT() + 1;
        vm.deal(address(sequencerFeeVault), amount);

        // No ether has been withdrawn yet
        assertEq(sequencerFeeVault.totalProcessed(), 0);

        vm.expectEmit(address(Predeploys.SEQUENCER_FEE_WALLET));
        emit Withdrawal(address(sequencerFeeVault).balance, recipient, address(this));
        vm.expectEmit(address(Predeploys.SEQUENCER_FEE_WALLET));
        emit Withdrawal(address(sequencerFeeVault).balance, recipient, address(this), Types.WithdrawalNetwork.L1);

        // The entire vault's balance is withdrawn
        vm.expectCall(Predeploys.L2_TO_L1_MESSAGE_PASSER, address(sequencerFeeVault).balance, hex"");

        // The message is passed to the correct recipient
        vm.expectEmit(Predeploys.L2_TO_L1_MESSAGE_PASSER);
        emit MessagePassed(
            l2ToL1MessagePasser.messageNonce(),
            address(sequencerFeeVault),
            recipient,
            amount,
            400_000,
            hex"",
            Hashing.hashWithdrawal(
                Types.WithdrawalTransaction({
                    nonce: l2ToL1MessagePasser.messageNonce(),
                    sender: address(sequencerFeeVault),
                    target: recipient,
                    value: amount,
                    gasLimit: 400_000,
                    data: hex""
                })
            )
        );

        sequencerFeeVault.withdraw();

        // The withdrawal was successful
        assertEq(sequencerFeeVault.totalProcessed(), amount);
        assertEq(address(sequencerFeeVault).balance, 0);
        assertEq(Predeploys.L2_TO_L1_MESSAGE_PASSER.balance, amount);
    }

    /// @notice Tests that `withdraw` successfully initiates a withdrawal to L2.
    function test_withdraw_toL2_succeeds() external {
        _setupL2Withdrawal();

        uint256 amount = sequencerFeeVault.MIN_WITHDRAWAL_AMOUNT() + 1;
        vm.deal(address(sequencerFeeVault), amount);

        // No ether has been withdrawn yet
        assertEq(sequencerFeeVault.totalProcessed(), 0);

        vm.expectEmit(address(Predeploys.SEQUENCER_FEE_WALLET));
        emit Withdrawal(address(sequencerFeeVault).balance, sequencerFeeVault.RECIPIENT(), address(this));
        vm.expectEmit(address(Predeploys.SEQUENCER_FEE_WALLET));
        emit Withdrawal(
            address(sequencerFeeVault).balance, sequencerFeeVault.RECIPIENT(), address(this), Types.WithdrawalNetwork.L2
        );

        // The entire vault's balance is withdrawn
        vm.expectCall(recipient, address(sequencerFeeVault).balance, bytes(""));

        uint256 withdrawnAmount = sequencerFeeVault.withdraw();

        // The withdrawal was successful
        assertEq(withdrawnAmount, amount);
        assertEq(sequencerFeeVault.totalProcessed(), amount);
        assertEq(address(sequencerFeeVault).balance, 0);
        assertEq(recipient.balance, amount);
    }

    /// @notice Tests that `withdraw` fails if the Recipient reverts. This also serves to simulate
    ///         a situation where insufficient gas is provided to the RECIPIENT.
    function test_withdraw_toL2recipientReverts_fails() external {
        _setupL2Withdrawal();

        uint256 amount = sequencerFeeVault.MIN_WITHDRAWAL_AMOUNT();

        vm.deal(address(sequencerFeeVault), amount);
        // No ether has been withdrawn yet
        assertEq(sequencerFeeVault.totalProcessed(), 0);

        // Ensure the RECIPIENT reverts
        vm.etch(sequencerFeeVault.RECIPIENT(), type(Reverter).runtimeCode);

        // The entire vault's balance is withdrawn
        vm.expectCall(recipient, address(sequencerFeeVault).balance, bytes(""));
        vm.expectRevert("FeeVault: failed to send ETH to L2 fee recipient");
        sequencerFeeVault.withdraw();
        assertEq(sequencerFeeVault.totalProcessed(), 0);
    }
}

/// @title SequencerFeeVault_Setters_Test
/// @notice Tests the setter functions of the `SequencerFeeVault` contract.
contract SequencerFeeVault_Setters_Test is SequencerFeeVault_TestInit {
    /// @notice Tests that the owner can successfully set minimum withdrawal amount with fuzz testing.
    function testFuzz_setMinWithdrawalAmount_succeeds(uint256 _newAmount) external {
        address owner = IProxyAdmin(Predeploys.PROXY_ADMIN).owner();
        
        // Store initial values to verify boolean flag behavior
        uint256 initialAmount = sequencerFeeVault.minWithdrawalAmount();
        vm.assume(_newAmount != initialAmount);
        
        vm.prank(owner);
        IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).setMinWithdrawalAmount(_newAmount);

        // Verify the value was updated
        assertEq(sequencerFeeVault.minWithdrawalAmount(), _newAmount);
        
        // Should no longer return the immutable value
        assertNotEq(sequencerFeeVault.minWithdrawalAmount(), initialAmount);
    }

    /// @notice Tests that non-owner cannot set minimum withdrawal amount with fuzz testing.
    function testFuzz_setMinWithdrawalAmount_onlyOwner_reverts(address _caller, uint256 _newAmount) external {
        address owner = IProxyAdmin(Predeploys.PROXY_ADMIN).owner();
        vm.assume(_caller != owner);
        
        uint256 initialAmount = sequencerFeeVault.minWithdrawalAmount();

        vm.prank(_caller);
        vm.expectRevert();
        IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).setMinWithdrawalAmount(_newAmount);
        
        // Verify the value and boolean flag were NOT changed
        assertEq(sequencerFeeVault.minWithdrawalAmount(), initialAmount);
    }

    /// @notice Tests that the owner can successfully set recipient with fuzz testing.
    function testFuzz_setRecipient_succeeds(address _newRecipient) external {
        address owner = IProxyAdmin(Predeploys.PROXY_ADMIN).owner();
        
        // Store initial value
        address initialRecipient = sequencerFeeVault.recipient();

        vm.prank(owner);
        IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).setRecipient(_newRecipient);

        // Verify the value was updated
        assertEq(sequencerFeeVault.recipient(), _newRecipient);
        
        // Should no longer return the immutable value
        assertNotEq(sequencerFeeVault.recipient(), initialRecipient);
    }

    /// @notice Tests that non-owner cannot set recipient with fuzz testing.
    function testFuzz_setRecipient_onlyOwner_reverts(address _caller, address _newRecipient) external {
        address owner = IProxyAdmin(Predeploys.PROXY_ADMIN).owner();
        vm.assume(_caller != owner);
        
        address initialRecipient = sequencerFeeVault.recipient();

        vm.prank(_caller);
        vm.expectRevert();
        IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).setRecipient(_newRecipient);
        
        // Verify the value and boolean flag were NOT changed
        assertEq(sequencerFeeVault.recipient(), initialRecipient);
    }

    /// @notice Tests that the owner can successfully set withdrawal network with fuzz testing.
    function testFuzz_setWithdrawalNetwork_succeeds(uint8 _networkValue) external {
        // Bound to valid enum values (0 = L1, 1 = L2)
        _networkValue = uint8(bound(_networkValue, 0, 1));
        Types.WithdrawalNetwork newNetwork = Types.WithdrawalNetwork(_networkValue);
        
        address owner = IProxyAdmin(Predeploys.PROXY_ADMIN).owner();
        
        vm.prank(owner);
        IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).setWithdrawalNetwork(newNetwork);

        // Verify the value was updated
        assertEq(uint8(sequencerFeeVault.withdrawalNetwork()), uint8(newNetwork));
    }

    /// @notice Tests that non-owner cannot set withdrawal network with fuzz testing.
    function testFuzz_setWithdrawalNetwork_onlyOwner_reverts(address _caller, uint8 _networkValue) external {
        address owner = IProxyAdmin(Predeploys.PROXY_ADMIN).owner();
        vm.assume(_caller != owner);
        
        // Bound to valid enum values
        _networkValue = uint8(bound(_networkValue, 0, 1));
        Types.WithdrawalNetwork newNetwork = Types.WithdrawalNetwork(_networkValue);
        
        Types.WithdrawalNetwork initialNetwork = sequencerFeeVault.withdrawalNetwork();

        vm.prank(_caller);
        vm.expectRevert();
        IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).setWithdrawalNetwork(newNetwork);
        
        // Verify the value and boolean flag were NOT changed
        assertEq(uint8(sequencerFeeVault.withdrawalNetwork()), uint8(initialNetwork));
    }
}

/// @title SequencerFeeVault_Getters_Test
/// @notice Tests the getter functions of the `SequencerFeeVault` contract.
contract SequencerFeeVault_Getters_Test is SequencerFeeVault_TestInit {
    /// @notice Tests that minWithdrawalAmount returns immutable by default, then storage after being set.
    function test_minWithdrawalAmount_returnsImmutableThenStorage_succeeds() external {
        address owner = IProxyAdmin(Predeploys.PROXY_ADMIN).owner();
        
        // Initially should return the immutable value
        uint256 immutableValue = sequencerFeeVault.MIN_WITHDRAWAL_AMOUNT();
        assertEq(sequencerFeeVault.minWithdrawalAmount(), immutableValue);
        
        // Set a different value via owner
        uint256 newValue = immutableValue + 1 ether;
        vm.prank(owner);
        IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).setMinWithdrawalAmount(newValue);
        
        // Now should return the storage value, not the immutable
        assertEq(sequencerFeeVault.minWithdrawalAmount(), newValue);
        assertNotEq(sequencerFeeVault.minWithdrawalAmount(), immutableValue);
        assertEq(sequencerFeeVault.MIN_WITHDRAWAL_AMOUNT(), immutableValue); // immutable unchanged
    }

    /// @notice Tests that recipient returns immutable by default, then storage after being set.
    function test_recipient_returnsImmutableThenStorage_succeeds() external {
        address owner = IProxyAdmin(Predeploys.PROXY_ADMIN).owner();
        
        // Initially should return the immutable value
        address immutableValue = sequencerFeeVault.RECIPIENT();
        assertEq(sequencerFeeVault.recipient(), immutableValue);
        
        // Set a different value via owner
        address newValue = address(0x123);
        vm.prank(owner);
        IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).setRecipient(newValue);
        
        // Now should return the storage value, not the immutable
        assertEq(sequencerFeeVault.recipient(), newValue);
        assertNotEq(sequencerFeeVault.recipient(), immutableValue);
        assertEq(sequencerFeeVault.RECIPIENT(), immutableValue); // immutable unchanged
    }

    /// @notice Tests that withdrawalNetwork returns immutable by default, then storage after being set.
    function test_withdrawalNetwork_returnsImmutableThenStorage_succeeds() external {
        address owner = IProxyAdmin(Predeploys.PROXY_ADMIN).owner();
        
        // Initially should return the immutable value
        Types.WithdrawalNetwork immutableValue = sequencerFeeVault.WITHDRAWAL_NETWORK();
        assertEq(uint8(sequencerFeeVault.withdrawalNetwork()), uint8(immutableValue));
        
        // Set a different value via owner (toggle between L1 and L2)
        Types.WithdrawalNetwork newValue = immutableValue == Types.WithdrawalNetwork.L1 
            ? Types.WithdrawalNetwork.L2 
            : Types.WithdrawalNetwork.L1;
        vm.prank(owner);
        IFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET)).setWithdrawalNetwork(newValue);
        
        // Now should return the storage value, not the immutable
        assertEq(uint8(sequencerFeeVault.withdrawalNetwork()), uint8(newValue));
        assertNotEq(uint8(sequencerFeeVault.withdrawalNetwork()), uint8(immutableValue));
        assertEq(uint8(sequencerFeeVault.WITHDRAWAL_NETWORK()), uint8(immutableValue)); // immutable unchanged
    }
}
