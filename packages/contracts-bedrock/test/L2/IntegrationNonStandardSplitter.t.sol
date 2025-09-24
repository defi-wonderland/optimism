// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { DeployUtils } from "scripts/libraries/DeployUtils.sol";
import { IL1FeeVault } from "interfaces/L2/IL1FeeVault.sol";
import { IFeeVaultConstructor, IFeeVault } from "interfaces/L2/IFeeVault.sol";
import { IOperatorFeeVault } from "interfaces/L2/IOperatorFeeVault.sol";
import { ISequencerFeeVault } from "interfaces/L2/ISequencerFeeVault.sol";
import { IBaseFeeVault } from "interfaces/L2/IBaseFeeVault.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { Types } from "src/libraries/Types.sol";

interface IUnichainFeeSplitter {
    event FeesDistributed(uint256 optimismShare, uint256 l1Fees, uint256 netShare);
    event NoFeesCollected();

    function distributeFees() external returns (bool feesDistributed);
}

interface IBaseFeeSplitter { // it actually is called FeeDisbuser
    function disburseFees() external;
    function FEE_DISBURSEMENT_INTERVAL() external view returns (uint256);
}


/// @title IntegrationNonStandardSplitters
/// @notice Integration tests for non-standard splitters
contract IntegrationNonStandardSplitters is Test {
    address public constant UNICHAIN_FEE_SPLITTER = 0x8Ae8710611e58eDF83978dDd833dFdEE1eD1FB8e;
    address public constant BASE_FEE_SPLITTER = 0x76355A67fCBCDE6F9a69409A8EAd5EaA9D8d875d;

    // Event for testing Unichain
    event FeesDistributed(uint256 optimismShare, uint256 l1Fees, uint256 netShare);

    // Event for testing Base
    event FeesDisbursed(uint256 disbursementTime, uint256 paidToOptimism, uint256 totalFeesDisbursed);
    
    // Event for testing both
    event NoFeesCollected();

    function _getVaultSettings(address _vault) internal returns (address recipient, uint256 minWithdrawalAmount, Types.WithdrawalNetwork network) {
        IFeeVault feeVault = IFeeVault(payable(_vault));
        recipient = feeVault.RECIPIENT();
        minWithdrawalAmount = feeVault.MIN_WITHDRAWAL_AMOUNT();
        network = feeVault.WITHDRAWAL_NETWORK();
    }

    function setUp() public {
        // Get environment variables
        string memory rpcUrl = vm.envString("FORK_RPC_URL");
        uint256 blockNumber = vm.envUint("FORK_BLOCK_NUMBER");
        
        // Create fork from environment variables
        vm.createSelectFork(rpcUrl, blockNumber);
        
        // Require OP Mainnet chain ID
        require(block.chainid == 84532 || block.chainid == 1301, "Integration tests require Base or Unichain Mainnet fork (chain ID 84532 or 1301)");

        // Label predeploys for better test output
        vm.label(Predeploys.BASE_FEE_VAULT, "BaseFeeVault");
        vm.label(Predeploys.L1_FEE_VAULT, "L1FeeVault");
        vm.label(Predeploys.SEQUENCER_FEE_WALLET, "SequencerFeeVault");
        vm.label(Predeploys.OPERATOR_FEE_VAULT, "OperatorFeeVault");

        (address recipient, uint256 minWithdrawalAmount, Types.WithdrawalNetwork network) = _getVaultSettings(Predeploys.L1_FEE_VAULT);

        IL1FeeVault l1FeeVault = IL1FeeVault(
            DeployUtils.create1({
                _name: "L1FeeVault",
                _args: DeployUtils.encodeConstructor(
                    abi.encodeCall(
                        IFeeVaultConstructor.__constructor__, (recipient, minWithdrawalAmount, network)
                    )
                )
            })
        );
        
        (recipient, minWithdrawalAmount, network) = _getVaultSettings(Predeploys.OPERATOR_FEE_VAULT);

        IOperatorFeeVault operatorFeeVault = IOperatorFeeVault(
            DeployUtils.create1({
                _name: "OperatorFeeVault",
                _args: DeployUtils.encodeConstructor(
                    abi.encodeCall(IFeeVaultConstructor.__constructor__, (recipient, minWithdrawalAmount, network))
                )
            })
        );

        (recipient, minWithdrawalAmount, network) = _getVaultSettings(Predeploys.SEQUENCER_FEE_WALLET);

        ISequencerFeeVault sequencerFeeVault = ISequencerFeeVault(
            DeployUtils.create1({
                _name: "SequencerFeeVault",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IFeeVaultConstructor.__constructor__, (recipient, minWithdrawalAmount, network)))
            })
        );

        (recipient, minWithdrawalAmount, network) = _getVaultSettings(Predeploys.BASE_FEE_VAULT);

        IBaseFeeVault baseFeeVault = IBaseFeeVault(
            DeployUtils.create1({
                _name: "BaseFeeVault",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IFeeVaultConstructor.__constructor__, (recipient, minWithdrawalAmount, network)))
            })
        );

        vm.etch(Predeploys.L1_FEE_VAULT, address(l1FeeVault).code);
        vm.etch(Predeploys.OPERATOR_FEE_VAULT, address(operatorFeeVault).code);
        vm.etch(Predeploys.SEQUENCER_FEE_WALLET, address(sequencerFeeVault).code);
        vm.etch(Predeploys.BASE_FEE_VAULT, address(baseFeeVault).code);
    }

    function test_unichain_fee_splitter() public {
        vm.label(UNICHAIN_FEE_SPLITTER, "FeeSplitter");

        // Declare contracts
        IL1FeeVault l1FeeVault = IL1FeeVault(payable(Predeploys.L1_FEE_VAULT));
        IOperatorFeeVault operatorFeeVault = IOperatorFeeVault(payable(Predeploys.OPERATOR_FEE_VAULT));
        ISequencerFeeVault sequencerFeeVault = ISequencerFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET));
        IBaseFeeVault baseFeeVault = IBaseFeeVault(payable(Predeploys.BASE_FEE_VAULT));
        IUnichainFeeSplitter feeSplitter = IUnichainFeeSplitter(UNICHAIN_FEE_SPLITTER);

        // Fund vaults
        vm.deal(Predeploys.L1_FEE_VAULT, 10 ether);
        vm.deal(Predeploys.OPERATOR_FEE_VAULT, 10 ether);
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 10 ether);
        vm.deal(Predeploys.BASE_FEE_VAULT, 10 ether);

        // Distribute fees
        // 1. Optimism share, 2. L1 fees, 3. Net share
        vm.expectEmit(true, true, true, true, UNICHAIN_FEE_SPLITTER);
        emit FeesDistributed(3 ether, 10 ether, 17 ether); 
        feeSplitter.distributeFees();
        
        // Update min withdrawal amount
        vm.startPrank(IProxyAdmin(Predeploys.PROXY_ADMIN).owner());
        l1FeeVault.setMinWithdrawalAmount(1 ether);
        operatorFeeVault.setMinWithdrawalAmount(1 ether);
        sequencerFeeVault.setMinWithdrawalAmount(1 ether);
        baseFeeVault.setMinWithdrawalAmount(1 ether);
        vm.stopPrank();

        // Fund vaults with less than the min withdrawal amount
        vm.deal(Predeploys.L1_FEE_VAULT, 1 ether - 1);
        vm.deal(Predeploys.OPERATOR_FEE_VAULT, 1 ether - 1);
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 1 ether - 1);
        vm.deal(Predeploys.BASE_FEE_VAULT, 1 ether - 1);

        // Try to withdraw, it shouldn't withdraw
        vm.expectEmit(true, true, true, true, UNICHAIN_FEE_SPLITTER);
        emit NoFeesCollected();
        feeSplitter.distributeFees();
    }

    function test_base_fee_splitter() public {
        vm.label(BASE_FEE_SPLITTER, "FeeSplitter");

        // Declare contracts
        IL1FeeVault l1FeeVault = IL1FeeVault(payable(Predeploys.L1_FEE_VAULT));
        IOperatorFeeVault operatorFeeVault = IOperatorFeeVault(payable(Predeploys.OPERATOR_FEE_VAULT));
        ISequencerFeeVault sequencerFeeVault = ISequencerFeeVault(payable(Predeploys.SEQUENCER_FEE_WALLET));
        IBaseFeeVault baseFeeVault = IBaseFeeVault(payable(Predeploys.BASE_FEE_VAULT));
        IBaseFeeSplitter feeSplitter = IBaseFeeSplitter(BASE_FEE_SPLITTER);

        // Fund vaults
        vm.deal(Predeploys.L1_FEE_VAULT, 10 ether);
        vm.deal(Predeploys.OPERATOR_FEE_VAULT, 10 ether);
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 10 ether);
        vm.deal(Predeploys.BASE_FEE_VAULT, 10 ether);

        // Distribute fees
        // 1. Disbursement time, 2. Paid to Optimism, 3. Total fees disbursed
        vm.expectEmit(true, true, true, true, BASE_FEE_SPLITTER);
        emit FeesDisbursed(block.timestamp, 1465590281055871330227, 9780601873705808868182); 
        feeSplitter.disburseFees();

        // Update min withdrawal amount
        vm.startPrank(IProxyAdmin(Predeploys.PROXY_ADMIN).owner());
        l1FeeVault.setMinWithdrawalAmount(10 ether);
        operatorFeeVault.setMinWithdrawalAmount(10 ether);
        sequencerFeeVault.setMinWithdrawalAmount(10 ether);
        baseFeeVault.setMinWithdrawalAmount(10 ether);
        vm.stopPrank();

        // Fund vaults with less than the min withdrawal amount
        vm.deal(Predeploys.L1_FEE_VAULT, 10 ether - 1);
        vm.deal(Predeploys.OPERATOR_FEE_VAULT, 10 ether - 1);
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 10 ether - 1);
        vm.deal(Predeploys.BASE_FEE_VAULT, 10 ether - 1);

        // Advance time for new disbursement
        vm.warp(block.timestamp + feeSplitter.FEE_DISBURSEMENT_INTERVAL() + 1);

        // Try to withdraw, it shouldn't withdraw, but it reverts because of checking the immutable value
        /* vm.expectEmit(true, true, true, true, BASE_FEE_SPLITTER);
        emit NoFeesCollected(); */
        vm.expectRevert("FeeVault: withdrawal amount must be greater than minimum withdrawal amount");
        feeSplitter.disburseFees();
    }
}