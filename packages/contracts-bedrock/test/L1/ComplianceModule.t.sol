// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { CommonTest } from "test/setup/CommonTest.sol";
import { MockPolicy, IComplianceModuleVerdicts } from "test/mocks/MockPolicy.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";

// Scripts
import { ForgeArtifacts, StorageSlot } from "scripts/libraries/ForgeArtifacts.sol";

// Contracts
import { ComplianceModule } from "src/L1/ComplianceModule.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";

// Libraries
import { Types } from "src/libraries/Types.sol";
import { Hashing } from "src/libraries/Hashing.sol";
import { Encoding } from "src/libraries/Encoding.sol";
import { Features } from "src/libraries/Features.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Asset, BridgeHookItem, Direction, Item } from "src/libraries/BridgeHookItem.sol";

// Interfaces
import { IBridgeHook } from "interfaces/universal/IBridgeHook.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { IStandardBridge } from "interfaces/universal/IStandardBridge.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { IAnchorStateRegistry } from "interfaces/dispute/IAnchorStateRegistry.sol";
import { IOptimismMintableERC20 } from "interfaces/universal/IOptimismMintableERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Timestamp } from "src/dispute/lib/Types.sol";

/// @title ComplianceModule_TestInit
/// @notice Brings up a chain with the BRIDGE_HOOK feature enabled and a ComplianceModule wired in
///         behind a proxy admin of its own, which is what the design requires: the key that can
///         upgrade the contract holding frozen value must not be the chain's.
abstract contract ComplianceModule_TestInit is CommonTest {
    ComplianceModule module;
    MockPolicy policy;
    TestERC20 token;
    address moduleOwner;
    ProxyAdmin moduleProxyAdmin;

    /// @notice A withdrawal's default gas limit in these tests. Generous, because the release path
    ///         forwards it to a real messenger relay.
    uint256 internal constant WITHDRAWAL_GAS_LIMIT = 500_000;

    function setUp() public virtual override {
        super.setUp();

        moduleOwner = makeAddr("moduleOwner");
        policy = new MockPolicy();
        token = new TestERC20();

        // The module lives behind a ProxyAdmin separate from the chain's, so chain governance
        // cannot upgrade the fund holder and defeat the arrangement.
        moduleProxyAdmin = new ProxyAdmin(moduleOwner);
        Proxy moduleProxy = new Proxy(address(moduleProxyAdmin));
        ComplianceModule impl = new ComplianceModule(
            optimismPortal2, l1StandardBridge, ICrossDomainMessenger(address(l1CrossDomainMessenger))
        );

        vm.prank(address(moduleProxyAdmin));
        moduleProxy.upgradeToAndCall(
            address(impl),
            abi.encodeCall(ComplianceModule.initialize, (address(policy)))
        );
        module = ComplianceModule(address(moduleProxy));
        policy.setModule(IComplianceModuleVerdicts(address(module)));

        // Enabling the feature is two acts by the same authority: the flag, then the address.
        vm.startPrank(proxyAdminOwner);
        systemConfig.setFeature(Features.BRIDGE_HOOK, true);
        optimismPortal2.setBridgeHook(IBridgeHook(address(module)));
        l1StandardBridge.setBridgeHook(IBridgeHook(address(module)));
        vm.stopPrank();
    }

    /// @notice The contract holding protocol-custodied ETH. The ETHLockbox when that feature is
    ///         on, the Portal itself otherwise, which is the shape this test setup runs in.
    function _ethCustodian() internal view returns (address) {
        if (systemConfig.isFeatureEnabled(Features.ETH_LOCKBOX) && address(ethLockbox) != address(0)) {
            return address(ethLockbox);
        }
        return address(optimismPortal2);
    }

    /// @notice Builds the item the Portal assigns for an ETH deposit.
    function _ethDepositItem(
        address _from,
        address _to,
        uint256 _amount,
        uint64 _gasLimit,
        bytes32 _uid
    )
        internal
        pure
        returns (Item memory)
    {
        return Item({
            direction: Direction.Deposit,
            asset: Asset.ETH,
            from: _from,
            aliased: false,
            to: _to,
            localToken: address(0),
            remoteToken: address(0),
            amount: _amount,
            value: 0,
            gasLimit: _gasLimit,
            isCreation: false,
            data: hex"",
            messageNonce: 0,
            uid: _uid
        });
    }

    /// @notice Builds the item the bridge assigns for a token item.
    function _erc20Item(
        Direction _direction,
        address _from,
        address _to,
        address _localToken,
        address _remoteToken,
        uint256 _amount,
        uint256 _gasLimit,
        bytes32 _uid
    )
        internal
        pure
        returns (Item memory)
    {
        return Item({
            direction: _direction,
            asset: Asset.ERC20,
            from: _from,
            aliased: false,
            to: _to,
            localToken: _localToken,
            remoteToken: _remoteToken,
            amount: _amount,
            value: 0,
            gasLimit: _gasLimit,
            isCreation: false,
            data: hex"",
            messageNonce: 0,
            uid: _uid
        });
    }

    /// @notice Builds the withdrawal a real ERC-20 bridge withdrawal produces: a zero-value
    ///         relayMessage envelope targeting the L1 messenger, carrying a finalizeBridgeERC20
    ///         for the bridge. Going through the Portal is what makes `currentWithdrawalHash`
    ///         available to the bridge.
    function _bridgedERC20Withdrawal(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount
    )
        internal
        view
        returns (Types.WithdrawalTransaction memory)
    {
        bytes memory inner = abi.encodeCall(
            IStandardBridge.finalizeBridgeERC20, (_localToken, _remoteToken, _from, _to, _amount, hex"")
        );
        bytes memory envelope = abi.encodeCall(
            ICrossDomainMessenger.relayMessage,
            (
                Encoding.encodeVersionedNonce(0, 1),
                Predeploys.L2_STANDARD_BRIDGE,
                address(l1StandardBridge),
                0,
                200_000,
                inner
            )
        );

        return Types.WithdrawalTransaction({
            nonce: 0,
            sender: Predeploys.L2_CROSS_DOMAIN_MESSENGER,
            target: address(l1CrossDomainMessenger),
            value: 0,
            gasLimit: WITHDRAWAL_GAS_LIMIT,
            data: envelope
        });
    }

    /// @notice The identifier of the item an ETH withdrawal produces. The withdrawal hash is the
    ///         item's uniqueness source rather than its identifier, so that the identifier still
    ///         binds every other field.
    function _ethWithdrawalId(Types.WithdrawalTransaction memory _tx) internal pure returns (bytes32) {
        return BridgeHookItem.hash(BridgeHookItem.fromWithdrawalTransaction(_tx, Hashing.hashWithdrawal(_tx)));
    }

    /// @notice Puts the bridge in the state a matching deposit would have left it in.
    function _seedBridgeEscrow(address _localToken, address _remoteToken, uint256 _amount) internal {
        TestERC20(_localToken).mint(address(l1StandardBridge), _amount);
        StorageSlot memory slot = ForgeArtifacts.getSlot("L1StandardBridge", "deposits");
        vm.store(
            address(l1StandardBridge),
            keccak256(abi.encode(_remoteToken, keccak256(abi.encode(_localToken, uint256(slot.slot))))),
            bytes32(_amount)
        );
    }

    /// @notice Marks a withdrawal proven and mature without going through the proof machinery, so
    ///         these tests exercise the hook rather than the trie.
    function _fakeProve(Types.WithdrawalTransaction memory _tx) internal returns (bytes32 hash_) {
        hash_ = Hashing.hashWithdrawal(_tx);

        address fakeGame = makeAddr("fakeGame");
        vm.mockCall(fakeGame, abi.encodeCall(IDisputeGame.createdAt, ()), abi.encode(Timestamp.wrap(uint64(1))));
        vm.mockCall(
            address(anchorStateRegistry),
            abi.encodeCall(IAnchorStateRegistry.isGameClaimValid, (IDisputeGame(fakeGame))),
            abi.encode(true)
        );

        // provenWithdrawals[hash][msg.sender] = { disputeGameProxy, timestamp }, packed into one
        // slot: a 20 byte address followed by a uint64.
        StorageSlot memory slot = ForgeArtifacts.getSlot("OptimismPortal2", "provenWithdrawals");
        bytes32 outer = keccak256(abi.encode(hash_, uint256(slot.slot)));
        bytes32 inner = keccak256(abi.encode(address(this), outer));
        vm.store(
            address(optimismPortal2),
            inner,
            bytes32((uint256(uint64(block.timestamp)) << 160) | uint256(uint160(fakeGame)))
        );

        vm.warp(block.timestamp + optimismPortal2.proofMaturityDelaySeconds() + 1);

        // Whichever contract holds protocol ETH has to be able to cover the payout.
        address custodian = _ethCustodian();
        vm.deal(custodian, custodian.balance + _tx.value);
    }

    /// @notice Builds the withdrawal a real ETH bridge withdrawal produces: a relayMessage
    ///         envelope targeting the L1 messenger, carrying a finalizeBridgeETH for the bridge.
    function _bridgedETHWithdrawal(
        address _from,
        address _to,
        uint256 _amount
    )
        internal
        view
        returns (Types.WithdrawalTransaction memory)
    {
        bytes memory inner = abi.encodeCall(IStandardBridge.finalizeBridgeETH, (_from, _to, _amount, hex""));
        bytes memory envelope = abi.encodeCall(
            ICrossDomainMessenger.relayMessage,
            (
                Encoding.encodeVersionedNonce(0, 1),
                Predeploys.L2_STANDARD_BRIDGE,
                address(l1StandardBridge),
                _amount,
                200_000,
                inner
            )
        );

        return Types.WithdrawalTransaction({
            nonce: 0,
            sender: Predeploys.L2_CROSS_DOMAIN_MESSENGER,
            target: address(l1CrossDomainMessenger),
            value: _amount,
            gasLimit: WITHDRAWAL_GAS_LIMIT,
            data: envelope
        });
    }

    /// @notice Finalizes a token withdrawal as the messenger would.
    function _finalizeERC20Withdrawal(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount
    )
        internal
    {
        vm.mockCall(
            address(l1CrossDomainMessenger),
            abi.encodeCall(ICrossDomainMessenger.xDomainMessageSender, ()),
            abi.encode(address(l2StandardBridge))
        );
        vm.prank(address(l1CrossDomainMessenger));
        l1StandardBridge.finalizeBridgeERC20(_localToken, _remoteToken, _from, _to, _amount, hex"");
    }
}

/// @title ComplianceModule_ETHDeposit_Test
/// @notice Covers the ETH deposit path: hold, verdict, completion.
contract ComplianceModule_ETHDeposit_Test is ComplianceModule_TestInit {
    /// @notice A held deposit locks nothing, emits no TransactionDeposited, and leaves the ETH
    ///         with the module rather than the lockbox.
    function test_ethDeposit_held_succeeds() external {
        uint256 amount = 1 ether;
        uint256 custodyBefore = _ethCustodian().balance;

        Item memory item = _ethDepositItem(alice, bob, amount, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");

        assertEq(address(module).balance, amount, "module should hold the ETH");
        assertEq(_ethCustodian().balance, custodyBefore, "protocol custody must not be touched on a hold");
        assertTrue(optimismPortal2.pendingDeposits(id), "Portal should have committed to the terms");

        (uint64 heldAt, uint64 clearedAt) = module.items(id);
        assertGt(heldAt, 0, "item should be held");
        assertEq(clearedAt, 0, "item should not be cleared");
    }

    /// @notice A cleared deposit completes to exactly the terms submitted, permissionlessly, and
    ///         only then does the ETH reach the lockbox.
    function test_ethDeposit_completeAfterVerdict_succeeds() external {
        uint256 amount = 1 ether;
        uint256 custodyBefore = _ethCustodian().balance;

        Item memory item = _ethDepositItem(alice, bob, amount, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");

        policy.clear(id);

        // Anyone can complete. The caller chooses only which item moves.
        vm.prank(makeAddr("randomCaller"));
        module.completeDeposit(item);

        assertEq(address(module).balance, 0, "module should have returned the ETH");
        assertEq(_ethCustodian().balance, custodyBefore + amount, "protocol custody should hold the ETH now");
        assertFalse(optimismPortal2.pendingDeposits(id), "commitment should be consumed");

        (uint64 heldAt,) = module.items(id);
        assertEq(heldAt, 0, "record should be deleted");
    }

    /// @notice An item cannot complete twice.
    function test_ethDeposit_completeTwice_reverts() external {
        uint256 amount = 1 ether;
        Item memory item = _ethDepositItem(alice, bob, amount, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");
        policy.clear(id);
        module.completeDeposit(item);

        vm.expectRevert(ComplianceModule.ComplianceModule_NotHeld.selector);
        module.completeDeposit(item);
    }

    /// @notice Value never moves out of a hold without a recorded clearance.
    function test_ethDeposit_completeWithoutVerdict_reverts() external {
        uint256 amount = 1 ether;
        Item memory item = _ethDepositItem(alice, bob, amount, 100_000, bytes32(0));

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");

        vm.expectRevert(ComplianceModule.ComplianceModule_NotCleared.selector);
        module.completeDeposit(item);
    }

    /// @notice An on-chain deny beats a prior clearance, because the policy is consulted again at
    ///         the moment value moves.
    function test_ethDeposit_denyBeatsPriorClearance_reverts() external {
        uint256 amount = 1 ether;
        Item memory item = _ethDepositItem(alice, bob, amount, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");
        policy.clear(id);

        policy.setDenied(bob, true);

        vm.expectRevert(ComplianceModule.ComplianceModule_ReleaseDeclined.selector);
        module.completeDeposit(item);
    }

    /// @notice A passing policy leaves the deposit path exactly as it is on a stock chain.
    function test_ethDeposit_policyPasses_behavesAsStock() external {
        policy.setPassDeposits(true);

        uint256 amount = 1 ether;
        uint256 custodyBefore = _ethCustodian().balance;

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");

        assertEq(address(module).balance, 0, "module should keep nothing");
        assertEq(_ethCustodian().balance, custodyBefore + amount, "ETH should be taken into custody as usual");
    }

    /// @notice A policy revert rejects the deposit and unwinds the whole transaction, so the user
    ///         keeps their ETH.
    function test_ethDeposit_policyReverts_rejectsDeposit() external {
        policy.setRejectDeposits(true);

        uint256 balanceBefore = alice.balance;

        vm.prank(alice, alice);
        vm.expectRevert(MockPolicy.MockPolicy_Rejected.selector);
        optimismPortal2.depositTransaction{ value: 1 ether }(bob, 0, 100_000, false, hex"");

        assertEq(alice.balance, balanceBefore, "user should keep their ETH");
    }

    /// @notice A deposit carrying no value is screened like any other. This is the force-inclusion
    ///         path, so exempting it would leave arbitrary L2 execution unscreened.
    function test_ethDeposit_zeroValue_isHeld() external {
        Item memory item = _ethDepositItem(alice, bob, 0, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: 0 }(bob, 0, 100_000, false, hex"");

        assertEq(optimismPortal2.depositNonce(), 1, "an identifier should have been assigned");
        assertTrue(optimismPortal2.pendingDeposits(id), "Portal should have committed to the terms");

        (uint64 heldAt,) = module.items(id);
        assertGt(heldAt, 0, "the item should be held");
    }

    /// @notice A held zero-value deposit completes with a zero mint, so the L2 effect is deferred
    ///         rather than frozen. There was never any custody involved.
    function test_ethDeposit_zeroValue_completes() external {
        Item memory item = _ethDepositItem(alice, bob, 0, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: 0 }(bob, 0, 100_000, false, hex"");

        policy.clear(id);
        module.completeDeposit(item);

        assertFalse(optimismPortal2.pendingDeposits(id), "the commitment should be consumed");
    }

    /// @notice A payload shaped like a messenger envelope, submitted directly, does not get the
    ///         bridge exemption and does not get to name its own parties either.
    function test_ethDeposit_forgedBridgeEnvelope_isStillScreened() external {
        bytes memory inner = abi.encodeCall(
            IStandardBridge.finalizeBridgeERC20,
            (address(token), makeAddr("remote"), makeAddr("cleanFrom"), makeAddr("cleanTo"), 1e18, hex"")
        );
        bytes memory envelope = abi.encodeCall(
            ICrossDomainMessenger.relayMessage,
            (
                Encoding.encodeVersionedNonce(0, 1),
                address(l1StandardBridge),
                Predeploys.L2_STANDARD_BRIDGE,
                0,
                200_000,
                inner
            )
        );

        // Denying the real submitter is what the forgery would be trying to escape.
        policy.setDenied(alice, true);
        policy.setPassDeposits(true);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: 0 }(
            Predeploys.L2_CROSS_DOMAIN_MESSENGER, 0, 200_000, false, envelope
        );

        // The policy saw alice rather than the fabricated parties, so it held the item instead of
        // passing it.
        assertEq(optimismPortal2.depositNonce(), 1, "the item should have been screened");

        Item memory item = Item({
            direction: Direction.Deposit,
            asset: Asset.ETH,
            from: alice,
            aliased: false,
            to: Predeploys.L2_CROSS_DOMAIN_MESSENGER,
            localToken: address(0),
            remoteToken: address(0),
            amount: 0,
            value: 0,
            gasLimit: 200_000,
            isCreation: false,
            data: envelope,
            messageNonce: 0,
            uid: bytes32(0)
        });
        assertTrue(optimismPortal2.pendingDeposits(BridgeHookItem.hash(item)), "the forgery should be held");
    }
}

/// @title ComplianceModule_UnbackedIssuance_Test
/// @notice The highest-severity failure the terms commitments exist to close. These exercise the
///         Portal directly, standing in for a compromised or upgraded module.
contract ComplianceModule_UnbackedIssuance_Test is ComplianceModule_TestInit {
    /// @notice A mint cannot be emitted for more ETH than was actually returned.
    function test_completeDepositTransaction_valueBelowCommitment_reverts() external {
        uint256 amount = 1 ether;
        Item memory item = _ethDepositItem(alice, bob, amount, 100_000, bytes32(0));

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");

        vm.deal(address(module), amount);
        vm.prank(address(module));
        vm.expectRevert(abi.encodeWithSignature("OptimismPortal_ItemValueMismatch()"));
        optimismPortal2.completeDepositTransaction{ value: amount - 1 }(item);
    }

    /// @notice Terms the Portal never committed to cannot be completed at all, which is what stops
    ///         a forged sender, a redirected recipient or an invented item.
    function test_completeDepositTransaction_uncommittedTerms_reverts() external {
        Item memory forged = _ethDepositItem(alice, bob, 1 ether, 100_000, bytes32(0));

        vm.deal(address(module), 1 ether);
        vm.prank(address(module));
        vm.expectRevert(abi.encodeWithSignature("OptimismPortal_UncommittedItem()"));
        optimismPortal2.completeDepositTransaction{ value: 1 ether }(forged);
    }

    /// @notice The sender is the one the Portal derived and nothing else. Altering it produces a
    ///         different identifier, which no commitment matches.
    function test_completeDepositTransaction_forgedSender_reverts() external {
        uint256 amount = 1 ether;

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");

        Item memory forged = _ethDepositItem(makeAddr("mallory"), bob, amount, 100_000, bytes32(0));

        vm.deal(address(module), amount);
        vm.prank(address(module));
        vm.expectRevert(abi.encodeWithSignature("OptimismPortal_UncommittedItem()"));
        optimismPortal2.completeDepositTransaction{ value: amount }(forged);
    }

    /// @notice Only the hook can reach the completion entry point.
    function test_completeDepositTransaction_notHook_reverts() external {
        Item memory item = _ethDepositItem(alice, bob, 1 ether, 100_000, bytes32(0));

        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSignature("OptimismPortal_NotBridgeHook()"));
        optimismPortal2.completeDepositTransaction{ value: 1 ether }(item);
    }
}

/// @title ComplianceModule_ERC20Deposit_Test
/// @notice Covers the token deposit path, where the binding constraint is accounting.
contract ComplianceModule_ERC20Deposit_Test is ComplianceModule_TestInit {
    /// @notice A held token deposit never touches `deposits`, so bridge accounting stays exactly
    ///         correct for every clean user even while other value is frozen.
    function test_erc20Deposit_held_leavesAccountingUntouched() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");

        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(l1StandardBridge), amount);

        vm.prank(alice, alice);
        l1StandardBridge.depositERC20To(address(token), remote, bob, amount, 100_000, hex"");

        assertEq(token.balanceOf(address(module)), amount, "module should hold the tokens");
        assertEq(token.balanceOf(address(l1StandardBridge)), 0, "bridge should hold nothing");
        assertEq(l1StandardBridge.deposits(address(token), remote), 0, "deposits must not be incremented");
    }

    /// @notice On completion the escrow and the message are recorded for the first time, for the
    ///         amount that actually arrived.
    function test_erc20Deposit_completeAfterVerdict_succeeds() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");

        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(l1StandardBridge), amount);

        Item memory item = _erc20Item(Direction.Deposit, alice, bob, address(token), remote, amount, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        vm.prank(alice, alice);
        l1StandardBridge.depositERC20To(address(token), remote, bob, amount, 100_000, hex"");

        policy.clear(id);
        module.completeDeposit(item);

        assertEq(token.balanceOf(address(module)), 0, "module should have returned the tokens");
        assertEq(token.balanceOf(address(l1StandardBridge)), amount, "bridge should escrow the tokens now");
        assertEq(l1StandardBridge.deposits(address(token), remote), amount, "deposits should count the item once");
        assertFalse(l1StandardBridge.pendingERC20Deposits(id), "commitment should be consumed");
    }

    /// @notice A token deposit whose local token is an OptimismMintableERC20 is held rather than
    ///         burned, so flagged value native to L2 is frozen like anything else. The burn is
    ///         deferred until the deposit is known to be proceeding.
    function test_erc20Deposit_mintableToken_heldNotBurned() external {
        address remote = makeAddr("remoteMintable");
        IOptimismMintableERC20 mintable = IOptimismMintableERC20(
            l1OptimismMintableERC20Factory.createOptimismMintableERC20(remote, "Mintable", "MNT")
        );

        uint256 amount = 50e18;
        vm.prank(address(l1StandardBridge));
        mintable.mint(alice, amount);

        vm.prank(alice);
        IERC20(address(mintable)).approve(address(l1StandardBridge), amount);

        Item memory item =
            _erc20Item(Direction.Deposit, alice, bob, address(mintable), remote, amount, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        uint256 supplyBefore = IERC20(address(mintable)).totalSupply();

        vm.prank(alice, alice);
        l1StandardBridge.depositERC20To(address(mintable), remote, bob, amount, 100_000, hex"");

        assertEq(IERC20(address(mintable)).balanceOf(address(module)), amount, "module should hold the tokens");
        assertEq(IERC20(address(mintable)).totalSupply(), supplyBefore, "nothing should have been burned yet");

        policy.clear(id);
        module.completeDeposit(item);

        assertEq(IERC20(address(mintable)).balanceOf(address(module)), 0, "module should have returned them");
        assertEq(IERC20(address(mintable)).totalSupply(), supplyBefore - amount, "the burn happens at completion");

        // This branch burns straight out of the module rather than pulling, so the allowance is
        // never consumed and has to be cleared rather than left standing.
        assertEq(
            IERC20(address(mintable)).allowance(address(module), address(l1StandardBridge)),
            0,
            "no allowance should be left behind"
        );
    }

    /// @notice One economic event produces exactly one verdict. The message the bridge sends
    ///         reaches the Portal and would be screened a second time without the origin check.
    function test_erc20Deposit_passing_screenedExactlyOnce() external {
        policy.setPassDeposits(true);

        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");

        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(l1StandardBridge), amount);

        vm.prank(alice, alice);
        l1StandardBridge.depositERC20To(address(token), remote, bob, amount, 100_000, hex"");

        assertEq(policy.screenCalls(), 1, "the bridge envelope should not be screened again");
        assertEq(l1StandardBridge.deposits(address(token), remote), amount, "the deposit should have gone through");
    }

    /// @notice Completing a held token deposit also sends a message through the Portal, and that
    ///         one carries no second verdict either.
    function test_erc20Deposit_completion_screenedExactlyOnce() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");

        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(l1StandardBridge), amount);

        Item memory item = _erc20Item(Direction.Deposit, alice, bob, address(token), remote, amount, 100_000, bytes32(0));

        vm.prank(alice, alice);
        l1StandardBridge.depositERC20To(address(token), remote, bob, amount, 100_000, hex"");
        assertEq(policy.screenCalls(), 1, "one verdict at submission");

        policy.clear(BridgeHookItem.hash(item));
        module.completeDeposit(item);

        assertEq(policy.screenCalls(), 1, "completion should not produce a second verdict");
        assertEq(l1StandardBridge.deposits(address(token), remote), amount, "escrow recorded once");
    }

    /// @notice A mintable token deposit needs no approval, exactly as on a stock chain, because
    ///         `burn` is `onlyBridge` and takes no allowance. Holding must not change that.
    function test_erc20Deposit_mintableToken_needsNoApproval() external {
        address remote = makeAddr("remoteMintable");
        IOptimismMintableERC20 mintable = IOptimismMintableERC20(
            l1OptimismMintableERC20Factory.createOptimismMintableERC20(remote, "Mintable", "MNT")
        );

        uint256 amount = 50e18;
        vm.prank(address(l1StandardBridge));
        mintable.mint(alice, amount);

        // No approve() anywhere. This is the call an existing integration would make.
        vm.prank(alice, alice);
        l1StandardBridge.depositERC20To(address(mintable), remote, bob, amount, 100_000, hex"");

        assertEq(IERC20(address(mintable)).balanceOf(address(module)), amount, "the module should hold the tokens");
        assertEq(IERC20(address(mintable)).balanceOf(alice), 0, "the depositor's tokens should be gone");
    }

    /// @notice Only the hook can reach the token completion entry point.
    function test_completeERC20Deposit_notHook_reverts() external {
        Item memory item =
            _erc20Item(Direction.Deposit, alice, bob, address(token), makeAddr("remote"), 1e18, 100_000, bytes32(0));

        vm.expectRevert(abi.encodeWithSignature("StandardBridge_NotBridgeHook()"));
        l1StandardBridge.completeERC20Deposit(item);
    }

    /// @notice A substituted remote token does not match any commitment, so it cannot inflate a
    ///         pairing nobody escrowed against.
    function test_completeERC20Deposit_substitutedRemoteToken_reverts() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");

        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(l1StandardBridge), amount);

        vm.prank(alice, alice);
        l1StandardBridge.depositERC20To(address(token), remote, bob, amount, 100_000, hex"");

        Item memory forged =
            _erc20Item(Direction.Deposit, alice, bob, address(token), makeAddr("otherRemote"), amount, 100_000, bytes32(0));

        vm.prank(address(module));
        vm.expectRevert(abi.encodeWithSignature("StandardBridge_UncommittedItem()"));
        l1StandardBridge.completeERC20Deposit(forged);
    }
}

/// @title ComplianceModule_ETHWithdrawal_Test
/// @notice Covers the ETH withdrawal path, including the release back through the Portal that the
///         messenger's own sender check forces.
contract ComplianceModule_ETHWithdrawal_Test is ComplianceModule_TestInit {
    /// @notice A not-cleared withdrawal finalizes into holding rather than reverting, which is
    ///         what takes the value out of protocol custody.
    /// @notice The mirror of the token case: on the Portal leg a reverting policy is allowed to
    ///         reach the caller, because there the failure unwinds the whole finalization.
    /// @dev    Nothing is consumed, so the withdrawal stays finalizable once a policy answers. That
    ///         is why the absorption is scoped to the bridge leg and not applied here.
    function test_ethWithdrawal_policyReverts_unwindsAndConsumesNothing() external {
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, 1 ether);
        bytes32 hash = _fakeProve(wtx);

        policy.setRejectReleases(true);

        vm.expectRevert(MockPolicy.MockPolicy_Rejected.selector);
        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertFalse(optimismPortal2.finalizedWithdrawals(hash), "the withdrawal must not be consumed");
        assertEq(address(module).balance, 0, "nothing should have been held");

        // And it still finalizes once the policy stops reverting.
        policy.setRejectReleases(false);
        optimismPortal2.finalizeWithdrawalTransaction(wtx);
        assertTrue(optimismPortal2.finalizedWithdrawals(hash), "finalizable afterwards");
    }

    function test_ethWithdrawal_finalizesIntoHolding_succeeds() external {
        uint256 amount = 1 ether;
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, amount);
        bytes32 hash = _fakeProve(wtx);

        uint256 recipientBefore = bob.balance;

        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertTrue(optimismPortal2.finalizedWithdrawals(hash), "the withdrawal is consumed either way");
        assertTrue(optimismPortal2.heldWithdrawals(_ethWithdrawalId(wtx)), "Portal should have committed to the held terms");
        assertEq(address(module).balance, amount, "module should hold the ETH");
        assertEq(bob.balance, recipientBefore, "recipient should not have been paid");

        (uint64 heldAt,) = module.items(_ethWithdrawalId(wtx));
        assertGt(heldAt, 0, "item should be held");
    }

    /// @notice A cleared withdrawal releases to its original recipient, through the Portal and the
    ///         messenger, exactly as a stock finalization would have paid.
    function test_ethWithdrawal_releaseAfterVerdict_succeeds() external {
        uint256 amount = 1 ether;
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, amount);
        _fakeProve(wtx);

        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        policy.clear(_ethWithdrawalId(wtx));

        uint256 recipientBefore = bob.balance;
        Item memory item = BridgeHookItem.fromWithdrawalTransaction(wtx, Hashing.hashWithdrawal(wtx));

        vm.prank(makeAddr("randomCaller"));
        module.releaseWithdrawal(item);

        assertEq(bob.balance, recipientBefore + amount, "recipient should be paid the full amount");
        assertEq(address(module).balance, 0, "module should hold nothing");
        assertFalse(optimismPortal2.heldWithdrawals(_ethWithdrawalId(wtx)), "commitment should be consumed");
    }

    /// @notice The effective parties are the user and the recipient, not the two messengers and
    ///         the two bridges the value actually travelled through.
    function test_ethWithdrawal_effectiveParties_resolvesThroughEnvelope() external view {
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, 1 ether);
        Item memory item = BridgeHookItem.fromWithdrawalTransaction(wtx, Hashing.hashWithdrawal(wtx));

        address[] memory parties = module.effectiveParties(item);
        assertEq(parties[0], alice, "sender should be the user, not the L2 messenger");
        assertEq(parties[1], bob, "recipient should be the user, not the L1 bridge");
    }

    /// @notice A clearance recorded during the challenge window lets the withdrawal finalize
    ///         normally, with no extra user signature and nothing held.
    function test_ethWithdrawal_clearedDuringWindow_paysDirectly() external {
        uint256 amount = 1 ether;
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, amount);
        _fakeProve(wtx);

        policy.clear(_ethWithdrawalId(wtx));

        uint256 recipientBefore = bob.balance;
        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertEq(bob.balance, recipientBefore + amount, "recipient should be paid at finalization");
        assertFalse(optimismPortal2.heldWithdrawals(_ethWithdrawalId(wtx)), "nothing should have been held");
        assertEq(address(module).balance, 0, "module should hold nothing");
    }

    /// @notice The module is never a route for value the guardian has frozen.
    function test_ethWithdrawal_releaseWhilePaused_reverts() external {
        uint256 amount = 1 ether;
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, amount);
        _fakeProve(wtx);

        optimismPortal2.finalizeWithdrawalTransaction(wtx);
        policy.clear(_ethWithdrawalId(wtx));

        vm.prank(superchainConfig.guardian());
        superchainConfig.pause(address(0));

        Item memory item = BridgeHookItem.fromWithdrawalTransaction(wtx, Hashing.hashWithdrawal(wtx));
        vm.expectRevert(ComplianceModule.ComplianceModule_Paused.selector);
        module.releaseWithdrawal(item);
    }

    /// @notice Only the hook can reach the release entry point.
    function test_completeWithdrawalTransaction_notHook_reverts() external {
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, 1 ether);

        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSignature("OptimismPortal_NotBridgeHook()"));
        optimismPortal2.completeWithdrawalTransaction{ value: 1 ether }(wtx);
    }

    /// @notice A withdrawal the Portal never held cannot be released.
    function test_completeWithdrawalTransaction_uncommitted_reverts() external {
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, 1 ether);

        vm.deal(address(module), 1 ether);
        vm.prank(address(module));
        vm.expectRevert(abi.encodeWithSignature("OptimismPortal_UncommittedItem()"));
        optimismPortal2.completeWithdrawalTransaction{ value: 1 ether }(wtx);
    }
}

/// @title ComplianceModule_ERC20Withdrawal_Test
/// @notice Covers the token withdrawal path, where the recipient-facing leg has to stay with the
///         bridge.
contract ComplianceModule_ERC20Withdrawal_Test is ComplianceModule_TestInit {
    /// @notice A policy that reverts at the value-moving step cannot reject a token withdrawal. It
    ///         is absorbed into a hold instead.
    /// @dev    This is the rule the design already states, enforced rather than left to the
    ///         policy's discipline: a withdrawal has no sender to return value to, so rejection has
    ///         nothing it could mean. What a revert would actually do here is fail inside
    ///         `finalizeBridgeERC20`, which the messenger swallows into a failed message rather
    ///         than bubbling. The Portal has already marked the withdrawal finalized by then, so
    ///         the tokens would sit in the bridge with no held record naming them.
    function test_erc20Withdrawal_policyReverts_isHeldNotRejected() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");

        token.mint(address(l1StandardBridge), amount);
        StorageSlot memory slot = ForgeArtifacts.getSlot("L1StandardBridge", "deposits");
        vm.store(
            address(l1StandardBridge),
            keccak256(abi.encode(remote, keccak256(abi.encode(address(token), uint256(slot.slot))))),
            bytes32(amount)
        );

        policy.setRejectReleases(true);

        // Must not revert: the relay would swallow it and the withdrawal is already consumed.
        _finalizeERC20Withdrawal(address(token), remote, alice, bob, amount);

        assertEq(token.balanceOf(address(module)), amount, "the tokens should have reached the module");
        assertEq(token.balanceOf(address(l1StandardBridge)), 0, "nothing should be left stranded in the bridge");
        assertEq(token.balanceOf(bob), 0, "the recipient should not have been paid");
    }

    /// @notice A held token withdrawal decrements `deposits` when the tokens leave the bridge, and
    ///         pays nobody.
    function test_erc20Withdrawal_held_succeeds() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");

        // Put the bridge in the state a matching deposit would have left it in.
        token.mint(address(l1StandardBridge), amount);
        StorageSlot memory slot = ForgeArtifacts.getSlot("L1StandardBridge", "deposits");
        vm.store(
            address(l1StandardBridge),
            keccak256(abi.encode(remote, keccak256(abi.encode(address(token), uint256(slot.slot))))),
            bytes32(amount)
        );

        _finalizeERC20Withdrawal(address(token), remote, alice, bob, amount);

        assertEq(token.balanceOf(address(module)), amount, "module should hold the tokens");
        assertEq(token.balanceOf(bob), 0, "recipient should not have been paid");
        assertEq(l1StandardBridge.deposits(address(token), remote), 0, "deposits should be decremented on the hold");
    }

    /// @notice The release pays the recipient from the bridge, which is the address the token and
    ///         the receiver expect to see as msg.sender, and does not touch `deposits` again.
    function test_erc20Withdrawal_releaseAfterVerdict_succeeds() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");

        token.mint(address(l1StandardBridge), amount);
        StorageSlot memory slot = ForgeArtifacts.getSlot("L1StandardBridge", "deposits");
        vm.store(
            address(l1StandardBridge),
            keccak256(abi.encode(remote, keccak256(abi.encode(address(token), uint256(slot.slot))))),
            bytes32(amount)
        );

        Item memory item = _erc20Item(Direction.Withdrawal, alice, bob, address(token), remote, amount, 0, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        _finalizeERC20Withdrawal(address(token), remote, alice, bob, amount);

        policy.clear(id);
        module.releaseWithdrawal(item);

        assertEq(token.balanceOf(bob), amount, "recipient should be paid");
        assertEq(token.balanceOf(address(module)), 0, "module should hold nothing");
        assertEq(l1StandardBridge.deposits(address(token), remote), 0, "deposits must not move again at release");
        assertFalse(l1StandardBridge.heldERC20Withdrawals(id), "commitment should be consumed");
    }

    /// @notice The bridge's own release leg is pause-gated, not only the module's check, so the
    ///         perimeter holds even if the hook is upgraded to stop looking.
    function test_completeERC20Withdrawal_whilePaused_reverts() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");

        token.mint(address(l1StandardBridge), amount);
        StorageSlot memory slot = ForgeArtifacts.getSlot("L1StandardBridge", "deposits");
        vm.store(
            address(l1StandardBridge),
            keccak256(abi.encode(remote, keccak256(abi.encode(address(token), uint256(slot.slot))))),
            bytes32(amount)
        );

        Item memory item = _erc20Item(Direction.Withdrawal, alice, bob, address(token), remote, amount, 0, bytes32(0));
        _finalizeERC20Withdrawal(address(token), remote, alice, bob, amount);

        vm.prank(superchainConfig.guardian());
        superchainConfig.pause(address(0));

        // Called as the hook, so this bypasses the module's own pause check entirely.
        vm.prank(address(module));
        vm.expectRevert("StandardBridge: paused");
        l1StandardBridge.completeERC20Withdrawal(item);
    }

    /// @notice A token native to L2 is minted straight to the module on a hold, because nothing
    ///         exists to take custody of until the bridge creates it.
    function test_erc20Withdrawal_mintableToken_mintsToModule() external {
        address remote = makeAddr("remoteMintable");
        IOptimismMintableERC20 mintable = IOptimismMintableERC20(
            l1OptimismMintableERC20Factory.createOptimismMintableERC20(remote, "Mintable", "MNT")
        );

        uint256 amount = 50e18;
        Item memory item =
            _erc20Item(Direction.Withdrawal, alice, bob, address(mintable), remote, amount, 0, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        _finalizeERC20Withdrawal(address(mintable), remote, alice, bob, amount);

        assertEq(IERC20(address(mintable)).balanceOf(address(module)), amount, "module should hold the mint");
        assertEq(IERC20(address(mintable)).balanceOf(bob), 0, "recipient should not have been paid");

        policy.clear(id);
        module.releaseWithdrawal(item);

        assertEq(IERC20(address(mintable)).balanceOf(bob), amount, "recipient should be paid at release");
        assertEq(IERC20(address(mintable)).balanceOf(address(module)), 0, "module should hold nothing");
    }
}

/// @title ComplianceModule_ERC20WithdrawalPreClearance_Test
/// @notice The capability the withdrawal hash buys: a token withdrawal screened during the
///         challenge window pays out at finalization, in one transaction, exactly as ETH does.
contract ComplianceModule_ERC20WithdrawalPreClearance_Test is ComplianceModule_TestInit {
    /// @notice A token withdrawal cleared during the window is never held.
    /// @dev The service can compute this identifier the moment the withdrawal is initiated on L2,
    ///      because it is derived from the withdrawal's own hash rather than from a counter the
    ///      bridge mints at finalization time.
    function test_erc20Withdrawal_clearedDuringWindow_paysDirectly() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");
        _seedBridgeEscrow(address(token), remote, amount);

        Types.WithdrawalTransaction memory wtx = _bridgedERC20Withdrawal(address(token), remote, alice, bob, amount);
        bytes32 withdrawalHash = _fakeProve(wtx);

        // The verdict is recorded against the item the bridge will build, days before anyone
        // finalizes.
        Item memory item =
            _erc20Item(Direction.Withdrawal, alice, bob, address(token), remote, amount, 0, withdrawalHash);
        policy.clear(BridgeHookItem.hash(item));

        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertEq(token.balanceOf(bob), amount, "recipient should be paid at finalization");
        assertEq(token.balanceOf(address(module)), 0, "nothing should have been held");
        assertEq(l1StandardBridge.deposits(address(token), remote), 0, "escrow should be released as usual");
    }

    /// @notice Without a verdict the same withdrawal finalizes into holding, and the identifier is
    ///         the same one the service would have cleared.
    function test_erc20Withdrawal_notCleared_holdsUnderTheSameId() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");
        _seedBridgeEscrow(address(token), remote, amount);

        Types.WithdrawalTransaction memory wtx = _bridgedERC20Withdrawal(address(token), remote, alice, bob, amount);
        bytes32 withdrawalHash = _fakeProve(wtx);

        Item memory item =
            _erc20Item(Direction.Withdrawal, alice, bob, address(token), remote, amount, 0, withdrawalHash);
        bytes32 id = BridgeHookItem.hash(item);

        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertEq(token.balanceOf(address(module)), amount, "module should hold the tokens");
        assertTrue(l1StandardBridge.heldERC20Withdrawals(id), "bridge should have committed under the withdrawal hash");

        // A verdict arriving late releases it under that same identifier.
        policy.clear(id);
        module.releaseWithdrawal(item);

        assertEq(token.balanceOf(bob), amount, "recipient should be paid at release");
    }
}

/// @title ComplianceModule_TermBinding_Test
/// @notice The identifier has to bind every field, not just be unique. These are the cases that
///         break if it carries a protocol hash rather than containing one.
contract ComplianceModule_TermBinding_Test is ComplianceModule_TestInit {
    /// @notice Sets up one held, cleared token withdrawal and returns its item.
    function _heldAndClearedWithdrawal(uint256 _amount, address _remote) internal returns (Item memory item_) {
        _seedBridgeEscrow(address(token), _remote, _amount);
        item_ = _erc20Item(Direction.Withdrawal, alice, bob, address(token), _remote, _amount, 0, bytes32(0));
        _finalizeERC20Withdrawal(address(token), _remote, alice, bob, _amount);
        policy.clear(BridgeHookItem.hash(item_));
    }

    /// @notice A cleared item cannot be redirected to another recipient.
    function test_releaseWithdrawal_redirectedRecipient_reverts() external {
        address remote = makeAddr("remoteToken");
        Item memory item = _heldAndClearedWithdrawal(100e18, remote);

        item.to = makeAddr("mallory");

        vm.expectRevert(ComplianceModule.ComplianceModule_NotHeld.selector);
        module.releaseWithdrawal(item);
    }

    /// @notice A cleared item cannot be inflated to drain what the module holds for other items.
    function test_releaseWithdrawal_inflatedAmount_reverts() external {
        address remote = makeAddr("remoteToken");
        Item memory item = _heldAndClearedWithdrawal(100e18, remote);

        // Give the module more of the same token, as a second held item would.
        token.mint(address(module), 500e18);
        item.amount = 600e18;

        vm.expectRevert(ComplianceModule.ComplianceModule_NotHeld.selector);
        module.releaseWithdrawal(item);
    }

    /// @notice A cleared item cannot be repointed at a different token.
    function test_releaseWithdrawal_substitutedToken_reverts() external {
        address remote = makeAddr("remoteToken");
        Item memory item = _heldAndClearedWithdrawal(100e18, remote);

        TestERC20 other = new TestERC20();
        other.mint(address(module), 100e18);
        item.localToken = address(other);

        vm.expectRevert(ComplianceModule.ComplianceModule_NotHeld.selector);
        module.releaseWithdrawal(item);
    }
}

/// @title ComplianceModule_Access_Test
/// @notice Covers the module's authorisation surface, which is deliberately tiny.
contract ComplianceModule_Access_Test is ComplianceModule_TestInit {
    /// @notice Verdicts are policy-only. There is no screening-service role, no officer role and
    ///         no list writer in the module.
    function test_recordVerdict_notPolicy_reverts() external {
        vm.expectRevert(ComplianceModule.ComplianceModule_NotPolicy.selector);
        module.recordVerdict(bytes32(uint256(1)));
    }

    /// @notice The hook functions are reachable only from the call site that owns the asset class.
    function test_screenDeposit_notCallSite_reverts() external {
        Item memory item = _ethDepositItem(alice, bob, 1 ether, 100_000, bytes32(0));

        vm.expectRevert(ComplianceModule.ComplianceModule_NotCallSite.selector);
        module.screenDeposit(item);
    }

    /// @notice ETH is always screened at the Portal and tokens always at the bridge, so the bridge
    ///         cannot present an ETH item.
    function test_screenDeposit_wrongCallSiteForAsset_reverts() external {
        Item memory item = _ethDepositItem(alice, bob, 1 ether, 100_000, bytes32(0));

        vm.prank(address(l1StandardBridge));
        vm.expectRevert(ComplianceModule.ComplianceModule_NotCallSite.selector);
        module.screenDeposit(item);
    }

    /// @notice The module refuses to record custody of value it did not receive, rather than
    ///         taking the call site's word for it.
    function test_holdDeposit_valueBelowItem_reverts() external {
        Item memory item = _ethDepositItem(alice, bob, 1 ether, 100_000, bytes32(0));

        vm.deal(address(optimismPortal2), address(optimismPortal2).balance + 1 ether);
        vm.prank(address(optimismPortal2));
        vm.expectRevert(ComplianceModule.ComplianceModule_ValueMismatch.selector);
        module.holdDeposit{ value: 0.5 ether }(item);
    }

    /// @notice Same on the withdrawal custody handover.
    function test_holdWithdrawal_valueBelowItem_reverts() external {
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, 1 ether);
        Item memory item = BridgeHookItem.fromWithdrawalTransaction(wtx, Hashing.hashWithdrawal(wtx));

        vm.deal(address(optimismPortal2), address(optimismPortal2).balance + 1 ether);
        vm.prank(address(optimismPortal2));
        vm.expectRevert(ComplianceModule.ComplianceModule_ValueMismatch.selector);
        module.holdWithdrawal{ value: 0.5 ether }(item);
    }

    /// @notice A token item must arrive with no ETH attached.
    function test_holdDeposit_ethOnTokenItem_reverts() external {
        Item memory item =
            _erc20Item(Direction.Deposit, alice, bob, address(token), makeAddr("remote"), 1e18, 100_000, bytes32(0));

        vm.deal(address(l1StandardBridge), address(l1StandardBridge).balance + 1 ether);
        vm.prank(address(l1StandardBridge));
        vm.expectRevert(ComplianceModule.ComplianceModule_ValueMismatch.selector);
        module.holdDeposit{ value: 1 ether }(item);
    }

    /// @notice The policy pointer is gated at the upgrade authority and nothing weaker, because a
    ///         permissive policy is indistinguishable in effect from an upgrade that stops
    ///         screening.
    function test_setPolicy_notUpgradeKey_reverts() external {
        vm.prank(proxyAdminOwner);
        vm.expectRevert(abi.encodeWithSignature("ProxyAdminOwnedBase_NotProxyAdminOwner()"));
        module.setPolicy(makeAddr("newPolicy"));
    }

    /// @notice The module's own upgrade key can repoint the policy.
    function test_setPolicy_upgradeKey_succeeds() external {
        address newPolicy = makeAddr("newPolicy");

        vm.prank(moduleOwner);
        module.setPolicy(newPolicy);

        assertEq(module.policy(), newPolicy);
    }
}

/// @title ComplianceModule_Inert_Test
/// @notice The feature must be inert when unconfigured, which is what makes it safe to ship to
///         every chain.
contract ComplianceModule_Inert_Test is CommonTest {
    /// @notice With no hook address configured, deposits behave exactly as they do on a stock
    ///         chain even when the feature flag is on.
    function test_noHookAddress_depositUnchanged_succeeds() external {
        vm.prank(proxyAdminOwner);
        systemConfig.setFeature(Features.BRIDGE_HOOK, true);

        address custodian = systemConfig.isFeatureEnabled(Features.ETH_LOCKBOX) && address(ethLockbox) != address(0)
            ? address(ethLockbox)
            : address(optimismPortal2);
        uint256 custodyBefore = custodian.balance;

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: 1 ether }(bob, 0, 100_000, false, hex"");

        assertEq(custodian.balance, custodyBefore + 1 ether, "ETH should be taken into custody as usual");
        assertEq(optimismPortal2.depositNonce(), 0, "no identifier should have been assigned");
    }

    /// @notice The hook address cannot be set while the feature is off.
    function test_setBridgeHook_featureDisabled_reverts() external {
        vm.prank(proxyAdminOwner);
        vm.expectRevert(abi.encodeWithSignature("OptimismPortal_InvalidBridgeHookState()"));
        optimismPortal2.setBridgeHook(IBridgeHook(makeAddr("hook")));
    }
}

/// @notice A hook that keeps the ETH it is handed and tries to restore the Portal's balance with a
///         fresh deposit from inside the same call, which is how the returned-value check would be
///         defeated without a guard.
contract ReenteringHook is IBridgeHook {
    IOptimismPortal2 internal portal;

    constructor(IOptimismPortal2 _portal) {
        portal = _portal;
    }

    function screenDeposit(Item calldata) external returns (bool pass_) {
        portal.depositTransaction{ value: address(this).balance }(address(1), 0, 100_000, false, hex"");
        pass_ = true;
    }

    function holdDeposit(Item calldata) external payable { }

    function screenWithdrawal(Item calldata) external pure returns (bool pass_) {
        pass_ = true;
    }

    function holdWithdrawal(Item calldata) external payable { }
}

/// @title ComplianceModule_HookReentrancy_Test
/// @notice The hook is called from the hottest function in the protocol, on a path that sits
///         outside both the Portal's l2Sender guard and the lockbox's own check.
contract ComplianceModule_HookReentrancy_Test is ComplianceModule_TestInit {
    /// @notice A value-bearing deposit cannot be made from inside a hook call.
    function test_depositTransaction_reentrantFromHook_reverts() external {
        ReenteringHook hostile = new ReenteringHook(optimismPortal2);

        vm.prank(proxyAdminOwner);
        optimismPortal2.setBridgeHook(IBridgeHook(address(hostile)));

        vm.prank(alice, alice);
        vm.expectRevert(abi.encodeWithSignature("OptimismPortal_NoReentrancy()"));
        optimismPortal2.depositTransaction{ value: 1 ether }(bob, 0, 100_000, false, hex"");
    }

    /// @notice A hook cannot keep the ETH of a deposit it passes, because it is never handed it.
    ///         The question carries no value; only the hold does.
    function test_depositTransaction_passingHookIsHandedNoValue() external {
        // A hook that answers true and does nothing else. Under a design that pushed the value
        // with the question, this one would simply keep it.
        address hostile = makeAddr("retainingHook");
        vm.etch(hostile, hex"");
        vm.mockCall(hostile, abi.encodeWithSelector(IBridgeHook.screenDeposit.selector), abi.encode(true));

        vm.prank(proxyAdminOwner);
        optimismPortal2.setBridgeHook(IBridgeHook(hostile));

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: 1 ether }(bob, 0, 100_000, false, hex"");

        assertEq(hostile.balance, 0, "a passing hook should never receive the deposit's ETH");
        assertEq(_ethCustodian().balance, 1 ether, "the ETH should have gone straight to custody");
    }
}

/// @title ComplianceModule_ETHBridging_Test
/// @notice The bridge's ETH entry points stay open. Every route ends at the Portal, which screens
///         the value and resolves the parties through the envelope, so closing them would break
///         clean users without covering anything the Portal does not already cover.
contract ComplianceModule_ETHBridging_Test is ComplianceModule_TestInit {
    /// @notice A bridge ETH deposit is screened once, at the Portal, against the real depositor
    ///         and recipient rather than the two bridges it travelled through.
    function test_depositETHTo_isScreenedAgainstTheUser() external {
        vm.prank(alice, alice);
        l1StandardBridge.depositETHTo{ value: 1 ether }(bob, 200_000, hex"");

        assertEq(policy.screenCalls(), 1, "screened exactly once, at the Portal");
        assertEq(policy.lastParties(0), alice, "the sender is the depositor");
        assertEq(policy.lastParties(1), bob, "the recipient is the depositor's recipient");
    }

    /// @notice And when it is not cleared the ETH ends up with the module, not in the lockbox.
    function test_depositETHTo_notCleared_holdsAtTheModule() external {
        uint256 custodyBefore = _ethCustodian().balance;

        vm.prank(alice, alice);
        l1StandardBridge.depositETHTo{ value: 1 ether }(bob, 200_000, hex"");

        assertEq(address(module).balance, 1 ether, "the module holds the ETH");
        assertEq(_ethCustodian().balance, custodyBefore, "protocol custody is untouched");
    }

    /// @notice An ETH deposit routed through the bridge must never pick up the token exemption.
    ///         It comes from the same contracts, so the amount and the inner selector are what
    ///         tell the two apart.
    function test_ethViaBridge_doesNotGetTheTokenExemption() external {
        policy.setPassDeposits(true);
        policy.setDenied(alice, true);

        vm.prank(alice, alice);
        l1StandardBridge.depositETHTo{ value: 1 ether }(bob, 200_000, hex"");

        assertEq(address(module).balance, 1 ether, "a denied depositor is held, so it was screened");
    }

    /// @notice Sending ETH straight to the bridge still works and is screened the same way.
    function test_receive_isScreened() external {
        vm.prank(alice, alice);
        (bool success,) = address(l1StandardBridge).call{ value: 1 ether }(hex"");

        assertTrue(success, "the bridge still accepts ETH");
        assertEq(policy.screenCalls(), 1, "and it was screened");
        assertEq(policy.lastParties(0), alice, "against the sender");
    }
}

/// @notice A hook that reenters finalization from the withdrawal screen, which runs after the ETH
///         is unlocked and before l2Sender is set, so neither the Portal's own guard nor the
///         lockbox's covers it.
contract WithdrawalReenteringHook is IBridgeHook {
    IOptimismPortal2 internal portal;

    constructor(IOptimismPortal2 _portal) {
        portal = _portal;
    }

    function screenDeposit(Item calldata) external pure returns (bool pass_) {
        pass_ = true;
    }

    function holdDeposit(Item calldata) external payable { }

    function screenWithdrawal(Item calldata) external returns (bool pass_) {
        Types.WithdrawalTransaction memory reentrant;
        portal.finalizeWithdrawalTransaction(reentrant);
        pass_ = true;
    }

    function holdWithdrawal(Item calldata) external payable { }
}

/// @title ComplianceModule_MessengerRouting_Test
/// @notice Now that every deposit is screened, the messenger carries two very different kinds of
///         traffic through the Portal and they must not be treated alike.
contract ComplianceModule_MessengerRouting_Test is ComplianceModule_TestInit {
    /// @notice A message a user sends through the messenger is screened, and screened against the
    ///         user rather than against the messenger. This is the bypass the exemption must not
    ///         open: whitelisting the messenger outright would exempt exactly this.
    function test_userMessengerMessage_isScreenedAgainstTheUser() external {
        vm.prank(alice, alice);
        l1CrossDomainMessenger.sendMessage(bob, hex"1234", 200_000);

        assertEq(policy.screenCalls(), 1, "the message should have been screened");
        assertEq(policy.lastParties(0), alice, "the sender should be the user, not the messenger");
        assertEq(policy.lastParties(1), bob, "the recipient should be the inner target");
    }

    /// @notice The same message from a denied user is held, which is what the screening is for.
    function test_userMessengerMessage_deniedUser_isHeld() external {
        policy.setPassDeposits(true);
        policy.setDenied(alice, true);

        vm.prank(alice, alice);
        l1CrossDomainMessenger.sendMessage(bob, hex"1234", 200_000);

        assertEq(optimismPortal2.depositNonce(), 1, "an identifier should have been assigned");
    }

    /// @notice A denied user cannot launder their identity by sending a genuine messenger envelope
    ///         whose payload is shaped like a bridge finalizer naming two clean addresses.
    /// @dev    The envelope here is real, not forged: it went through the canonical messenger, so
    ///         every check that authenticates the *envelope* passes. What must not be believed is
    ///         the payload inside it. The messenger writes the inner sender as its own caller, so
    ///         requiring that to be the counterpart bridge is what ties a finalizer payload to the
    ///         only contract that could have produced it honestly. Without that check the parties
    ///         resolve to the addresses the submitter chose and the deposit passes.
    function test_userMessengerMessage_bridgeShapedPayload_isScreenedAgainstTheSubmitter() external {
        address cleanFrom = makeAddr("cleanFrom");
        address cleanTo = makeAddr("cleanTo");

        policy.setPassDeposits(true);
        policy.setDenied(alice, true);

        bytes memory inner =
            abi.encodeCall(IStandardBridge.finalizeBridgeETH, (cleanFrom, cleanTo, 1 ether, hex""));

        vm.deal(alice, 2 ether);
        vm.prank(alice, alice);
        l1CrossDomainMessenger.sendMessage{ value: 1 ether }(Predeploys.L2_STANDARD_BRIDGE, inner, 200_000);

        assertEq(policy.lastParties(0), alice, "the party is the submitter, not the payload's sender");
        assertTrue(policy.lastParties(0) != cleanFrom, "the payload must not substitute the sender");
        assertEq(address(module).balance, 1 ether, "the denied submitter should have been held");
    }
}

/// @title ComplianceModule_RemainingCases_Test
/// @notice Cases the four flow suites leave uncovered.
contract ComplianceModule_RemainingCases_Test is ComplianceModule_TestInit {
    /// @notice A zero-value deposit the policy passes behaves exactly as it does on a stock chain.
    function test_ethDeposit_zeroValue_passing_behavesAsStock() external {
        policy.setPassDeposits(true);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: 0 }(bob, 0, 100_000, false, hex"");

        assertEq(optimismPortal2.depositNonce(), 1, "the item was screened");
        (uint64 heldAt,) = module.items(BridgeHookItem.hash(_ethDepositItem(alice, bob, 0, 100_000, bytes32(0))));
        assertEq(heldAt, 0, "nothing should have been held");
    }

    /// @notice A passing mintable deposit burns from the depositor and mints nothing, which is
    ///         byte-for-byte what an unmodified bridge does.
    function test_erc20Deposit_mintableToken_passing_burnsFromDepositor() external {
        policy.setPassDeposits(true);

        address remote = makeAddr("remoteMintable");
        IOptimismMintableERC20 mintable = IOptimismMintableERC20(
            l1OptimismMintableERC20Factory.createOptimismMintableERC20(remote, "Mintable", "MNT")
        );

        uint256 amount = 50e18;
        vm.prank(address(l1StandardBridge));
        mintable.mint(alice, amount);
        uint256 supplyBefore = IERC20(address(mintable)).totalSupply();

        // No approve, exactly as an existing integration would call it.
        vm.prank(alice, alice);
        l1StandardBridge.depositERC20To(address(mintable), remote, bob, amount, 100_000, hex"");

        assertEq(IERC20(address(mintable)).balanceOf(alice), 0, "burned from the depositor");
        assertEq(IERC20(address(mintable)).balanceOf(address(module)), 0, "the module holds nothing on a pass");
        assertEq(IERC20(address(mintable)).totalSupply(), supplyBefore - amount, "supply drops once");
    }

    /// @notice A mintable token withdrawal cleared during the window is minted straight to the
    ///         recipient, with no hold and no second transaction.
    function test_erc20Withdrawal_mintableToken_clearedDuringWindow_paysDirectly() external {
        address remote = makeAddr("remoteMintable");
        IOptimismMintableERC20 mintable = IOptimismMintableERC20(
            l1OptimismMintableERC20Factory.createOptimismMintableERC20(remote, "Mintable", "MNT")
        );

        uint256 amount = 50e18;
        Types.WithdrawalTransaction memory wtx =
            _bridgedERC20Withdrawal(address(mintable), remote, alice, bob, amount);
        bytes32 withdrawalHash = _fakeProve(wtx);

        Item memory item =
            _erc20Item(Direction.Withdrawal, alice, bob, address(mintable), remote, amount, 0, withdrawalHash);
        policy.clear(BridgeHookItem.hash(item));

        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertEq(IERC20(address(mintable)).balanceOf(bob), amount, "the recipient is minted at finalization");
        assertEq(IERC20(address(mintable)).balanceOf(address(module)), 0, "nothing should have been held");
    }

    /// @notice A revoked clearance stops an item that was already cleared.
    function test_revokeVerdict_blocksCompletion() external {
        uint256 amount = 1 ether;
        Item memory item = _ethDepositItem(alice, bob, amount, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");

        policy.clear(id);
        policy.revoke(id);

        vm.expectRevert(ComplianceModule.ComplianceModule_NotCleared.selector);
        module.completeDeposit(item);
    }

    /// @notice An on-chain deny beats a prior clearance on the withdrawal side too, not only on
    ///         deposits.
    function test_ethWithdrawal_denyBeatsPriorClearance_reverts() external {
        uint256 amount = 1 ether;
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, amount);
        _fakeProve(wtx);

        optimismPortal2.finalizeWithdrawalTransaction(wtx);
        policy.clear(_ethWithdrawalId(wtx));

        policy.setDenied(bob, true);

        Item memory item = BridgeHookItem.fromWithdrawalTransaction(wtx, Hashing.hashWithdrawal(wtx));
        vm.expectRevert(ComplianceModule.ComplianceModule_ReleaseDeclined.selector);
        module.releaseWithdrawal(item);
    }

    /// @notice The withdrawal screen is guarded too, on the leg that sits outside both the
    ///         Portal's l2Sender check and the lockbox's own.
    function test_finalizeWithdrawal_reentrantFromHook_reverts() external {
        WithdrawalReenteringHook hostile = new WithdrawalReenteringHook(optimismPortal2);

        vm.prank(proxyAdminOwner);
        optimismPortal2.setBridgeHook(IBridgeHook(address(hostile)));

        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, 1 ether);
        _fakeProve(wtx);

        vm.expectRevert(abi.encodeWithSignature("OptimismPortal_NoReentrancy()"));
        optimismPortal2.finalizeWithdrawalTransaction(wtx);
    }
}

/// @title ComplianceModule_MessengerETH_Test
/// @notice ETH travelling through the messenger is screened where it lands, at the Portal, and the
///         hook unwraps the envelope so the screen names whoever actually paid.
contract ComplianceModule_MessengerETH_Test is ComplianceModule_TestInit {
    /// @notice A value-bearing message goes through and is screened at the Portal, against the
    ///         caller and the L2 target rather than the two messengers.
    function test_sendMessageWithValue_isScreenedAgainstTheUser() external {
        vm.prank(alice, alice);
        l1CrossDomainMessenger.sendMessage{ value: 1 ether }(bob, hex"1234", 200_000);

        assertEq(policy.screenCalls(), 1, "screened once");
        assertEq(policy.lastParties(0), alice, "the sender is the caller");
        assertEq(policy.lastParties(1), bob, "the recipient is the L2 target");
        assertEq(address(module).balance, 1 ether, "and the ETH is held at the module");
    }

    /// @notice A message with no value still goes through, and is still screened.
    function test_sendMessageWithoutValue_succeeds() external {
        vm.prank(alice, alice);
        l1CrossDomainMessenger.sendMessage(bob, hex"1234", 200_000);

        assertEq(policy.screenCalls(), 1, "the message should have been screened");
    }
}

/// @title ComplianceModule_WithdrawalShapes_Test
/// @notice A withdrawal reaches L1 in more than one shape, and the expectation is that the shape
///         changes where it is caught but never whether it is caught.
contract ComplianceModule_WithdrawalShapes_Test is ComplianceModule_TestInit {
    /// @notice A withdrawal the user initiated straight at the MessagePasser, paying an address
    ///         with no messenger in between.
    function _directETHWithdrawal(
        address _from,
        address _to,
        uint256 _amount
    )
        internal
        pure
        returns (Types.WithdrawalTransaction memory)
    {
        return Types.WithdrawalTransaction({
            nonce: 0,
            sender: _from,
            target: _to,
            value: _amount,
            gasLimit: WITHDRAWAL_GAS_LIMIT,
            data: hex""
        });
    }

    /// @notice Cleared in advance, a direct withdrawal pays out at finalization with no hold.
    function test_directETHWithdrawal_clearedDuringWindow_paysDirectly() external {
        uint256 amount = 1 ether;
        Types.WithdrawalTransaction memory wtx = _directETHWithdrawal(alice, bob, amount);
        _fakeProve(wtx);

        policy.clear(_ethWithdrawalId(wtx));

        uint256 before = bob.balance;
        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertEq(bob.balance, before + amount, "the recipient is paid at finalization");
        assertEq(address(module).balance, 0, "nothing should have been held");
    }

    /// @notice Not cleared, it is held at the Portal and the ETH goes to the module, exactly as
    ///         the messenger-routed shape does.
    function test_directETHWithdrawal_notCleared_holdsAtThePortal() external {
        uint256 amount = 1 ether;
        Types.WithdrawalTransaction memory wtx = _directETHWithdrawal(alice, bob, amount);
        bytes32 hash = _fakeProve(wtx);

        uint256 before = bob.balance;
        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertTrue(optimismPortal2.finalizedWithdrawals(hash), "consumed either way");
        assertTrue(optimismPortal2.heldWithdrawals(_ethWithdrawalId(wtx)), "the Portal committed to it");
        assertEq(address(module).balance, amount, "the module holds the ETH");
        assertEq(bob.balance, before, "the recipient is not paid");
    }

    /// @notice And it releases to the original recipient once a verdict arrives.
    function test_directETHWithdrawal_releaseAfterVerdict_succeeds() external {
        uint256 amount = 1 ether;
        Types.WithdrawalTransaction memory wtx = _directETHWithdrawal(alice, bob, amount);
        _fakeProve(wtx);

        optimismPortal2.finalizeWithdrawalTransaction(wtx);
        policy.clear(_ethWithdrawalId(wtx));

        uint256 before = bob.balance;
        module.releaseWithdrawal(BridgeHookItem.fromWithdrawalTransaction(wtx, Hashing.hashWithdrawal(wtx)));

        assertEq(bob.balance, before + amount, "the recipient is paid at release");
        assertEq(address(module).balance, 0, "the module holds nothing");
    }

    /// @notice The effective parties of a direct withdrawal are its own fields, with no unwrapping,
    ///         because nothing authenticates as the messenger.
    function test_directETHWithdrawal_partiesAreTheOuterFields() external view {
        Types.WithdrawalTransaction memory wtx = _directETHWithdrawal(alice, bob, 1 ether);
        Item memory item = BridgeHookItem.fromWithdrawalTransaction(wtx, Hashing.hashWithdrawal(wtx));

        address[] memory parties = module.effectiveParties(item);
        assertEq(parties[0], alice);
        assertEq(parties[1], bob);
    }

    /// @notice A withdrawal carrying no ETH still executes an arbitrary L1 call chosen by an L2
    ///         sender, so it is screened and held like any other.
    function test_zeroValueWithdrawal_isScreenedAndHeld() external {
        policy.setDenied(alice, true);

        Types.WithdrawalTransaction memory wtx = Types.WithdrawalTransaction({
            nonce: 0,
            sender: alice,
            target: bob,
            value: 0,
            gasLimit: WITHDRAWAL_GAS_LIMIT,
            data: hex"1234"
        });
        _fakeProve(wtx);

        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertTrue(optimismPortal2.heldWithdrawals(_ethWithdrawalId(wtx)), "the denied sender should be held");
    }

    /// @notice And it releases once a verdict arrives, with nothing to hand over on the way.
    function test_zeroValueWithdrawal_releasesAfterVerdict() external {
        Types.WithdrawalTransaction memory wtx = Types.WithdrawalTransaction({
            nonce: 0,
            sender: alice,
            target: bob,
            value: 0,
            gasLimit: WITHDRAWAL_GAS_LIMIT,
            data: hex"1234"
        });
        _fakeProve(wtx);

        optimismPortal2.finalizeWithdrawalTransaction(wtx);
        policy.clear(_ethWithdrawalId(wtx));

        module.releaseWithdrawal(BridgeHookItem.fromWithdrawalTransaction(wtx, Hashing.hashWithdrawal(wtx)));

        assertFalse(optimismPortal2.heldWithdrawals(_ethWithdrawalId(wtx)), "the commitment is consumed");
    }

    /// @notice The token envelope is the one shape that passes the Portal without a verdict, so
    ///         that the bridge can judge it where its value actually moves.
    function test_tokenEnvelope_isDeferredToTheBridge_notHeldAtThePortal() external {
        uint256 amount = 100e18;
        address remote = makeAddr("remoteToken");
        _seedBridgeEscrow(address(token), remote, amount);

        Types.WithdrawalTransaction memory wtx = _bridgedERC20Withdrawal(address(token), remote, alice, bob, amount);
        _fakeProve(wtx);

        // Nothing is cleared anywhere, so the bridge holds it and the Portal must not.
        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertFalse(optimismPortal2.heldWithdrawals(_ethWithdrawalId(wtx)), "the Portal should have deferred");
        assertEq(token.balanceOf(address(module)), amount, "the bridge held it instead");
    }

    /// @notice A payload that merely looks like a token envelope does not get the exemption,
    ///         because the withdrawal's own sender is not the L2 messenger.
    function test_forgedTokenEnvelope_isScreened() external {
        policy.setDenied(alice, true);

        bytes memory inner = abi.encodeCall(
            IStandardBridge.finalizeBridgeERC20,
            (address(token), makeAddr("remote"), makeAddr("cleanFrom"), makeAddr("cleanTo"), 1e18, hex"")
        );
        bytes memory envelope = abi.encodeCall(
            ICrossDomainMessenger.relayMessage,
            (
                Encoding.encodeVersionedNonce(0, 1),
                Predeploys.L2_STANDARD_BRIDGE,
                address(l1StandardBridge),
                0,
                200_000,
                inner
            )
        );

        Types.WithdrawalTransaction memory wtx = Types.WithdrawalTransaction({
            nonce: 0,
            sender: alice,
            target: address(l1CrossDomainMessenger),
            value: 0,
            gasLimit: WITHDRAWAL_GAS_LIMIT,
            data: envelope
        });
        _fakeProve(wtx);

        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertTrue(optimismPortal2.heldWithdrawals(_ethWithdrawalId(wtx)), "the forgery should be screened and held");
    }
}

/// @title ComplianceModule_Disable_Test
/// @notice The emergency stop. It lives in the module rather than in the protocol, and it only
///         ever reaches forward: items already held keep needing a verdict.
contract ComplianceModule_Disable_Test is ComplianceModule_TestInit {
    function _disable(bool _value) internal {
        vm.prank(moduleOwner);
        module.setDisabled(_value);
    }

    /// @notice While disabled a deposit behaves exactly as it would on a stock chain: the policy is
    ///         never consulted, nothing is committed, and the ETH reaches protocol custody.
    function test_disabled_deposit_behavesAsStock() external {
        uint256 amount = 1 ether;
        uint256 custodyBefore = _ethCustodian().balance;

        // The policy would hold this deposit if it were asked.
        assertFalse(policy.passDeposits(), "policy would otherwise hold");

        _disable(true);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");

        assertEq(address(module).balance, 0, "module should hold nothing");
        assertEq(_ethCustodian().balance, custodyBefore + amount, "ETH should reach protocol custody");
        assertEq(optimismPortal2.outstandingBridgeHookItems(), 0, "nothing should be deferred");
    }

    /// @notice While disabled a withdrawal pays its recipient at finalization instead of being
    ///         routed into holding.
    function test_disabled_withdrawal_paysOut() external {
        uint256 amount = 1 ether;
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, amount);
        _fakeProve(wtx);

        _disable(true);

        uint256 recipientBefore = bob.balance;
        optimismPortal2.finalizeWithdrawalTransaction(wtx);

        assertEq(bob.balance, recipientBefore + amount, "recipient should be paid");
        assertEq(address(module).balance, 0, "module should hold nothing");
        assertFalse(optimismPortal2.heldWithdrawals(_ethWithdrawalId(wtx)), "nothing should be held");
    }

    /// @notice The stop does not reach backwards. A deposit held before the disable still needs a
    ///         clear verdict, so disabling is not a release valve for value already flagged.
    function test_disabled_heldDeposit_stillNeedsVerdict() external {
        uint256 amount = 1 ether;
        Item memory item = _ethDepositItem(alice, bob, amount, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");
        assertTrue(optimismPortal2.pendingDeposits(id), "deposit should be held");

        _disable(true);

        vm.expectRevert(bytes4(keccak256("ComplianceModule_NotCleared()")));
        module.completeDeposit(item);

        // Still completable through the normal path once the policy clears it.
        policy.clear(id);
        module.completeDeposit(item);
        assertFalse(optimismPortal2.pendingDeposits(id), "commitment should be consumed");
    }

    /// @notice The same, on the withdrawal side.
    function test_disabled_heldWithdrawal_stillNeedsVerdict() external {
        uint256 amount = 1 ether;
        Types.WithdrawalTransaction memory wtx = _bridgedETHWithdrawal(alice, bob, amount);
        _fakeProve(wtx);

        optimismPortal2.finalizeWithdrawalTransaction(wtx);
        assertEq(address(module).balance, amount, "withdrawal should be held");

        _disable(true);

        Item memory item = BridgeHookItem.fromWithdrawalTransaction(wtx, Hashing.hashWithdrawal(wtx));
        vm.expectRevert(bytes4(keccak256("ComplianceModule_NotCleared()")));
        module.releaseWithdrawal(item);
    }

    /// @notice Re-enabling restores screening with no loss of state.
    function test_reenable_restoresScreening() external {
        _disable(true);
        _disable(false);

        uint256 amount = 1 ether;
        Item memory item = _ethDepositItem(alice, bob, amount, 100_000, bytes32(0));

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: amount }(bob, 0, 100_000, false, hex"");

        assertEq(address(module).balance, amount, "screening should be back on");
        assertTrue(optimismPortal2.pendingDeposits(BridgeHookItem.hash(item)), "terms should be committed again");
    }

    /// @notice Only the module's own upgrade authority can pull the stop.
    function test_setDisabled_notModuleOwner_reverts() external {
        vm.expectRevert(bytes4(keccak256("ProxyAdminOwnedBase_NotProxyAdminOwner()")));
        vm.prank(proxyAdminOwner);
        module.setDisabled(true);

        vm.prank(moduleOwner);
        module.setDisabled(true);
        assertTrue(module.disabled(), "the module owner can");
    }
}

/// @title ComplianceModule_HookPointer_Test
/// @notice The hook address cannot move while items are deferred to it, because every release path
///         is gated on the live address.
contract ComplianceModule_HookPointer_Test is ComplianceModule_TestInit {
    /// @notice Unsetting the hook while a deposit is held would strand it, so it is refused.
    function test_setBridgeHook_itemsOutstanding_reverts() external {
        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: 1 ether }(bob, 0, 100_000, false, hex"");
        assertEq(optimismPortal2.outstandingBridgeHookItems(), 1, "one item deferred");

        vm.expectRevert(bytes4(keccak256("OptimismPortal_BridgeHookItemsOutstanding()")));
        vm.prank(proxyAdminOwner);
        optimismPortal2.setBridgeHook(IBridgeHook(address(0)));
    }

    /// @notice Once everything has completed the pointer is free to move again.
    function test_setBridgeHook_afterCompletion_succeeds() external {
        Item memory item = _ethDepositItem(alice, bob, 1 ether, 100_000, bytes32(0));
        bytes32 id = BridgeHookItem.hash(item);

        vm.prank(alice, alice);
        optimismPortal2.depositTransaction{ value: 1 ether }(bob, 0, 100_000, false, hex"");

        policy.clear(id);
        module.completeDeposit(item);
        assertEq(optimismPortal2.outstandingBridgeHookItems(), 0, "nothing deferred any more");

        vm.prank(proxyAdminOwner);
        optimismPortal2.setBridgeHook(IBridgeHook(address(0)));
        assertEq(address(optimismPortal2.bridgeHook()), address(0), "pointer should be clear");
    }

    /// @notice The key that can upgrade the contract holding frozen value is not the chain's.
    function test_moduleUpgradeAuthority_isNotTheChains() external view {
        assertTrue(module.proxyAdminOwner() != proxyAdminOwner, "module owner must not be chain governance");
        assertEq(module.proxyAdminOwner(), moduleOwner, "module owner should be its own admin's owner");
    }
}
