// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;


// Testing
import { CommonTest } from "test/setup/CommonTest.sol"; 

// Contracts
import { FeeVaultInitializer } from "src/L2/FeeVaultInitializer.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";




contract FeeVaultInitializer_Test is CommonTest {
    FeeVaultInitializer feeVaultInitializer;

    event FeeVaultDeployed(
        string indexed vaultType,
        address indexed newImplementation,
        address recipient,
        Types.WithdrawalNetwork network,
        uint256 minWithdrawalAmount
    );

    function setUp() public override {
        super.setUp();
    }

    function test_constructor_succeeds() public {
        // Store original fee vault configurations before deploying the initializer
        address baseRecipient = baseFeeVault.RECIPIENT();
        uint256 baseMinWithdrawal = baseFeeVault.MIN_WITHDRAWAL_AMOUNT();
        Types.WithdrawalNetwork baseNetwork = baseFeeVault.WITHDRAWAL_NETWORK();
        
        address sequencerRecipient = sequencerFeeVault.RECIPIENT();
        uint256 sequencerMinWithdrawal = sequencerFeeVault.MIN_WITHDRAWAL_AMOUNT();
        Types.WithdrawalNetwork sequencerNetwork = sequencerFeeVault.WITHDRAWAL_NETWORK();
        
        address l1Recipient = l1FeeVault.RECIPIENT();
        uint256 l1MinWithdrawal = l1FeeVault.MIN_WITHDRAWAL_AMOUNT();
        Types.WithdrawalNetwork l1Network = l1FeeVault.WITHDRAWAL_NETWORK();
        
        address operatorRecipient = operatorFeeVault.RECIPIENT();
        uint256 operatorMinWithdrawal = operatorFeeVault.MIN_WITHDRAWAL_AMOUNT();
        Types.WithdrawalNetwork operatorNetwork = operatorFeeVault.WITHDRAWAL_NETWORK();
        
        // Expect the FeeVaultDeployed events for each vault type (ignoring implementation addresses)
        vm.expectEmit(true, false, false, true);
        emit FeeVaultDeployed("BaseFeeVault", address(0), baseRecipient, baseNetwork, baseMinWithdrawal);
        
        vm.expectEmit(true, false, false, true);
        emit FeeVaultDeployed("SequencerFeeVault", address(0), sequencerRecipient, sequencerNetwork, sequencerMinWithdrawal);
        
        vm.expectEmit(true, false, false, true);
        emit FeeVaultDeployed("L1FeeVault", address(0), l1Recipient, l1Network, l1MinWithdrawal);
        
        vm.expectEmit(true, false, false, true);
        emit FeeVaultDeployed("OperatorFeeVault", address(0), operatorRecipient, operatorNetwork, operatorMinWithdrawal);
        
        // Deploy the FeeVaultInitializer
        feeVaultInitializer = new FeeVaultInitializer();
        
        // The constructor should have completed successfully
        // Version should be accessible to verify deployment
        assertEq(feeVaultInitializer.version(), "1.0.0");

        // Verify the fee vaults were deployed with the correct configuration
        assertEq(baseFeeVault.RECIPIENT(), baseRecipient);
        assertEq(baseFeeVault.MIN_WITHDRAWAL_AMOUNT(), baseMinWithdrawal);
        assertEq(uint8(baseFeeVault.WITHDRAWAL_NETWORK()), uint8(baseNetwork));
        
        assertEq(sequencerFeeVault.RECIPIENT(), sequencerRecipient);
        assertEq(sequencerFeeVault.MIN_WITHDRAWAL_AMOUNT(), sequencerMinWithdrawal);
        assertEq(uint8(sequencerFeeVault.WITHDRAWAL_NETWORK()), uint8(sequencerNetwork));
        
        assertEq(l1FeeVault.RECIPIENT(), l1Recipient);
        assertEq(l1FeeVault.MIN_WITHDRAWAL_AMOUNT(), l1MinWithdrawal);
        assertEq(uint8(l1FeeVault.WITHDRAWAL_NETWORK()), uint8(l1Network));
        
        assertEq(operatorFeeVault.RECIPIENT(), operatorRecipient);
        assertEq(operatorFeeVault.MIN_WITHDRAWAL_AMOUNT(), operatorMinWithdrawal);
        assertEq(uint8(operatorFeeVault.WITHDRAWAL_NETWORK()), uint8(operatorNetwork));
    }
}