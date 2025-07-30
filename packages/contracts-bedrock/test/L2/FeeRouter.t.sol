// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from "test/setup/CommonTest.sol";
import { FeeRouter } from "src/L2/FeeRouter.sol";
import { OptimismPortal2 } from "src/L1/OptimismPortal2.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Types } from "src/libraries/Types.sol";
import { IL2ToL1MessagePasser } from "interfaces/L2/IL2ToL1MessagePasser.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";

contract FeeRouterTest is CommonTest {
    address private _optimismPortal2;
    address private _feeCollector;
    address private _owner;

    // Events
    event FeesDisbursed(
        uint256 indexed disbursementTime, uint256 paidToL1Wallet, uint256 paidToFeeCollector, uint256 totalFeesDisbursed
    );

    // Use common test to setup the test enniornment
    // Need to set up / deploy the fee router as a predeploy behind a proxy contract
    function setUp() public override {
        super.setUp();
        _deployFeeRouter();
    }

    function _deployFeeRouter() internal {
        // Deploy FeeRouter implementation
        FeeRouter implementation = new FeeRouter();

        // Deploy proxy at the predeploy address with the implementation
        vm.etch(Predeploys.FEE_ROUTER, address(new Proxy(address(implementation))).code);

        // Set the admin to the ProxyAdmin predeploy
        EIP1967Helper.setAdmin(Predeploys.FEE_ROUTER, Predeploys.PROXY_ADMIN);

        // Set the implementation
        EIP1967Helper.setImplementation(Predeploys.FEE_ROUTER, address(implementation));

        // Label the contract for better debugging
        vm.label(Predeploys.FEE_ROUTER, "FeeRouter");

        _owner = ProxyAdmin(Predeploys.PROXY_ADMIN).owner();

        // Deploy OptimismPortal2
        _optimismPortal2 = address(new OptimismPortal2(100));

        // Deploy fee collector
        _feeCollector = address(new Mock_FeeCollector());
    }

    function _initializeFeeRouter() internal {
        // Initialize the fee router as admin
        vm.prank(_owner);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).initialize(
            payable(Predeploys.L1_FEE_VAULT), payable(_feeCollector), payable(_optimismPortal2), 24 hours, 150
        );
    }

    function _setupMockFeeVaults() internal {
        // Deploy mock FeeVault contracts with proper configuration
        Mock_FeeVault sequencerFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_ROUTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault baseFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_ROUTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault l1FeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_ROUTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        Mock_FeeVault operatorFeeVault = new Mock_FeeVault(
            payable(Predeploys.FEE_ROUTER), // recipient
            1 ether, // minWithdrawalAmount
            Types.WithdrawalNetwork.L2 // withdrawalNetwork
        );

        // Etch the mock vaults at the predeploy addresses
        vm.etch(Predeploys.SEQUENCER_FEE_WALLET, address(sequencerFeeVault).code);
        vm.etch(Predeploys.BASE_FEE_VAULT, address(baseFeeVault).code);
        vm.etch(Predeploys.L1_FEE_VAULT, address(l1FeeVault).code);
        vm.etch(Predeploys.OPERATOR_FEE_VAULT, address(operatorFeeVault).code);
    }

    // assert the block chain id is correctly set to the current chain id
    function test_constructor_succeeds() public {
        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).BLOCK_CHAIN_ID(), block.chainid);
    }

    // assert all addresses, fee disbursment interval, and l1 wallet share are correctly set
    function test_feeRouter_initialization() public {
        _initializeFeeRouter();

        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).BLOCK_CHAIN_ID(), block.chainid);
        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).l1Wallet(), Predeploys.L1_FEE_VAULT);
        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).feeCollector(), _feeCollector);
        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).opPortalAddress(), _optimismPortal2);
        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).feeDisbursementInterval(), 24 hours);
        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).l1FeeWalletShare(), 150);
    }

    function test_feeRouter_disburseFees_reverts_when_feeDisbursementInterval_not_reached() public {
        _initializeFeeRouter();
        vm.roll(block.timestamp + 24 hours + 1);

        vm.expectRevert(FeeRouter.FeeRouter_DisbursementIntervalNotReached.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).disburseFees();
    }

    function test_feeRouter_disburseFees_opMainnet_succeeds() public {
        // Set chain ID to OP Mainnet (10) before deployment
        vm.chainId(10);

        // Deploy FeeRouter with OP Mainnet chain ID
        _deployFeeRouter();
        _initializeFeeRouter();
        _setupMockFeeVaults();

        // Deploy and setup Mock L2ToL1MessagePasser
        Mock_L2ToL1MessagePasser mockMessagePasser = new Mock_L2ToL1MessagePasser();
        vm.etch(Predeploys.L2_TO_L1_MESSAGE_PASSER, address(mockMessagePasser).code);

        // Add balances to the fee vaults
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 2 ether);
        vm.deal(Predeploys.BASE_FEE_VAULT, 3 ether);
        vm.deal(Predeploys.L1_FEE_VAULT, 1 ether);
        vm.deal(Predeploys.OPERATOR_FEE_VAULT, 1 ether);

        // Fast forward time to allow disbursement
        vm.warp(block.timestamp + 25 hours);

        // Calculate expected amounts
        uint256 totalFees = 7 ether;
        uint256 l1WalletShare = totalFees * FeeRouter(payable(Predeploys.FEE_ROUTER)).l1FeeWalletShare()
            / FeeRouter(payable(Predeploys.FEE_ROUTER)).BASIS_POINT_SCALE(); // 1.5%
        uint256 feeCollectorShare = totalFees - l1WalletShare;

        // Expect L2ToL1MessagePasser call for L1 wallet share
        vm.expectCall(
            Predeploys.L2_TO_L1_MESSAGE_PASSER,
            l1WalletShare,
            abi.encodeCall(IL2ToL1MessagePasser.initiateWithdrawal, (Predeploys.L1_FEE_VAULT, 35000, hex""))
        );

        // Expect the FeesDisbursed event to be emitted
        vm.expectEmit(address(Predeploys.FEE_ROUTER));
        emit FeesDisbursed({
            disbursementTime: block.timestamp,
            paidToL1Wallet: l1WalletShare,
            paidToFeeCollector: feeCollectorShare,
            totalFeesDisbursed: totalFees
        });

        // Store initial balances
        uint256 feeCollectorBalanceBefore = address(_feeCollector).balance;

        // Call disburseFees
        FeeRouter(payable(Predeploys.FEE_ROUTER)).disburseFees();

        // Verify the last disbursement time was updated
        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).lastDisbursementTime(), block.timestamp);

        // Verify fee collector received the correct amount (OP Mainnet flow)
        assertEq(address(_feeCollector).balance, feeCollectorBalanceBefore + feeCollectorShare);
    }

    function test_feeRouter_disburseFees_opStackChain_succeeds() public {
        // Set chain ID to non-OP Mainnet (420 for OP Sepolia) before deployment
        vm.chainId(420);

        // Deploy FeeRouter with OP Stack Chain ID
        _deployFeeRouter();
        _initializeFeeRouter();
        _setupMockFeeVaults();

        // Deploy and setup Mock L2ToL1MessagePasser
        Mock_L2ToL1MessagePasser mockMessagePasser = new Mock_L2ToL1MessagePasser();
        vm.etch(Predeploys.L2_TO_L1_MESSAGE_PASSER, address(mockMessagePasser).code);

        // Add balances to the fee vaults
        vm.deal(Predeploys.SEQUENCER_FEE_WALLET, 2 ether);
        vm.deal(Predeploys.BASE_FEE_VAULT, 3 ether);
        vm.deal(Predeploys.L1_FEE_VAULT, 1 ether);
        vm.deal(Predeploys.OPERATOR_FEE_VAULT, 1 ether);

        // Fast forward time to allow disbursement
        vm.warp(block.timestamp + 25 hours);

        // Calculate expected amounts
        uint256 totalFees = 7 ether;
        uint256 l1WalletShare = totalFees * FeeRouter(payable(Predeploys.FEE_ROUTER)).l1FeeWalletShare()
            / FeeRouter(payable(Predeploys.FEE_ROUTER)).BASIS_POINT_SCALE(); // 1.5%
        uint256 feeCollectorShare = totalFees - l1WalletShare;

        // Expect L2ToL1MessagePasser call for L1 wallet share
        vm.expectCall(
            Predeploys.L2_TO_L1_MESSAGE_PASSER,
            l1WalletShare,
            abi.encodeCall(IL2ToL1MessagePasser.initiateWithdrawal, (Predeploys.L1_FEE_VAULT, 35000, hex""))
        );

        // Build expected data for OP Fee Collector deposit transaction
        bytes memory expectedData =
            abi.encodeCall(IOptimismPortal2.depositTransaction, (_feeCollector, feeCollectorShare, 35000, false, hex""));

        // Expect L2ToL1MessagePasser call for fee collector share (OP Stack Chain flow)
        vm.expectCall(
            Predeploys.L2_TO_L1_MESSAGE_PASSER,
            feeCollectorShare,
            abi.encodeCall(IL2ToL1MessagePasser.initiateWithdrawal, (_optimismPortal2, 35000, expectedData))
        );

        // Expect the FeesDisbursed event to be emitted
        vm.expectEmit(address(Predeploys.FEE_ROUTER));
        emit FeesDisbursed({
            disbursementTime: block.timestamp,
            paidToL1Wallet: l1WalletShare,
            paidToFeeCollector: feeCollectorShare,
            totalFeesDisbursed: totalFees
        });

        // Call disburseFees
        FeeRouter(payable(Predeploys.FEE_ROUTER)).disburseFees();

        // Verify the last disbursement time was updated
        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).lastDisbursementTime(), block.timestamp);
    }

    // expect a revert when initializing with an invalid _l1Wallet (adress(0))
    function test_feeRouter_initialize_reverts_with_invalid_l1Wallet() public {
        _deployFeeRouter();

        vm.prank(_owner);
        vm.expectRevert(FeeRouter.FeeRouter_L1WalletCannotBeZero.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).initialize(
            payable(address(0)), payable(address(0)), payable(address(0)), 24 hours, 0
        );
    }

    // expect a revert when initializing with an invalid _feeCollector (address(0))
    function test_feeRouter_initialize_reverts_with_invalid_feeCollector() public {
        _deployFeeRouter();

        vm.prank(_owner);
        vm.expectRevert(FeeRouter.FeeRouter_FeeCollectorCannotBeZero.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).initialize(
            payable(address(1)), payable(address(0)), payable(address(0)), 24 hours, 0
        );
    }

    // expect a revert when initializing with an invalid _opPortalAddress (address(0))
    function test_feeRouter_initialize_reverts_with_invalid_opPortalAddress() public {
        _deployFeeRouter();

        vm.prank(_owner);
        vm.expectRevert(FeeRouter.FeeRouter_OpPortalAddressCannotBeZero.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).initialize(
            payable(address(1)), payable(address(1)), payable(address(0)), 24 hours, 0
        );
    }

    // expect a revert when initializing with an invalid _feeDisbursementInterval (less than 24 hours)
    function test_feeRouter_initialize_reverts_with_invalid_feeDisbursementInterval() public {
        _deployFeeRouter();

        vm.prank(_owner);
        vm.expectRevert(FeeRouter.FeeRouter_FeeDisbursementIntervalTooShort.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).initialize(
            payable(address(1)), payable(address(1)), payable(address(1)), 1 hours, 0
        );
    }

    // expect a revert when initializing with an invalid _l1FeeWalletShare (greater than 100%)
    function test_feeRouter_initialize_reverts_with_invalid_l1FeeWalletShare() public {
        _deployFeeRouter();

        vm.prank(_owner);
        vm.expectRevert(FeeRouter.FeeRouter_L1FeeWalletShareExceeds100Percent.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).initialize(
            payable(address(1)), payable(address(1)), payable(address(1)), 24 hours, 10001
        );
    }

    // test the setL1Wallet function works as expected
    function test_feeRouter_setL1Wallet_succeeds(address _newL1Wallet) public {
        vm.assume(_newL1Wallet != address(0));
        _initializeFeeRouter();

        vm.prank(_owner);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setL1Wallet(_newL1Wallet);

        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).l1Wallet(), _newL1Wallet);
    }

    // test the setL1Wallet function reverts with an invalid _newL1Wallet (address(0))
    function test_feeRouter_setL1Wallet_reverts_with_invalid_newL1Wallet() public {
        _initializeFeeRouter();

        vm.prank(_owner);
        vm.expectRevert(FeeRouter.FeeRouter_NewL1WalletCannotBeZero.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setL1Wallet(address(0));
    }

    // test the setL1Wallet function reverts when the caller is not the owner
    function test_feeRouter_setL1Wallet_reverts_when_caller_is_not_owner(address _caller) public {
        vm.assume(_caller != _owner);

        _initializeFeeRouter();

        vm.prank(_caller);
        vm.expectRevert(FeeRouter.FeeRouter_OnlyProxyAdminOwner.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setL1Wallet(address(0x123));
    }

    // test the setFeeCollector function works as expected
    function test_feeRouter_setFeeCollector_succeeds(address _newFeeCollector) public {
        vm.assume(_newFeeCollector != address(0));
        _initializeFeeRouter();

        vm.prank(_owner);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setFeeCollector(payable(_newFeeCollector));

        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).feeCollector(), _newFeeCollector);
    }

    // test the setFeeCollector function reverts with an invalid _newFeeCollector (address(0))
    function test_feeRouter_setFeeCollector_reverts_with_invalid_newFeeCollector() public {
        _initializeFeeRouter();

        vm.prank(_owner);
        vm.expectRevert(FeeRouter.FeeRouter_NewFeeCollectorCannotBeZero.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setFeeCollector(payable(address(0)));
    }

    // test the setFeeCollector function reverts when the caller is not the owner
    function test_feeRouter_setFeeCollector_reverts_when_caller_is_not_owner(address _caller) public {
        vm.assume(_caller != _owner);

        _initializeFeeRouter();

        vm.prank(_caller);
        vm.expectRevert(FeeRouter.FeeRouter_OnlyProxyAdminOwner.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setFeeCollector(payable(address(0x789)));
    }

    // test the setOpPortalAddress function works as expected
    function test_feeRouter_setOpPortalAddress_succeeds(address _newOpPortalAddress) public {
        vm.assume(_newOpPortalAddress != address(0));
        _initializeFeeRouter();

        vm.prank(_owner);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setOpPortalAddress(_newOpPortalAddress);

        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).opPortalAddress(), _newOpPortalAddress);
    }

    // test the setOpPortalAddress function reverts with an invalid _newOpPortalAddress (address(0))
    function test_feeRouter_setOpPortalAddress_reverts_with_invalid_newOpPortalAddress() public {
        _initializeFeeRouter();

        vm.prank(_owner);
        vm.expectRevert(FeeRouter.FeeRouter_NewOpPortalAddressCannotBeZero.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setOpPortalAddress(address(0));
    }

    // test the setOpPortalAddress function reverts when the caller is not the owner
    function test_feeRouter_setOpPortalAddress_reverts_when_caller_is_not_owner(address _caller) public {
        vm.assume(_caller != _owner);

        _initializeFeeRouter();

        vm.prank(_caller);
        vm.expectRevert(FeeRouter.FeeRouter_OnlyProxyAdminOwner.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setOpPortalAddress(address(0xABC));
    }

    // test the setL1FeeWalletShare function works as expected
    function test_feeRouter_setL1FeeWalletShare_succeeds(uint256 _newL1FeeWalletShare) public {
        _newL1FeeWalletShare = bound(_newL1FeeWalletShare, 0, 10000);
        _initializeFeeRouter();

        vm.prank(_owner);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setL1FeeWalletShare(_newL1FeeWalletShare);

        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).l1FeeWalletShare(), _newL1FeeWalletShare);
    }

    // test the setL1FeeWalletShare function reverts with an invalid _newL1FeeWalletShare (greater than 100%)
    function test_feeRouter_setL1FeeWalletShare_reverts_with_invalid_newL1FeeWalletShare(uint256 _newL1FeeWalletShare)
        public
    {
        _newL1FeeWalletShare = bound(_newL1FeeWalletShare, 10001, type(uint256).max);
        _initializeFeeRouter();

        vm.prank(_owner);
        vm.expectRevert(FeeRouter.FeeRouter_NewL1FeeWalletShareExceeds100Percent.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setL1FeeWalletShare(_newL1FeeWalletShare);
    }

    // test the setL1FeeWalletShare function reverts when the caller is not the owner
    function test_feeRouter_setL1FeeWalletShare_reverts_when_caller_is_not_owner(address _caller) public {
        vm.assume(_caller != _owner);

        _initializeFeeRouter();

        vm.prank(_caller);
        vm.expectRevert(FeeRouter.FeeRouter_OnlyProxyAdminOwner.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setL1FeeWalletShare(150);
    }

    // test the setFeeDisbursementInterval function works as expected
    function test_feeRouter_setFeeDisbursementInterval_succeeds(uint256 _newFeeDisbursementInterval) public {
        _newFeeDisbursementInterval = bound(_newFeeDisbursementInterval, 24 hours, type(uint256).max);
        _initializeFeeRouter();

        vm.prank(_owner);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setFeeDisbursementInterval(_newFeeDisbursementInterval);

        assertEq(FeeRouter(payable(Predeploys.FEE_ROUTER)).feeDisbursementInterval(), _newFeeDisbursementInterval);
    }

    // test the setFeeDisbursementInterval function reverts with an invalid _newFeeDisbursementInterval (less than 24
    // hours)
    function test_feeRouter_setFeeDisbursementInterval_reverts_with_invalid_newFeeDisbursementInterval(
        uint256 _newFeeDisbursementInterval
    )
        public
    {
        _newFeeDisbursementInterval = bound(_newFeeDisbursementInterval, 0, 24 hours - 1);
        _initializeFeeRouter();

        vm.prank(_owner);
        vm.expectRevert(FeeRouter.FeeRouter_NewFeeDisbursementIntervalTooShort.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setFeeDisbursementInterval(_newFeeDisbursementInterval);
    }

    // test the setFeeDisbursementInterval function reverts when the caller is not the owner
    function test_feeRouter_setFeeDisbursementInterval_reverts_when_caller_is_not_owner(address _caller) public {
        vm.assume(_caller != _owner);

        _initializeFeeRouter();

        vm.prank(_caller);
        vm.expectRevert(FeeRouter.FeeRouter_OnlyProxyAdminOwner.selector);
        FeeRouter(payable(Predeploys.FEE_ROUTER)).setFeeDisbursementInterval(48 hours);
    }
}

contract Mock_FeeCollector {
    receive() external payable { }
}

contract Mock_FeeVault {
    uint256 public immutable MIN_WITHDRAWAL_AMOUNT;
    address public immutable RECIPIENT;
    Types.WithdrawalNetwork public immutable WITHDRAWAL_NETWORK;
    uint256 public totalProcessed;

    event Withdrawal(uint256 value, address to, address from);
    event Withdrawal(uint256 value, address to, address from, Types.WithdrawalNetwork withdrawalNetwork);

    constructor(address payable _recipient, uint256 _minWithdrawalAmount, Types.WithdrawalNetwork _withdrawalNetwork) {
        RECIPIENT = _recipient;
        MIN_WITHDRAWAL_AMOUNT = _minWithdrawalAmount;
        WITHDRAWAL_NETWORK = _withdrawalNetwork;
    }

    receive() external payable { }

    function withdraw() external {
        require(
            address(this).balance >= MIN_WITHDRAWAL_AMOUNT,
            "FeeVault: withdrawal amount must be greater than minimum withdrawal amount"
        );

        uint256 value = address(this).balance;
        totalProcessed += value;

        emit Withdrawal(value, RECIPIENT, msg.sender);
        emit Withdrawal(value, RECIPIENT, msg.sender, WITHDRAWAL_NETWORK);

        if (WITHDRAWAL_NETWORK == Types.WithdrawalNetwork.L2) {
            (bool success,) = RECIPIENT.call{ value: value }("");
            require(success, "FeeVault: failed to send ETH to L2 fee recipient");
        }
    }
}

contract Mock_L2ToL1MessagePasser {
    uint256 public messageNonce;

    event MessagePassed(
        uint256 indexed nonce,
        address indexed sender,
        address indexed target,
        uint256 value,
        uint256 gasLimit,
        bytes data,
        bytes32 withdrawalHash
    );

    receive() external payable { }

    function initiateWithdrawal(address _target, uint256 _gasLimit, bytes memory _data) external payable {
        bytes32 withdrawalHash = keccak256(abi.encode(messageNonce, msg.sender, _target, msg.value, _gasLimit, _data));

        emit MessagePassed({
            nonce: messageNonce,
            sender: msg.sender,
            target: _target,
            value: msg.value,
            gasLimit: _gasLimit,
            data: _data,
            withdrawalHash: withdrawalHash
        });

        messageNonce++;
    }
}
