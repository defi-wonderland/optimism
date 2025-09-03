// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";

// Contracts
import { FeeVaultInitializer } from "src/L2/FeeVaultInitializer.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";

// Interfaces
import { IBaseFeeVault } from "interfaces/L2/IBaseFeeVault.sol";
import { ISequencerFeeVault } from "interfaces/L2/ISequencerFeeVault.sol";
import { IL1FeeVault } from "interfaces/L2/IL1FeeVault.sol";
import { IOperatorFeeVault } from "interfaces/L2/IOperatorFeeVault.sol";

contract FeeVaultInitializer_Test is CommonTest {
    FeeVaultInitializer feeVaultInitializer;

    // Store original vault configurations
    address originalBaseRecipient;
    uint256 originalBaseMinWithdrawal;
    Types.WithdrawalNetwork originalBaseNetwork;
    
    address originalSequencerRecipient;
    uint256 originalSequencerMinWithdrawal;
    Types.WithdrawalNetwork originalSequencerNetwork;
    
    address originalL1Recipient;
    uint256 originalL1MinWithdrawal;
    Types.WithdrawalNetwork originalL1Network;
    
    address originalOperatorRecipient;
    uint256 originalOperatorMinWithdrawal;
    Types.WithdrawalNetwork originalOperatorNetwork;

    event FeeVaultDeployed(
        string indexed vaultType,
        address indexed newImplementation,
        address recipient,
        Types.WithdrawalNetwork network,
        uint256 minWithdrawalAmount
    );

    function setUp() public override {
        super.setUp();

        // Capture original Base Fee Vault configuration
        originalBaseRecipient = baseFeeVault.RECIPIENT();
        originalBaseMinWithdrawal = baseFeeVault.MIN_WITHDRAWAL_AMOUNT();
        originalBaseNetwork = baseFeeVault.WITHDRAWAL_NETWORK();
        
        // Capture original Sequencer Fee Vault configuration
        originalSequencerRecipient = sequencerFeeVault.RECIPIENT();
        originalSequencerMinWithdrawal = sequencerFeeVault.MIN_WITHDRAWAL_AMOUNT();
        originalSequencerNetwork = sequencerFeeVault.WITHDRAWAL_NETWORK();
        
        // Capture original L1 Fee Vault configuration
        originalL1Recipient = l1FeeVault.RECIPIENT();
        originalL1MinWithdrawal = l1FeeVault.MIN_WITHDRAWAL_AMOUNT();
        originalL1Network = l1FeeVault.WITHDRAWAL_NETWORK();
        
        // Capture original Operator Fee Vault configuration
        originalOperatorRecipient = operatorFeeVault.RECIPIENT();
        originalOperatorMinWithdrawal = operatorFeeVault.MIN_WITHDRAWAL_AMOUNT();
        originalOperatorNetwork = operatorFeeVault.WITHDRAWAL_NETWORK();
    }

    function test_constructor_succeeds() public {      
        // Get the current nonce and predicted initializer address to predict the vault addresses
        uint64 currentNonce = vm.getNonce(address(this));
        address predictedInitializerAddress = vm.computeCreateAddress(address(this), currentNonce);
        
        // Test event emissions before fee vault initializer deployment
        _testEventEmissions(predictedInitializerAddress);
        
        // Deploy the FeeVaultInitializer
        feeVaultInitializer = new FeeVaultInitializer();

        // Can now read the fee vault initializer version
        assertEq(feeVaultInitializer.version(), "1.0.0");
        assertEq(address(feeVaultInitializer), predictedInitializerAddress);
        
        // Test the new implementations have correct configurations against the original values
        _testNewImplementations(predictedInitializerAddress);
    }
    
    function _testEventEmissions(address _predictedInitializerAddress) internal {
        address predictedBaseFeeVault = vm.computeCreateAddress(_predictedInitializerAddress, 1);
        address predictedSequencerFeeVault = vm.computeCreateAddress(_predictedInitializerAddress, 2);
        address predictedL1FeeVault = vm.computeCreateAddress(_predictedInitializerAddress, 3);
        address predictedOperatorFeeVault = vm.computeCreateAddress(_predictedInitializerAddress, 4);

        // Expect the FeeVaultDeployed events from the FeeVaultInitializer contract using the original values
        vm.expectEmit(_predictedInitializerAddress);
        emit FeeVaultDeployed("BaseFeeVault", predictedBaseFeeVault, originalBaseRecipient, originalBaseNetwork, originalBaseMinWithdrawal);

        vm.expectEmit(_predictedInitializerAddress);
        emit FeeVaultDeployed("SequencerFeeVault", predictedSequencerFeeVault, originalSequencerRecipient, originalSequencerNetwork, originalSequencerMinWithdrawal);

        vm.expectEmit(_predictedInitializerAddress);
        emit FeeVaultDeployed("L1FeeVault", predictedL1FeeVault, originalL1Recipient, originalL1Network, originalL1MinWithdrawal);

        vm.expectEmit(_predictedInitializerAddress);
        emit FeeVaultDeployed("OperatorFeeVault", predictedOperatorFeeVault, originalOperatorRecipient, originalOperatorNetwork, originalOperatorMinWithdrawal);
    }
    
    function _testNewImplementations(address _predictedInitializerAddress) internal view {
        address predictedBaseFeeVault = vm.computeCreateAddress(_predictedInitializerAddress, 1);
        address predictedSequencerFeeVault = vm.computeCreateAddress(_predictedInitializerAddress, 2);
        address predictedL1FeeVault = vm.computeCreateAddress(_predictedInitializerAddress, 3);
        address predictedOperatorFeeVault = vm.computeCreateAddress(_predictedInitializerAddress, 4);
        
        _testBaseFeeVaultImplementation(predictedBaseFeeVault);
        _testSequencerFeeVaultImplementation(predictedSequencerFeeVault);
        _testL1FeeVaultImplementation(predictedL1FeeVault);
        _testOperatorFeeVaultImplementation(predictedOperatorFeeVault);
    }
    
    function _testBaseFeeVaultImplementation(address _newImplementation) internal view {
        IBaseFeeVault newBaseFeeVault = IBaseFeeVault(payable(_newImplementation));
        // Test against the original stored values
        assertEq(newBaseFeeVault.RECIPIENT(), originalBaseRecipient);
        assertEq(newBaseFeeVault.MIN_WITHDRAWAL_AMOUNT(), originalBaseMinWithdrawal);
        assertEq(uint8(newBaseFeeVault.WITHDRAWAL_NETWORK()), uint8(originalBaseNetwork));

        // Check new getter functions return the same original values
        assertEq(newBaseFeeVault.recipient(), originalBaseRecipient);
        assertEq(newBaseFeeVault.minWithdrawalAmount(), originalBaseMinWithdrawal);
        assertEq(uint8(newBaseFeeVault.withdrawalNetwork()), uint8(originalBaseNetwork));
    }
    
    function _testSequencerFeeVaultImplementation(address _newImplementation) internal view {
        ISequencerFeeVault newSequencerFeeVault = ISequencerFeeVault(payable(_newImplementation));
        // Test against the original stored values
        assertEq(newSequencerFeeVault.RECIPIENT(), originalSequencerRecipient);
        assertEq(newSequencerFeeVault.MIN_WITHDRAWAL_AMOUNT(), originalSequencerMinWithdrawal);
        assertEq(uint8(newSequencerFeeVault.WITHDRAWAL_NETWORK()), uint8(originalSequencerNetwork));

        // Check new getter functions return the same original values
        assertEq(newSequencerFeeVault.recipient(), originalSequencerRecipient);
        assertEq(newSequencerFeeVault.minWithdrawalAmount(), originalSequencerMinWithdrawal);
        assertEq(uint8(newSequencerFeeVault.withdrawalNetwork()), uint8(originalSequencerNetwork));
    }
    
    function _testL1FeeVaultImplementation(address _newImplementation) internal view {
        IL1FeeVault newL1FeeVault = IL1FeeVault(payable(_newImplementation));
        // Test against the original stored values
        assertEq(newL1FeeVault.RECIPIENT(), originalL1Recipient);
        assertEq(newL1FeeVault.MIN_WITHDRAWAL_AMOUNT(), originalL1MinWithdrawal);
        assertEq(uint8(newL1FeeVault.WITHDRAWAL_NETWORK()), uint8(originalL1Network));

        // Check new getter functions return the same original values
        assertEq(newL1FeeVault.recipient(), originalL1Recipient);
        assertEq(newL1FeeVault.minWithdrawalAmount(), originalL1MinWithdrawal);
        assertEq(uint8(newL1FeeVault.withdrawalNetwork()), uint8(originalL1Network));
    }
    
    function _testOperatorFeeVaultImplementation(address _newImplementation) internal view {
        IOperatorFeeVault newOperatorFeeVault = IOperatorFeeVault(payable(_newImplementation));
        // Test against the original stored values
        assertEq(newOperatorFeeVault.RECIPIENT(), originalOperatorRecipient);
        assertEq(newOperatorFeeVault.MIN_WITHDRAWAL_AMOUNT(), originalOperatorMinWithdrawal);
        assertEq(uint8(newOperatorFeeVault.WITHDRAWAL_NETWORK()), uint8(originalOperatorNetwork));

        // Check new getter functions return the same original values
        assertEq(newOperatorFeeVault.recipient(), originalOperatorRecipient);
        assertEq(newOperatorFeeVault.minWithdrawalAmount(), originalOperatorMinWithdrawal);
        assertEq(uint8(newOperatorFeeVault.withdrawalNetwork()), uint8(originalOperatorNetwork));
    }
}
