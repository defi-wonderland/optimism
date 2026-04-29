# ZKDisputeGame — Audit PoCs

Two Medium-severity findings against `src/dispute/zk/ZKDisputeGame.sol`,
each with a passing Forge proof-of-concept. Both findings share a root cause
and a single combined fix closes them.

```sh
cd packages/contracts-bedrock
DEV_FEATURE__ZK_DISPUTE_GAME=true forge test --match-path 'test/dispute/zk/poc/*'
```

> 3 tests · all pass.

---

## TL;DR

`ZKDisputeGame.prove()` is a permissionless terminal-state-committing
operation, but the contract uses two pieces of weak input as preconditions:
the *identity* of the caller (which it then promotes into bond-distribution
logic) and the *current* status of the parent game (which can change
afterwards). Each weakness produces a Medium finding:

- **M-01** — anyone, including the challenger, can call `prove()` and steal
  the bonus bond that the proposer was supposed to earn for defending
  their valid claim.
- **M-02** — anyone, including the proposer, can call `prove()` while the
  parent is still in flight, locking out future challengers; if the parent
  later turns out to be bad, the bonds that should have rewarded the
  honest challenger get burned to `address(0)`.

The combined fix is a 5-line patch on a new impl: always credit the
proposer's bonus to `gameCreator()` regardless of who proves, and reject
`prove()` while parent is `IN_PROGRESS`.

---

## Background — what this contract is supposed to do

`ZKDisputeGame` is a ZK-validity dispute game in the OP Stack's fault-proof
system. A *proposer* posts a claim about the L2 state at some sequence
number, putting up `initBond`. Anyone can *challenge* by putting up
`challengerBond`. A *prover* later submits a ZK proof that the claim is
correct (verified on-chain by an `IZKVerifier`). After a deadline, anyone
calls `resolve()` and the contract pays bonds out according to who was
right.

The contract distinguishes three roles intentionally:
- **Proposer** = `gameCreator()` — set at game creation, immutable via CWIA.
- **Challenger** = `claimData.challenger` — set when someone calls
  `challenge()`.
- **Prover** = `claimData.prover` — set when someone calls `prove()`. The
  contract permits the prover to be a different account than the
  proposer, so a third party can earn a reward by doing the proof work
  on behalf of an honest-but-busy proposer.

### Intended bond economics

Every game ends in one of these terminal states. Below is the *intended*
distribution per the resolve() branches at lines 478–516:

| Terminal | Triggering condition | proposer | challenger | prover (if ≠ proposer) |
|---|---|---|---|---|
| `Unchallenged` after deadline | nobody challenged, nobody proved | **`totalBonds`** (= `initBond`) | — | — |
| `UnchallengedAndValidProofProvided` | proposer proved unopposed | **`totalBonds`** (= `initBond`) | — | 0 |
| `Challenged` after deadline | challenger posted, nobody proved | 0 | **`totalBonds`** (= `initBond + challengerBond`) | — |
| `ChallengedAndValidProofProvided`, prover = proposer | proposer defended their claim | **`totalBonds`** | 0 | — |
| `ChallengedAndValidProofProvided`, prover ≠ proposer | third party defended | `initBond` | 0 | **`challengerBond`** ⚠ |
| Parent `CHALLENGER_WINS` | child invalidated by parent failing | 0 | **`totalBonds`** | 0 |

The two ⚠ rows below (M-01 and M-02) are where the design intent breaks down.

### State machine

`prove()` is a one-shot transition that moves the game to a terminal
proof-bearing state (`...AndValidProofProvided`). After it lands,
`gameOver()` returns true, blocking any subsequent `challenge()`:

```
  newGame
     │
     │ initialize()
     ▼
  Unchallenged ──── prove() ────▶ UnchallengedAndValidProofProvided
     │                                │
     │ challenge()                    │
     ▼                                │
  Challenged ────── prove() ─────▶ ChallengedAndValidProofProvided
     │                                │
     │ deadline reached               │
     ▼                                ▼
                  resolve()
                     │
                     ▼
        DEFENDER_WINS  /  CHALLENGER_WINS
                     │
                     ▼
                  Resolved (terminal)
```

Two facts about this state machine matter for the findings:

1. **`prove()` accepts at most once.** Once `claimData.prover != address(0)`,
   `gameOver()` is true (`L644`) and `challenge()` reverts at `L377`. The
   first prover to land controls the post-resolution bond split.

2. **`prove()` only checks `parent.status() != CHALLENGER_WINS`** at `L411`.
   It accepts parents that are still `IN_PROGRESS`, even though the
   contract's resolve()-time logic at `L471–477` later treats parent
   CHALLENGER_WINS as invalidating the child entirely.

These two facts compose into the shared architectural seam.

---

## The shared architectural seam

`prove()` commits the game to a terminal state on weak input:

| Input it depends on | Weakness |
|---|---|
| `msg.sender`, baked into `publicValues` and into `claimData.prover` | Whoever lands first wins the bond split. Permissionless. |
| `getParentGameStatus()` returns `IN_PROGRESS` | The parent's eventual outcome is *unknown* at prove-time. The contract treats "not yet CHALLENGER_WINS" as "permitted to prove." |

The verifier itself is honest in both cases — it attests only to a *local*
L2 transition (`startingProposal.root → rootClaim` for `l2SequenceNumber`).
It cannot tell the contract anything about who *should* be rewarded or
whether the parent is valid. The contract has to enforce those properties
in its own state machine, and it currently doesn't.

The two findings are the two ways an attacker can exploit this seam:

- **M-01** weaponises the `msg.sender` half: the attacker submits a valid
  proof under their own address to redirect the bond split.
- **M-02** weaponises the parent-status half: the attacker proves before
  the parent has settled, denying any challenger the chance to land.

A single new impl that tightens both checks closes both findings.

---

## [M-01] Permissionless prover race denies the proposer's `challengerBond` bonus

**Severity:** Medium · **Location:** `ZKDisputeGame.sol:406–435, 497–511` ·
**Class:** Economic griefing / state-machine misuse

### The mechanism

In the `ChallengedAndValidProofProvided` resolve() branch (the *only* path
where prover identity matters), the credit allocation depends on whether
the prover equals the proposer:

```solidity
// ZKDisputeGame.sol:497–511
} else if (claimData.status == ProposalStatus.ChallengedAndValidProofProvided) {
    status = GameStatus.DEFENDER_WINS;

    if (claimData.prover == gameCreator()) {
        normalModeCredit[claimData.prover] = totalBonds;          // proposer takes everything
    } else {
        normalModeCredit[claimData.prover]    = challengerBond(); // prover pockets challengerBond
        normalModeCredit[gameCreator()]       = totalBonds - challengerBond();
        // proposer left with only initBond — denied the bonus they would have earned.
    }
}
```

`prove()` is permissionless (`L406–410`), and `claimData.prover` is set to
`msg.sender` (`L424`). So **any account that lands `prove()` first becomes
the prover-of-record**, including the very party who challenged the game
in the first place.

### Walkthrough — challenger-as-prover

This is the cleanest demonstration: the challenger themselves runs the
attack, with no third-party coordination required. (The PoC at
`ZKDeepReview_DR01.t.sol::test_dr01_challengerAsProver_griefsProposer`
implements exactly this.)

1. **Setup.** Alice (proposer) creates a game `G` with a valid claim
   about the L2 state. She posts `initBond`.
2. **Bob challenges.** Bob calls `challenge()` and posts `challengerBond`.
   `claimData.challenger = Bob`. `claimData.status = Challenged`. The
   game is now in the contested state where, if Alice or someone else
   proves, the proposer gets paid.
3. **Bob proves himself.** In the same block (or any block before Alice
   gets there), Bob calls `prove(_proofBytes)`. Anyone with witness data
   can produce the proof; if Bob was already willing to challenge an
   honest claim, he had to expect the witness to exist. The verifier
   accepts because the claim *is* valid.
   `claimData.prover = Bob`. `claimData.status =
   ChallengedAndValidProofProvided`.
4. **Deadline passes; anyone calls `resolve()`.** Branch is
   `ChallengedAndValidProofProvided`, prover ≠ gameCreator, so
   `normalModeCredit[Bob] = challengerBond` and
   `normalModeCredit[Alice] = initBond`.
5. **Net result:** Bob recovers his full `challengerBond` (he's both
   challenger and prover, but the credit assignment at L509 just
   overwrites the slot — challenger refund logic doesn't apply here
   because the game ended `DEFENDER_WINS`, not `Challenged`). His total
   cost was gas + proof generation. Alice's expected return was
   `totalBonds`; her actual return is `initBond`. **She is short
   `challengerBond`.**

### Economic ledger

| Party | Pre-attack balance change | Post-attack balance change |
|---|---|---|
| Alice (proposer) | `+totalBonds` (= `initBond + challengerBond`) | `+initBond` only |
| Bob (challenger AND prover) | `−challengerBond − gas` | `−gas − proof_gen` (full bond returned) |

`challengerBond` evaporates from Alice's expected reward and re-lands at
Bob, who paid for the privilege of doing nothing harmful.

### Why this is a real harm, not just an accounting curiosity

The protocol promises proposers a `challengerBond` bonus for defending a
valid claim against a frivolous challenge. That promise is the entire
economic basis for `challengerBond` existing — it's slashing collateral
posted by the challenger to deter wasted disputes. Under M-01, the bond
becomes a *refundable deposit*: the challenger always recovers it,
regardless of whether their challenge was justified, by simply self-proving
the claim they just challenged. The "skin in the game" property is gone.

Practical consequences:
- A bot watching the mempool for valid proposals can challenge each one,
  self-prove, and net out at gas cost. The proposer is short
  `challengerBond` per game.
- Honest proposers' expected revenue from running a proposer service
  drops by `challengerBond × challenge_rate`. On any production
  deployment with non-trivial bonds, this is material.
- The system retains liveness (proofs still resolve correctly), but the
  game-theoretic incentive to challenge *only* invalid claims is broken.

### Why Medium, not High

- No direct theft of bonds the attacker hadn't already posted — Bob
  recovers his own deposit, he doesn't drain Alice's.
- The economic harm to Alice is bounded by `challengerBond` per game,
  not Alice's full bond.
- The pattern is permissionless and repeatable, so cumulative harm scales
  with `challenge_rate × challengerBond × number_of_games` — a real
  protocol-economics problem, but not a single-tx fund drain.

### Mitigation

The intent of the `prover != proposer` branch is to incentivise *third
parties* to do proof work for honest-but-offline proposers — a backstop,
not a wedge. The cleanest fix is to remove the wedge by paying the
proposer regardless of who supplies the proof:

```diff
 } else if (claimData.status == ProposalStatus.ChallengedAndValidProofProvided) {
     status = GameStatus.DEFENDER_WINS;
-    if (claimData.prover == gameCreator()) {
-        normalModeCredit[claimData.prover] = totalBonds;
-    } else {
-        normalModeCredit[claimData.prover]    = challengerBond();
-        normalModeCredit[gameCreator()]       = totalBonds - challengerBond();
-    }
+    // Defender wins: proposer always takes the full pot. If a third party
+    // did the proof work, they can be compensated out-of-band — coupling
+    // their reward to the challenger's bond turned the bond into a free
+    // option for the challenger themselves.
+    normalModeCredit[gameCreator()] = totalBonds;
 }
```

If the third-party-prover incentive is important to keep, replace it with
a fixed reward funded outside the bond pool (e.g., a bounty paid by the
proposer at game-creation time as a separate immutable). What it must
*not* be is a slice of the challenger's deposit, because that creates the
self-prove loophole.

---

## [M-02] Early prover front-runs challenge window; bonds burn to `address(0)` when parent resolves CHALLENGER_WINS

**Severity:** Medium · **Location:** `ZKDisputeGame.sol:329, 411, 471–477, 644` ·
**Class:** State-machine griefing / loss-of-funds

### The mechanism

Three pieces of contract logic compose:

1. **`initialize()` permits parents in `IN_PROGRESS` state.** Line 329
   only rejects parents that have *already* resolved `CHALLENGER_WINS`:

   ```solidity
   // ZKDisputeGame.sol:329
   if (parent.status() == GameStatus.CHALLENGER_WINS) revert InvalidParentGame();
   ```

   An `IN_PROGRESS` parent passes. This is necessary for proposer
   pipelining (you don't want to wait for the full clock before chaining
   the next claim) but it means the parent's eventual outcome is unknown
   at child-creation time.

2. **`prove()` permits parents in `IN_PROGRESS` state.** Line 411 also
   only blocks `CHALLENGER_WINS`:

   ```solidity
   // ZKDisputeGame.sol:411
   if (getParentGameStatus() == GameStatus.CHALLENGER_WINS) revert InvalidParentGame();
   ```

   The verifier is honest about the *local* L2 transition, but the
   contract decides whether to let the prover commit *now* or wait.
   Currently it lets them commit now.

3. **`gameOver()` flips on first prove.** Line 644:

   ```solidity
   // ZKDisputeGame.sol:644
   gameOver_ = claimData.deadline.raw() < uint64(block.timestamp)
            || claimData.prover != address(0);
   ```

   After `prove()` succeeds, any subsequent `challenge()` reverts at L377.
   The challenge window is closed early, and **stays closed** for the
   rest of the game's life.

When `(1) + (2) + (3)` compose with the resolve-time parent-check at
L471–477, you get a path where bonds get sent to the zero address:

```solidity
// ZKDisputeGame.sol:467–477
GameStatus parentGameStatus = getParentGameStatus();
if (parentGameStatus == GameStatus.IN_PROGRESS) revert ParentGameNotResolved();

if (parentGameStatus == GameStatus.CHALLENGER_WINS) {
    status = GameStatus.CHALLENGER_WINS;
    normalModeCredit[claimData.challenger] = totalBonds;  // ← claimData.challenger may be address(0)
}
```

Note resolve() *does* check that the parent has settled before it runs.
But by then, prove() has already committed the game to a state where
`claimData.challenger` is still its zero default — because the early
prover prevented anyone from filling that slot.

### Walkthrough — speculative early-prove on a doubtful parent

The PoCs at `ZKDeepReview_DR02.t.sol::test_dr02_earlyProveLocksOutChallenger`
and `::test_dr02_fullAttackBondsBurnedToZeroAddress` implement this end-to-end.

1. **Setup.** Parent game `P` is `IN_PROGRESS`. Its eventual outcome is
   unknown to the network. (For the attack to bite, `P` will eventually
   resolve `CHALLENGER_WINS`, but the attacker doesn't need certainty
   about that — see "Why bother attacking?" below.)
2. **Adversary creates child `C`.** They post `initBond` and set
   `parentIndex = P`. `initialize()` accepts at L329 because
   `P.status() == IN_PROGRESS` (not `CHALLENGER_WINS`). The local L2
   transition `(P.rootClaim → C.rootClaim)` will be valid as far as the
   verifier is concerned, even if `P.rootClaim` is itself a lie.
3. **Adversary proves immediately.** They call `prove(_proofBytes)`.
   Verifier accepts the local transition. `claimData.prover = adversary`,
   `claimData.status = UnchallengedAndValidProofProvided`. `gameOver()`
   flips to true.
4. **Challenge window is now permanently closed.** Anyone trying to
   challenge `C` reverts at L377. `claimData.challenger` remains
   `address(0)`.
5. **Some time later, `P` resolves `CHALLENGER_WINS`.** The parent was
   bad after all.
6. **Anyone calls `resolve()` on `C`.** Parent-status branch at L471–477
   triggers: `status = CHALLENGER_WINS`, `normalModeCredit[address(0)] =
   totalBonds`.
7. **`totalBonds` (= `initBond`, since no challengerBond was ever posted)
   is now stuck at the zero address**, recoverable only via the
   DelayedWETH guardian's `hold()/recover()` flow.

### Economic ledger

| Party | Cost | Outcome |
|---|---|---|
| Adversary (proposer + early prover) | `initBond + gas + proof_gen` | Loses `initBond` (sent to address(0)). No direct reward. |
| Honest challenger who *would* have caught the bad child | `0` (couldn't deposit anything) | Loses their *expected* `totalBonds` reward. The reward is destroyed, not redirected. |
| Protocol | — | `initBond` worth of value sent to address(0); challenger-incentive mechanism broken for any child whose parent is IN_PROGRESS at prove-time. |

### Why bother attacking? — the attacker's calculus

An attacker willing to lose `initBond + gas + proof_gen` can grief the
protocol, but the more interesting case is **speculative**:

- Adversary creates a child over a parent whose validity is in genuine
  dispute. Adversary believes (or accepts the risk) that the parent
  might resolve `CHALLENGER_WINS`.
- Adversary proves the child immediately. Two branches:
  - If `P` resolves **`DEFENDER_WINS`**, adversary's child also resolves
    `DEFENDER_WINS` (`UnchallengedAndValidProofProvided` branch),
    `normalModeCredit[gameCreator] = totalBonds`, adversary recovers
    their `initBond` cleanly. **Net cost: gas + proof_gen.**
  - If `P` resolves **`CHALLENGER_WINS`**, the path described above
    triggers, adversary loses `initBond`, but the *expected* challenger
    reward for `C` is now zero (it went to address(0)). **The challenger
    market is denied a reward, asymmetrically.**

Generalised: an attacker who runs the speculative-child strategy at scale
across N parents pays at most `loss_rate × initBond × N` while denying
the challenger market `totalBonds × loss_rate × N` worth of expected
rewards. With even modest pricing, the attacker can be a net win for the
overall *attacker class* while individual attackers may lose. More
importantly, the attack systematically suppresses challenger
participation by reducing the expected return on a successful catch:
honest challengers can never reach a child whose parent is IN_PROGRESS at
the moment of an adversary's prove.

The defender-of-the-protocol view: any child created over an
in-flight parent is a node that the challenger market can be locked out
of for free, given a willing prover. Production deployments with active
provers and meaningful `initBond` values are exposed.

### Why Medium, not High

- No direct theft of attacker-foreign value: bonds go to address(0), not
  to the attacker. The attacker's own `initBond` is at risk.
- Recovery exists in principle (DelayedWETH guardian), so funds are not
  permanently lost.
- Trigger requires a specific timing window (parent IN_PROGRESS at
  prove-time and CHALLENGER_WINS at resolve-time) that's narrow but
  genuinely reachable in any active dispute network.
- Cumulative harm grows with the rate at which parents resolve
  CHALLENGER_WINS in production — could be argued either way for High,
  but the deep-review held it at Medium because the loss is denial-of-
  reward rather than redirected theft.

### Mitigation

The minimal change is to require the parent to be *finalised* before
`prove()` is willing to commit the game to a terminal state:

```diff
 function prove(bytes calldata _proofBytes) external returns (ProposalStatus) {
     if (status != GameStatus.IN_PROGRESS) revert ClaimAlreadyResolved();

-    if (getParentGameStatus() == GameStatus.CHALLENGER_WINS) revert InvalidParentGame();
+    GameStatus parentStatus = getParentGameStatus();
+    if (parentStatus == GameStatus.CHALLENGER_WINS) revert InvalidParentGame();
+    // INVARIANT: prove() commits the game to a terminal state and closes
+    // the challenge window via gameOver(). It must not run before the
+    // parent has settled, or a later parent CHALLENGER_WINS would route
+    // bonds to claimData.challenger == address(0) (the early prover
+    // having locked challengers out before any of them could deposit).
+    if (parentStatus == GameStatus.IN_PROGRESS) revert ParentGameNotResolved();
 
     if (gameOver()) revert GameOver();
     ...
 }
```

This preserves proposer-pipelining at the *initialize* level (children
can still be created over in-flight parents) while gating the
state-collapsing prove() on parent finality. Existing legitimate use
cases (a child whose parent eventually resolves DEFENDER_WINS) are only
slightly delayed: they have to wait `parent.maxClockDuration` before
proving, instead of being able to prove immediately.

If that delay is unacceptable for some operational reason, an alternative
keeps prove() permissive but stops the loss-of-funds in resolve():

```diff
 if (parentGameStatus == GameStatus.CHALLENGER_WINS) {
     status = GameStatus.CHALLENGER_WINS;
-    normalModeCredit[claimData.challenger] = totalBonds;
+    address recipient = claimData.challenger == address(0)
+        ? PROTOCOL_TREASURY  // configurable address, e.g. the OP Foundation slashing fund
+        : claimData.challenger;
+    normalModeCredit[recipient] = totalBonds;
 }
```

This stops the burn-to-`address(0)` outcome but doesn't restore the
challenger-incentive (no challenger ever got to compete). The prove()
guard is the cleaner fix.

---

## Combined fix

A single new `ZKDisputeGame` impl that includes both diffs above closes
M-01 and M-02. Re-register via `DisputeGameFactory.setImplementation` (or
in production via OPCM's `upgrade()`). Existing in-flight games are not
affected — the change applies only to games created after the new impl
is registered, because the impl is the source of CWIA bytecode for new
clones.

```diff
--- a/src/dispute/zk/ZKDisputeGame.sol
+++ b/src/dispute/zk/ZKDisputeGame.sol
@@ -408,7 +408,9 @@ contract ZKDisputeGame is Clone, ISemver, IDisputeGame {
     function prove(bytes calldata _proofBytes) external returns (ProposalStatus) {
         if (status != GameStatus.IN_PROGRESS) revert ClaimAlreadyResolved();
 
-        if (getParentGameStatus() == GameStatus.CHALLENGER_WINS) revert InvalidParentGame();
+        GameStatus parentStatus = getParentGameStatus();
+        if (parentStatus == GameStatus.CHALLENGER_WINS) revert InvalidParentGame();
+        if (parentStatus == GameStatus.IN_PROGRESS)     revert ParentGameNotResolved();
 
         if (gameOver()) revert GameOver();
@@ -494,12 +496,8 @@
             } else if (claimData.status == ProposalStatus.ChallengedAndValidProofProvided) {
                 status = GameStatus.DEFENDER_WINS;
-                if (claimData.prover == gameCreator()) {
-                    normalModeCredit[claimData.prover] = totalBonds;
-                } else {
-                    normalModeCredit[claimData.prover]    = challengerBond();
-                    normalModeCredit[gameCreator()]       = totalBonds - challengerBond();
-                }
+                // Defender wins regardless of who proved. Pay the proposer the full pot.
+                normalModeCredit[gameCreator()] = totalBonds;
             }
```

After the patch, `forge test --match-path 'test/dispute/zk/poc/*'`
should *fail* — both PoCs assert the buggy outcome, and the patch removes
that outcome. That's how you verify the fix landed: the PoCs flip from
green to red.

> Once you've validated the fix, the PoCs can stay in the repo as
> regression tests by inverting the assertions, or be retired entirely
> with the audit-fix PR.

---

## Reproduction

```sh
cd packages/contracts-bedrock
DEV_FEATURE__ZK_DISPUTE_GAME=true forge test --match-path 'test/dispute/zk/poc/*'
```

Expected output:
```
Ran 1 test for test/dispute/zk/poc/ZKDeepReview_DR01.t.sol:ZKDeepReview_DR01
[PASS] test_dr01_challengerAsProver_griefsProposer()

Ran 2 tests for test/dispute/zk/poc/ZKDeepReview_DR02.t.sol:ZKDeepReview_DR02
[PASS] test_dr02_earlyProveLocksOutChallenger()
[PASS] test_dr02_fullAttackBondsBurnedToZeroAddress()

3 tests passed, 0 failed, 0 skipped
```

Both PoC files inherit `DisputeGameFactory_TestInit` so they get the same
deployment plumbing as the in-tree ZK tests. They use `ZKMockVerifier`
(always-pass) so the proof-validity question is decoupled from the
state-machine bugs the PoCs are demonstrating.

---

## Discoveries that did **not** become findings

The deep-review pass rejected several first-pass concerns. These are
worth understanding so reviewers don't re-derive them:

- **`closeGame()` EIP-150 OOG griefing on `try setAnchorState`.** The
  `nosemgrep` annotation at L619 is correctly applied. `isGameProper`
  in `AnchorStateRegistry.sol:275–297` checks only registration,
  blacklist, retirement, and pause — it does **not** depend on
  `setAnchorState` having succeeded. A swallowed OOG inside the `try`
  block is harmless to bond distribution.
- **`publicValues` ABI vs packed encoding mismatch.** Encoding is
  `abi.encode` end-to-end (192 bytes); the SP1 program decodes the same
  way. The "172 bytes" figure that appeared in the original audit-scope
  was a counting error — `address` pads to 32 bytes in `abi.encode`.
- **Proof-replay across sibling-parented games.** Even when a single
  prover satisfies `verify()` for two sibling games sharing
  `publicValues`, each game has its own bond pool, no invariant is
  violated, and no fund flow is unauthorised. At worst it's a
  "compute-once-prove-twice" optimisation for honest provers.
- **`DelayedWETH.withdraw(_guy, _wad)` double-spend.** `DelayedWETH.sol:96–104`
  routes ETH to `msg.sender` (the game), then the game forwards via
  `_recipient.call{value}`. Single payment. No double-spend.

## Out-of-scope (per audit-scope agreement, not investigated)

- **uint64 deadline truncation** at `L350` and `L392`. With a misconfigured
  `maxChallengeDuration` or `maxProveDuration` (set in `gameArgs` at
  impl-registration time by the factory operator), `block.timestamp +
  duration` can overflow when cast to uint64, instantly making
  `gameOver()` true. Two-line fix with `SafeCast.toUint64(...)` if scope
  later expands to factory-operator misconfig.
- **Parent blacklisted post-init** — guardian flow.
- **Permissionless `closeGame` race vs guardian** — guardian flow.
- **Verifier address swap at impl registration** — factory-operator
  centralisation.

## Audit metadata

- **Source commit reference:** `ZKDisputeGame` is derived from
  `succinctlabs/op-succinct@c13844a9bbc330cca69eef2538d8f8ec123e1653`
  per the contract docstring at `L49`. M-01 and M-02 may exist upstream;
  coordinated disclosure is worth considering before merging the fix
  publicly.
- **Solidity:** `0.8.15`, Foundry-built, CWIA via Solady's `Clone`.
- **Reviewer:** evm-security-audit pipeline (sc-first-pass →
  vulnerability-scanner → deep-reviewer → poc-builder).
- **Scope confirmed with audit caller:** whole `src/dispute/zk/`
  subtree + ZK interfaces; verifier trusted; adversaries are
  proposer/challenger/prover; H/C/M floor; PoCs required for confirmed
  H/C, voluntary for M (delivered for both Mediums anyway).
- **Final counts:** 0 Critical · 0 High · 2 Medium. Lows, Informationals,
  and Gas observations were not enumerated by request.
