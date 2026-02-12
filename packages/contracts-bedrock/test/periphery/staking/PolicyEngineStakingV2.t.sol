// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { CommonTest } from "test/setup/CommonTest.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";

// Contracts
import { PolicyEngineStakingV2 } from "src/periphery/staking/PolicyEngineStakingV2.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

/// @title PolicyEngineStakingV2_TestInit
/// @notice Reusable test initialization for `PolicyEngineStakingV2` tests.
abstract contract PolicyEngineStakingV2_TestInit is CommonTest {
    address internal carol = address(0xC4101);

    PolicyEngineStakingV2 internal staking;
    address internal owner;

    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event Linked(address indexed staker, address indexed beneficiary);
    event Unlinked(address indexed staker, address indexed previousBeneficiary);
    event EffectiveStakeChanged(address indexed account, uint256 newEffectiveStake);
    event BeneficiaryAllowlistUpdated(address indexed beneficiary, address indexed staker, bool allowed);
    event Paused();
    event Unpaused();

    function setUp() public virtual override {
        super.setUp();
        owner = makeAddr("owner");
        staking = new PolicyEngineStakingV2(owner);

        _setupMockOPToken();

        vm.label(carol, "carol");
        vm.label(address(staking), "PolicyEngineStakingV2");
    }

    /// @notice Deploys TestERC20 at the predeploy address and funds test accounts.
    function _setupMockOPToken() internal {
        TestERC20 token = new TestERC20();
        vm.etch(Predeploys.GOVERNANCE_TOKEN, address(token).code);

        TestERC20(Predeploys.GOVERNANCE_TOKEN).mint(alice, 1_000 ether);
        TestERC20(Predeploys.GOVERNANCE_TOKEN).mint(bob, 1_000 ether);
        TestERC20(Predeploys.GOVERNANCE_TOKEN).mint(carol, 1_000 ether);
    }

    /// @notice Approves the staking contract and stakes tokens via stakeAndLink.
    function _stakeAndLink(address _account, uint256 _amount, address _beneficiary) internal {
        vm.prank(_account);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), _amount);
        vm.prank(_account);
        staking.stakeAndLink(_amount, _beneficiary);
    }

    /// @notice Approves the staking contract and stakes tokens via stake (requires existing link).
    function _stake(address _account, uint256 _amount) internal {
        vm.prank(_account);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), _amount);
        vm.prank(_account);
        staking.stake(_amount);
    }
}

/// @title PolicyEngineStakingV2_Pause_Test
/// @notice Tests the pause/unpause functionality.
contract PolicyEngineStakingV2_Pause_Test is PolicyEngineStakingV2_TestInit {
    /// @notice Tests that owner can pause and unpause.
    function test_pauseUnpause_owner_succeeds() external {
        assertFalse(staking.paused());

        vm.expectEmit(address(staking));
        emit Paused();
        vm.prank(owner);
        staking.pause();

        assertTrue(staking.paused());

        vm.expectEmit(address(staking));
        emit Unpaused();
        vm.prank(owner);
        staking.unpause();

        assertFalse(staking.paused());
    }

    /// @notice Tests that non-owner cannot pause.
    function test_pause_notOwner_reverts() external {
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_OnlyOwner.selector);
        vm.prank(alice);
        staking.pause();
    }

    /// @notice Tests that non-owner cannot unpause.
    function test_unpause_notOwner_reverts() external {
        vm.prank(owner);
        staking.pause();

        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_OnlyOwner.selector);
        vm.prank(alice);
        staking.unpause();
    }

    /// @notice Tests that stakeAndLink reverts when paused.
    function test_stakeAndLink_whenPaused_reverts() external {
        vm.prank(owner);
        staking.pause();

        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), 100 ether);

        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_Paused.selector);
        vm.prank(alice);
        staking.stakeAndLink(100 ether, alice);
    }

    /// @notice Tests that stake reverts when paused.
    function test_stake_whenPaused_reverts() external {
        _stakeAndLink(alice, 100 ether, alice);

        vm.prank(owner);
        staking.pause();

        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), 50 ether);

        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_Paused.selector);
        vm.prank(alice);
        staking.stake(50 ether);
    }

    /// @notice Tests that link reverts when paused.
    function test_link_whenPaused_reverts() external {
        _stakeAndLink(alice, 100 ether, alice);
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);

        vm.prank(owner);
        staking.pause();

        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_Paused.selector);
        vm.prank(alice);
        staking.link(bob);
    }

    /// @notice Tests that unstake works when paused.
    function test_unstake_whenPaused_succeeds() external {
        _stakeAndLink(alice, 100 ether, alice);
        vm.prank(owner);
        staking.pause();

        uint256 balanceBefore = IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice);
        vm.prank(alice);
        staking.unstake(100 ether);
        assertEq(IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice), balanceBefore + 100 ether);
    }
}

/// @title PolicyEngineStakingV2_StakeAndLink_Test
/// @notice Tests the `stakeAndLink` function.
contract PolicyEngineStakingV2_StakeAndLink_Test is PolicyEngineStakingV2_TestInit {
    /// @notice Tests that stakeAndLink with self-attribution succeeds.
    function test_stakeAndLink_selfAttribution_succeeds() external {
        uint256 amount = 100 ether;

        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), amount);

        vm.expectEmit(address(staking));
        emit Linked(alice, alice);
        vm.expectEmit(address(staking));
        emit EffectiveStakeChanged(alice, amount);
        vm.expectEmit(address(staking));
        emit Staked(alice, amount);

        vm.prank(alice);
        staking.stakeAndLink(amount, alice);

        (uint256 staked, address linkedTo) = staking.stakingData(alice);
        (uint128 effectiveStake, uint128 lastUpdate) = staking.peData(alice);

        assertEq(staked, amount);
        assertEq(linkedTo, alice);
        assertEq(effectiveStake, amount);
        assertEq(lastUpdate, block.timestamp);
    }

    /// @notice Tests that multiple stakeAndLink calls to same beneficiary succeed.
    function test_stakeAndLink_severalToSameBeneficiary_succeeds() external {
        _stakeAndLink(alice, 100 ether, alice);
        _stakeAndLink(alice, 200 ether, alice);
        _stakeAndLink(alice, 300 ether, alice);

        (uint256 aliceStaked, address aliceLinkedTo) = staking.stakingData(alice);
        assertEq(aliceStaked, 600 ether);
        assertEq(aliceLinkedTo, alice);
        (uint128 aliceEffectiveStake, uint128 aliceLastUpdate) = staking.peData(alice);
        assertEq(aliceEffectiveStake, 600 ether);
        assertEq(aliceLastUpdate, block.timestamp);
    }

    /// @notice Tests that stakeAndLink to another beneficiary with allowlist succeeds.
    function test_stakeAndLink_toBeneficiaryWithAllowlist_succeeds() external {
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);

        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), 100 ether);

        vm.expectEmit(address(staking));
        emit Linked(alice, bob);
        vm.expectEmit(address(staking));
        emit EffectiveStakeChanged(bob, 100 ether);
        vm.expectEmit(address(staking));
        emit Staked(alice, 100 ether);

        vm.prank(alice);
        staking.stakeAndLink(100 ether, bob);

        (uint256 staked, address linkedTo) = staking.stakingData(alice);
        (uint128 effectiveStake, uint128 lastUpdate) = staking.peData(alice);
        assertEq(staked, 100 ether);
        assertEq(linkedTo, bob);
        assertEq(effectiveStake, 0);
        assertEq(lastUpdate, 0);

        (uint128 bobEffectiveStake, uint128 bobLastUpdate) = staking.peData(bob);
        assertEq(bobEffectiveStake, 100 ether);
        assertEq(bobLastUpdate, block.timestamp);
    }

    /// @notice Tests that stakeAndLink more to same beneficiary when already linked succeeds.
    function test_stakeAndLink_moreToSameBeneficiary_succeeds() external {
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);
        _stakeAndLink(alice, 100 ether, bob);

        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), 50 ether);
        vm.prank(alice);
        staking.stakeAndLink(50 ether, bob);

        (uint256 staked,) = staking.stakingData(alice);
        assertEq(staked, 150 ether);
        (uint128 bobEffective,) = staking.peData(bob);
        assertEq(bobEffective, 150 ether);
    }

    /// @notice Tests that stakeAndLink re-links to new beneficiary atomically.
    function test_stakeAndLink_relink_succeeds() external {
        // Alice stakes to self
        _stakeAndLink(alice, 100 ether, alice);

        (uint128 aliceEffBefore,) = staking.peData(alice);
        assertEq(aliceEffBefore, 100 ether);

        // Bob allows alice
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);

        // Alice re-links to bob with additional stake
        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), 50 ether);

        vm.expectEmit(address(staking));
        emit EffectiveStakeChanged(alice, 0); // decrease alice's PE
        vm.expectEmit(address(staking));
        emit Unlinked(alice, alice);
        vm.expectEmit(address(staking));
        emit EffectiveStakeChanged(bob, 100 ether); // increase bob's PE by existing stake
        vm.expectEmit(address(staking));
        emit Linked(alice, bob);
        vm.expectEmit(address(staking));
        emit EffectiveStakeChanged(bob, 150 ether); // increase bob's PE by new amount
        vm.expectEmit(address(staking));
        emit Staked(alice, 50 ether);

        vm.prank(alice);
        staking.stakeAndLink(50 ether, bob);

        (uint256 staked, address linkedTo) = staking.stakingData(alice);
        assertEq(staked, 150 ether);
        assertEq(linkedTo, bob);
        (uint128 aliceEffAfter,) = staking.peData(alice);
        assertEq(aliceEffAfter, 0);
        (uint128 bobEff,) = staking.peData(bob);
        assertEq(bobEff, 150 ether);
    }

    /// @notice Tests that stakeAndLink with zero amount reverts.
    function test_stakeAndLink_zeroAmount_reverts() external {
        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_ZeroAmount.selector);
        staking.stakeAndLink(0, alice);
    }

    /// @notice Tests that stakeAndLink with zero beneficiary reverts.
    function test_stakeAndLink_zeroBeneficiary_reverts() external {
        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), 100 ether);

        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_ZeroBeneficiary.selector);
        staking.stakeAndLink(100 ether, address(0));
    }

    /// @notice Tests that stakeAndLink to beneficiary without allowlist reverts.
    function test_stakeAndLink_toBeneficiaryWithoutAllowlist_reverts() external {
        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), 100 ether);

        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_NotAllowedToLink.selector);
        staking.stakeAndLink(100 ether, bob);
    }

    /// @notice Tests re-link from beneficiary to self reverts without allowlist removal.
    function test_stakeAndLink_relinkToBeneficiaryWithoutAllowlist_reverts() external {
        _stakeAndLink(alice, 100 ether, alice);

        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), 50 ether);

        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_NotAllowedToLink.selector);
        staking.stakeAndLink(50 ether, bob);
    }
}

/// @title PolicyEngineStakingV2_Stake_Test
/// @notice Tests the `stake` function.
contract PolicyEngineStakingV2_Stake_Test is PolicyEngineStakingV2_TestInit {
    /// @notice Tests that stake succeeds when already linked with various amounts.
    function testFuzz_stake_succeeds(uint256 _amount) external {
        _amount = bound(_amount, 1, 500 ether);

        _stakeAndLink(alice, 100 ether, alice);

        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), _amount);

        vm.expectEmit(address(staking));
        emit EffectiveStakeChanged(alice, 100 ether + _amount);
        vm.expectEmit(address(staking));
        emit Staked(alice, _amount);

        vm.prank(alice);
        staking.stake(_amount);

        (uint256 staked, address linkedTo) = staking.stakingData(alice);
        assertEq(staked, 100 ether + _amount);
        assertEq(linkedTo, alice);
        (uint128 effectiveStake,) = staking.peData(alice);
        assertEq(effectiveStake, 100 ether + _amount);
    }

    /// @notice Tests that stake adds to linked beneficiary's PE.
    function test_stake_addsToBeneficiaryPE_succeeds() external {
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);
        _stakeAndLink(alice, 100 ether, bob);

        _stake(alice, 50 ether);

        (uint256 staked,) = staking.stakingData(alice);
        assertEq(staked, 150 ether);
        (uint128 bobEffective,) = staking.peData(bob);
        assertEq(bobEffective, 150 ether);
    }

    /// @notice Tests that stake reverts when not linked.
    function test_stake_notLinked_reverts() external {
        vm.prank(alice);
        IERC20(Predeploys.GOVERNANCE_TOKEN).approve(address(staking), 100 ether);

        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_NotLinked.selector);
        vm.prank(alice);
        staking.stake(100 ether);
    }

    /// @notice Tests that stake reverts with zero amount.
    function test_stake_zeroAmount_reverts() external {
        _stakeAndLink(alice, 100 ether, alice);

        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_ZeroAmount.selector);
        staking.stake(0);
    }

}

/// @title PolicyEngineStakingV2_Unstake_Test
/// @notice Tests the `unstake` function.
contract PolicyEngineStakingV2_Unstake_Test is PolicyEngineStakingV2_TestInit {
    /// @notice Tests that full unstake succeeds, auto-unlinks, and preserves balance.
    function testFuzz_unstake_full_succeeds(uint256 _amount) external {
        _amount = bound(_amount, 1, 1_000 ether);

        _stakeAndLink(alice, _amount, alice);

        uint256 aliceBalanceBefore = IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice);

        vm.expectEmit(address(staking));
        emit EffectiveStakeChanged(alice, 0);
        vm.expectEmit(address(staking));
        emit Unlinked(alice, alice);
        vm.expectEmit(address(staking));
        emit Unstaked(alice, _amount);

        vm.prank(alice);
        staking.unstake(_amount);

        (uint256 aliceStaked, address linkedTo) = staking.stakingData(alice);
        assertEq(aliceStaked, 0);
        assertEq(linkedTo, address(0));
        assertEq(IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice), aliceBalanceBefore + _amount);
    }

    /// @notice Tests that unstake with zero amount reverts.
    function test_unstake_zeroAmount_reverts() external {
        _stakeAndLink(alice, 100 ether, alice);

        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_ZeroAmount.selector);
        staking.unstake(0);
    }

    /// @notice Tests that unstake with no stake reverts.
    function test_unstake_noStake_reverts() external {
        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_InsufficientStake.selector);
        staking.unstake(100 ether);
    }

    /// @notice Tests that unstake more than staked reverts.
    function test_unstake_insufficientStake_reverts() external {
        _stakeAndLink(alice, 100 ether, alice);

        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_InsufficientStake.selector);
        staking.unstake(101 ether);
    }

    /// @notice Tests partial unstake preserves correct remaining balance.
    function testFuzz_unstake_partialAmount_succeeds(uint256 _stakeAmount, uint256 _unstakeAmount) external {
        _stakeAmount = bound(_stakeAmount, 2, 1_000 ether);
        _unstakeAmount = bound(_unstakeAmount, 1, _stakeAmount - 1);

        _stakeAndLink(alice, _stakeAmount, alice);
        vm.prank(alice);
        staking.unstake(_unstakeAmount);

        (uint256 staked, address linkedTo) = staking.stakingData(alice);
        assertEq(staked, _stakeAmount - _unstakeAmount);
        assertEq(linkedTo, alice);
        (uint128 effective,) = staking.peData(alice);
        assertEq(effective, _stakeAmount - _unstakeAmount);
    }

    /// @notice Tests partial unstake with beneficiary preserves remaining stake attribution.
    function testFuzz_unstake_partialWithBeneficiary_succeeds(uint256 _stakeAmount, uint256 _unstakeAmount) external {
        _stakeAmount = bound(_stakeAmount, 2, 1_000 ether);
        _unstakeAmount = bound(_unstakeAmount, 1, _stakeAmount - 1);

        vm.prank(bob);
        staking.setAllowedStaker(alice, true);

        _stakeAndLink(alice, _stakeAmount, bob);
        vm.prank(alice);
        staking.unstake(_unstakeAmount);

        uint256 remaining = _stakeAmount - _unstakeAmount;
        (uint256 staked, address linkedTo) = staking.stakingData(alice);
        assertEq(staked, remaining);
        assertEq(linkedTo, bob);
        (uint128 bobEffective,) = staking.peData(bob);
        assertEq(bobEffective, remaining);
    }
}

/// @title PolicyEngineStakingV2_Link_Test
/// @notice Tests the `link` function.
contract PolicyEngineStakingV2_Link_Test is PolicyEngineStakingV2_TestInit {
    /// @notice Tests that linking to a beneficiary succeeds.
    function test_link_succeeds() external {
        uint256 amount = 100 ether;
        _stakeAndLink(alice, amount, alice);

        vm.prank(bob);
        staking.setAllowedStaker(alice, true);

        vm.expectEmit(address(staking));
        emit EffectiveStakeChanged(alice, 0);
        vm.expectEmit(address(staking));
        emit Unlinked(alice, alice);
        vm.expectEmit(address(staking));
        emit EffectiveStakeChanged(bob, amount);
        vm.expectEmit(address(staking));
        emit Linked(alice, bob);

        vm.prank(alice);
        staking.link(bob);

        (uint256 staked, address linkedTo) = staking.stakingData(alice);
        assertEq(staked, amount);
        assertEq(linkedTo, bob);
        (uint128 aliceEffective,) = staking.peData(alice);
        assertEq(aliceEffective, 0);
        (uint128 bobEffective,) = staking.peData(bob);
        assertEq(bobEffective, amount);
    }

    /// @notice Tests that re-linking from one beneficiary to another succeeds.
    function test_link_relink_succeeds() external {
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);
        _stakeAndLink(alice, 100 ether, bob);

        vm.prank(carol);
        staking.setAllowedStaker(alice, true);

        vm.prank(alice);
        staking.link(carol);

        (, address linkedTo) = staking.stakingData(alice);
        assertEq(linkedTo, carol);
        (uint128 bobEffective,) = staking.peData(bob);
        assertEq(bobEffective, 0);
        (uint128 carolEffective,) = staking.peData(carol);
        assertEq(carolEffective, 100 ether);
    }

    /// @notice Tests that linking to self succeeds (no allowlist needed).
    function test_link_toSelf_succeeds() external {
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);
        _stakeAndLink(alice, 100 ether, bob);

        vm.prank(alice);
        staking.link(alice);

        (, address linkedTo) = staking.stakingData(alice);
        assertEq(linkedTo, alice);
        (uint128 aliceEffective,) = staking.peData(alice);
        assertEq(aliceEffective, 100 ether);
        (uint128 bobEffective,) = staking.peData(bob);
        assertEq(bobEffective, 0);
    }

    /// @notice Tests that linking to same beneficiary is a no-op.
    function test_link_sameBeneficiaryNoOp_succeeds() external {
        _stakeAndLink(alice, 100 ether, alice);

        (uint128 effectiveBefore, uint128 lastUpdateBefore) = staking.peData(alice);

        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        staking.link(alice);

        // PE data should be unchanged (no-op)
        (uint128 effectiveAfter, uint128 lastUpdateAfter) = staking.peData(alice);
        assertEq(effectiveAfter, effectiveBefore);
        assertEq(lastUpdateAfter, lastUpdateBefore);
    }

    /// @notice Tests that linking with zero beneficiary reverts.
    function test_link_zeroBeneficiary_reverts() external {
        _stakeAndLink(alice, 100 ether, alice);

        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_ZeroBeneficiary.selector);
        staking.link(address(0));
    }

    /// @notice Tests that linking without allowlist reverts.
    function test_link_notAllowed_reverts() external {
        _stakeAndLink(alice, 100 ether, alice);

        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_NotAllowedToLink.selector);
        staking.link(bob);
    }

    /// @notice Tests that linking with no stake reverts.
    function test_link_noStake_reverts() external {
        vm.prank(alice);
        vm.expectRevert(PolicyEngineStakingV2.PolicyEngineStakingV2_NoStake.selector);
        staking.link(bob);
    }
}

/// @title PolicyEngineStakingV2_Uncategorized_Test
/// @notice Tests view functions, public mappings, and allowlist functions.
contract PolicyEngineStakingV2_Uncategorized_Test is PolicyEngineStakingV2_TestInit {
    /// @notice Tests that owner is set correctly.
    function test_owner_succeeds() external view {
        assertEq(staking.owner(), owner);
    }

    /// @notice Tests that PE_DATA_SLOT is 0.
    function test_peDataSlot_isZero_succeeds() external view {
        assertEq(staking.PE_DATA_SLOT(), bytes32(uint256(0)));
    }

    /// @notice Tests that peData storage layout matches PE_DATA_SLOT convention.
    ///         The Policy Engine reads keccak256(abi.encode(account, PE_DATA_SLOT)).
    function test_peData_storageLayout_succeeds() external {
        uint256 amount = 100 ether;
        _stakeAndLink(alice, amount, alice);

        bytes32 slot = keccak256(abi.encode(alice, staking.PE_DATA_SLOT()));
        bytes32 raw = vm.load(address(staking), slot);

        // Packed: effectiveStake (lower 128 bits) | lastUpdate (upper 128 bits)
        uint128 effectiveStake = uint128(uint256(raw));
        uint128 lastUpdate = uint128(uint256(raw) >> 128);

        assertEq(effectiveStake, amount);
        assertEq(lastUpdate, block.timestamp);
    }

    /// @notice Tests that setAllowedStaker updates allowlist correctly.
    function test_setAllowedStaker_succeeds() external {
        (bool allowed) = staking.allowlist(bob, alice);
        assertFalse(allowed);

        vm.expectEmit(address(staking));
        emit BeneficiaryAllowlistUpdated(bob, alice, true);

        vm.prank(bob);
        staking.setAllowedStaker(alice, true);

        (allowed) = staking.allowlist(bob, alice);
        assertTrue(allowed);

        vm.prank(bob);
        staking.setAllowedStaker(alice, false);

        (allowed) = staking.allowlist(bob, alice);
        assertFalse(allowed);
    }

    /// @notice Tests that setAllowedStakers batch updates allowlist.
    function test_setAllowedStakers_succeeds() external {
        address[] memory stakers = new address[](2);
        stakers[0] = alice;
        stakers[1] = carol;

        vm.prank(bob);
        staking.setAllowedStakers(stakers, true);

        (bool aliceAllowed) = staking.allowlist(bob, alice);
        (bool carolAllowed) = staking.allowlist(bob, carol);
        assertTrue(aliceAllowed);
        assertTrue(carolAllowed);

        vm.prank(bob);
        staking.setAllowedStakers(stakers, false);

        (aliceAllowed) = staking.allowlist(bob, alice);
        (carolAllowed) = staking.allowlist(bob, carol);
        assertFalse(aliceAllowed);
        assertFalse(carolAllowed);
    }
}

/// @title PolicyEngineStakingV2_Integration_Test
/// @notice Integration tests for the full stakeAndLink/link/unstake flow.
contract PolicyEngineStakingV2_Integration_Test is PolicyEngineStakingV2_TestInit {
    /// @notice Tests full flow: stakeAndLink -> stake more -> link to other -> partial unstake -> full unstake.
    function test_fullFlow_succeeds() external {
        // Step 1: Alice stakes 100 to self
        _stakeAndLink(alice, 100 ether, alice);
        (uint256 staked,) = staking.stakingData(alice);
        assertEq(staked, 100 ether);

        // Step 2: Alice stakes 50 more (using stake)
        _stake(alice, 50 ether);
        (staked,) = staking.stakingData(alice);
        assertEq(staked, 150 ether);

        // Step 3: Alice re-links to bob
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);
        vm.prank(alice);
        staking.link(bob);

        (, address linkedTo) = staking.stakingData(alice);
        assertEq(linkedTo, bob);
        (uint128 bobEff,) = staking.peData(bob);
        assertEq(bobEff, 150 ether);
        (uint128 aliceEff,) = staking.peData(alice);
        assertEq(aliceEff, 0);

        // Step 4: Partial unstake
        vm.prank(alice);
        staking.unstake(50 ether);
        (staked, linkedTo) = staking.stakingData(alice);
        assertEq(staked, 100 ether);
        assertEq(linkedTo, bob);
        (bobEff,) = staking.peData(bob);
        assertEq(bobEff, 100 ether);

        // Step 5: Full unstake (auto-unlinks)
        uint256 aliceBalanceBefore = IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice);
        vm.prank(alice);
        staking.unstake(100 ether);
        assertEq(IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice), aliceBalanceBefore + 100 ether);
        (staked, linkedTo) = staking.stakingData(alice);
        assertEq(staked, 0);
        assertEq(linkedTo, address(0));
        (bobEff,) = staking.peData(bob);
        assertEq(bobEff, 0);
    }

    /// @notice Tests that multiple stakers can stake to the same beneficiary.
    function test_multipleStakersToSameBeneficiary_succeeds() external {
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);
        vm.prank(bob);
        staking.setAllowedStaker(carol, true);

        _stakeAndLink(alice, 100 ether, bob);
        _stakeAndLink(carol, 50 ether, bob);

        (uint128 bobEffective,) = staking.peData(bob);
        assertEq(bobEffective, 150 ether);
    }

    /// @notice Tests that a beneficiary with own stake plus received stake has correct effective stake.
    function test_beneficiaryWithOwnStakeAndReceived_succeeds() external {
        _stakeAndLink(bob, 50 ether, bob);
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);
        _stakeAndLink(alice, 100 ether, bob);

        (uint256 bobStaked,) = staking.stakingData(bob);
        assertEq(bobStaked, 50 ether);
        (uint128 bobEffective,) = staking.peData(bob);
        assertEq(bobEffective, 150 ether);
    }

    /// @notice Tests that revoking allowlist does not auto-unlink: staker keeps link until explicit action.
    function test_revokeAllowlist_stakeRemainsUntilUnstake_succeeds() external {
        vm.prank(alice);
        staking.setAllowedStaker(bob, true);
        _stakeAndLink(bob, 100 ether, alice);

        (uint256 bobStaked, address bobLinkedTo) = staking.stakingData(bob);
        (uint128 aliceEffective,) = staking.peData(alice);
        assertEq(bobStaked, 100 ether);
        assertEq(bobLinkedTo, alice);
        assertEq(aliceEffective, 100 ether);

        vm.prank(alice);
        staking.setAllowedStaker(bob, false);

        // Bob stays linked - stake and effective power remain with Alice
        (bobStaked, bobLinkedTo) = staking.stakingData(bob);
        (aliceEffective,) = staking.peData(alice);
        assertEq(bobStaked, 100 ether);
        assertEq(bobLinkedTo, alice);
        assertEq(aliceEffective, 100 ether);

        // Bob fully unstakes (auto-unlinks)
        vm.prank(bob);
        staking.unstake(100 ether);

        (bobStaked, bobLinkedTo) = staking.stakingData(bob);
        (aliceEffective,) = staking.peData(alice);
        assertEq(bobStaked, 0);
        assertEq(bobLinkedTo, address(0));
        assertEq(aliceEffective, 0);
    }

    /// @notice Tests that lastUpdate is updated after new staking and linking when time advances.
    function test_lastUpdate_updatesAfterStakingAndLinking_succeeds() external {
        // Initial stake
        _stakeAndLink(alice, 100 ether, alice);
        (, uint128 lastUpdate0) = staking.peData(alice);
        uint256 ts0 = block.timestamp;
        assertEq(lastUpdate0, ts0);

        // Warp time and stake again; lastUpdate should advance
        vm.warp(block.timestamp + 1);
        _stake(alice, 50 ether);
        (, uint128 lastUpdate1) = staking.peData(alice);
        assertEq(lastUpdate1, ts0 + 1);

        // Warp time and link to bob; bob's lastUpdate should be the new timestamp
        vm.warp(block.timestamp + 1);
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);
        vm.prank(alice);
        staking.link(bob);
        (, uint128 bobLastUpdate) = staking.peData(bob);
        assertEq(bobLastUpdate, ts0 + 2);
    }

    /// @notice Tests that stakeAndLink after full unstake works (re-entry into system).
    function test_stakeAndLink_afterFullUnstake_succeeds() external {
        _stakeAndLink(alice, 100 ether, alice);
        vm.prank(alice);
        staking.unstake(100 ether);

        (uint256 staked, address linkedTo) = staking.stakingData(alice);
        assertEq(staked, 0);
        assertEq(linkedTo, address(0));

        // Re-enter with a different beneficiary
        vm.prank(bob);
        staking.setAllowedStaker(alice, true);
        _stakeAndLink(alice, 50 ether, bob);

        (staked, linkedTo) = staking.stakingData(alice);
        assertEq(staked, 50 ether);
        assertEq(linkedTo, bob);
        (uint128 bobEffective,) = staking.peData(bob);
        assertEq(bobEffective, 50 ether);
    }

    /// @notice Tests stake to beneficiary and full unstake preserves staker balance.
    function testFuzz_stakeToBeneficiaryAndUnstake_succeeds(uint256 _amount) external {
        _amount = bound(_amount, 1, 1_000 ether);

        vm.prank(bob);
        staking.setAllowedStaker(alice, true);

        uint256 balanceBefore = IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice);
        _stakeAndLink(alice, _amount, bob);
        vm.prank(alice);
        staking.unstake(_amount);
        uint256 balanceAfter = IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice);

        assertEq(balanceAfter, balanceBefore);
        (uint256 aliceStaked, address linkedTo) = staking.stakingData(alice);
        assertEq(aliceStaked, 0);
        assertEq(linkedTo, address(0));
        (uint128 bobEffective,) = staking.peData(bob);
        assertEq(bobEffective, 0);
    }

    /// @notice Tests stakeAndLink -> link -> unstake full cycle.
    function testFuzz_linkCycle_succeeds(uint256 _amount) external {
        _amount = bound(_amount, 1, 1_000 ether);

        vm.prank(bob);
        staking.setAllowedStaker(alice, true);

        uint256 balanceBefore = IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice);
        _stakeAndLink(alice, _amount, alice);
        vm.prank(alice);
        staking.link(bob);

        (uint128 bobEff,) = staking.peData(bob);
        assertEq(bobEff, _amount);

        vm.prank(alice);
        staking.unstake(_amount);
        uint256 balanceAfter = IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice);

        assertEq(balanceAfter, balanceBefore);
    }

    /// @notice Tests multiple stakeAndLink calls and single full unstake.
    function testFuzz_multipleStakesAndUnstake_succeeds(
        uint256 _amount1,
        uint256 _amount2,
        uint256 _amount3
    )
        external
    {
        _amount1 = bound(_amount1, 1, 300 ether);
        _amount2 = bound(_amount2, 1, 300 ether);
        _amount3 = bound(_amount3, 1, 300 ether);

        uint256 total = _amount1 + _amount2 + _amount3;

        uint256 balanceBefore = IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice);
        _stakeAndLink(alice, _amount1, alice);
        _stakeAndLink(alice, _amount2, alice);
        _stakeAndLink(alice, _amount3, alice);

        (uint256 staked,) = staking.stakingData(alice);
        (uint128 effective,) = staking.peData(alice);
        assertEq(staked, total);
        assertEq(effective, total);

        vm.prank(alice);
        staking.unstake(total);
        assertEq(IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(alice), balanceBefore);
    }

    /// @notice Tests stakeAndLink with different staker-beneficiary pairs.
    function testFuzz_stakeToBeneficiaryDifferentAccounts_succeeds(
        uint8 _stakerIdx,
        uint8 _beneficiaryIdx,
        uint256 _amount
    )
        external
    {
        address[] memory accounts = _accounts();
        _stakerIdx = uint8(bound(_stakerIdx, 0, 2));
        _beneficiaryIdx = uint8(bound(_beneficiaryIdx, 0, 2));
        if (_stakerIdx == _beneficiaryIdx) return; // self-attribution, skip
        address staker = accounts[_stakerIdx];
        address beneficiary = accounts[_beneficiaryIdx];
        _amount = bound(_amount, 1, 300 ether);

        vm.prank(beneficiary);
        staking.setAllowedStaker(staker, true);

        uint256 balanceBefore = IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(staker);
        _stakeAndLink(staker, _amount, beneficiary);
        vm.prank(staker);
        staking.unstake(_amount);
        uint256 balanceAfter = IERC20(Predeploys.GOVERNANCE_TOKEN).balanceOf(staker);

        assertEq(balanceAfter, balanceBefore);
        (uint128 benEffective,) = staking.peData(beneficiary);
        assertEq(benEffective, 0);
    }

    function _accounts() internal view returns (address[] memory) {
        address[] memory a = new address[](3);
        a[0] = alice;
        a[1] = bob;
        a[2] = carol;
        return a;
    }
}
