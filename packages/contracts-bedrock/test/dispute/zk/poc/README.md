# ZKDisputeGame — Audit PoCs

One Medium-severity finding against `src/dispute/zk/ZKDisputeGame.sol`,
with passing Forge proof-of-concept tests. A 3-line patch on a new impl
closes it.

```sh
cd packages/contracts-bedrock
DEV_FEATURE__ZK_DISPUTE_GAME=true forge test --match-path 'test/dispute/zk/poc/*'
```

> 2 tests · all pass.

---

## TL;DR

`ZKDisputeGame.prove()` accepts proofs even while the parent dispute game
is still `IN_PROGRESS`. Once `prove()` lands, `gameOver()` flips and the
challenge window is permanently closed. If the parent later resolves
`CHALLENGER_WINS`, the child's `resolve()` routes its bonds to
`claimData.challenger` — which is `address(0)` because no challenger
ever managed to deposit before the early prove. Bonds are burned to the
zero address (recoverable only via the DelayedWETH guardian) and the
honest challenger that *would* have caught the bad child gets nothing.

The fix is a single guard at the top of `prove()` requiring the parent
to be settled (`!= IN_PROGRESS`) before the function will commit the
game to a terminal state.

---

## Background — what this contract is supposed to do

`ZKDisputeGame` is a ZK-validity dispute game in the OP Stack's
fault-proof system. A *proposer* posts a claim about the L2 state at
some sequence number, putting up `initBond`. Anyone can *challenge* by
putting up `challengerBond`. A *prover* later submits a ZK proof that
the claim is correct (verified on-chain by an `IZKVerifier`). After a
deadline, anyone calls `resolve()` and the contract pays bonds out
according to who was right.

The contract distinguishes three roles intentionally:
- **Proposer** = `gameCreator()` — set at game creation, immutable via CWIA.
- **Challenger** = `claimData.challenger` — set when someone calls
  `challenge()`.
- **Prover** = `claimData.prover` — set when someone calls `prove()`.

The proposer and prover are **deliberately decoupled**: anyone with
witness data is encouraged to construct a proof of a valid root claim,
and the prover (whoever they are) earns `challengerBond` as a bounty
for the work. The proposer gets their `initBond` back; if the proposer
happens to be the same account as the prover, they take the entire pot.
This is by design, not a bug — it lets honest-but-busy proposers rely
on third-party provers without losing their initial deposit.

### Intended bond flow

| Terminal state | Triggering condition | proposer | challenger | prover (if ≠ proposer) |
|---|---|---|---|---|
| `Unchallenged` after deadline | nobody challenged, nobody proved | **`totalBonds`** (= `initBond`) | — | — |
| `UnchallengedAndValidProofProvided` | proposer (or anyone) proved unopposed | proposer or third-party prover takes pot | — | — |
| `Challenged` after deadline | challenger posted, nobody proved | 0 | **`totalBonds`** | — |
| `ChallengedAndValidProofProvided`, prover = proposer | proposer defended their claim | **`totalBonds`** | 0 | — |
| `ChallengedAndValidProofProvided`, prover ≠ proposer | third-party prover did the work | `initBond` | 0 | **`challengerBond`** (the bounty) |
| Parent `CHALLENGER_WINS` | child invalidated by parent failing | 0 | **`totalBonds`** ⚠ | 0 |

The ⚠ row at the bottom is where the finding bites: the contract assumes
`claimData.challenger` is non-zero when this branch runs, but `prove()`
can close the challenge window before any challenger gets a chance to
fill that slot.

### State machine

`prove()` is a one-shot transition that moves the game to a terminal
proof-bearing state. Once it lands, `gameOver()` returns true,
permanently blocking any subsequent `challenge()`:

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

Two facts about this state machine matter for the finding:

1. **`prove()` accepts at most once.** The first prover to land sets
   `claimData.prover`, after which `gameOver()` is true (`L644`) and
   `challenge()` reverts at `L377`.

2. **`prove()` only checks `parent.status() != CHALLENGER_WINS`** at
   `L411`. It accepts parents that are still `IN_PROGRESS`, even though
   `resolve()`'s parent-check at `L471–477` later treats parent
   `CHALLENGER_WINS` as invalidating the child entirely.

These two facts compose into the finding.

---

## [M-02] Early prover front-runs challenge window; bonds burn to `address(0)` when parent resolves CHALLENGER_WINS

**Severity:** Medium · **Location:** `ZKDisputeGame.sol:329, 411, 471–477, 644` ·
**Class:** State-machine griefing / loss-of-funds

> The "M-02" label is preserved from the deep-review pass for traceability
> with the PoC test file name (`ZKDeepReview_DR02.t.sol`). It is the only
> finding in this report.

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
`L471–477`, you get a path where bonds get sent to the zero address:

```solidity
// ZKDisputeGame.sol:467–477
GameStatus parentGameStatus = getParentGameStatus();
if (parentGameStatus == GameStatus.IN_PROGRESS) revert ParentGameNotResolved();

if (parentGameStatus == GameStatus.CHALLENGER_WINS) {
    status = GameStatus.CHALLENGER_WINS;
    normalModeCredit[claimData.challenger] = totalBonds;  // ← claimData.challenger may be address(0)
}
```

Note resolve() *does* require the parent to have settled before it runs.
But by then, prove() has already committed the game to a state where
`claimData.challenger` is still its zero default — because the early
prover prevented anyone from filling that slot.

### Walkthrough — speculative early-prove on a doubtful parent

Implemented end-to-end in `ZKDeepReview_DR02.t.sol::test_dr02_earlyProveLocksOutChallenger`
and `::test_dr02_fullAttackBondsBurnedToZeroAddress`.

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
7. **`totalBonds` (= `initBond`, since no `challengerBond` was ever
   posted) is now stuck at the zero address**, recoverable only via the
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

Generalised: an attacker who runs the speculative-child strategy at
scale across N parents pays at most `loss_rate × initBond × N` while
denying the challenger market `totalBonds × loss_rate × N` worth of
expected rewards. With even modest pricing, the attack systematically
suppresses challenger participation by reducing the expected return on
a successful catch — honest challengers can never reach a child whose
parent is IN_PROGRESS at the moment of an adversary's prove.

The defender-of-the-protocol view: any child created over an
in-flight parent is a node that the challenger market can be locked out
of for free, given a willing prover. Production deployments with active
provers and meaningful `initBond` values are exposed.

### Why Medium, not High

- No direct theft of attacker-foreign value: bonds go to address(0),
  not to the attacker. The attacker's own `initBond` is at risk.
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

If that delay is unacceptable for some operational reason, an
alternative keeps prove() permissive but stops the loss-of-funds in
resolve():

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
challenger-incentive (no challenger ever got to compete). The
prove()-side guard is the cleaner fix.

After applying the guard, `forge test --match-path 'test/dispute/zk/poc/*'`
should *fail* — the PoCs assert the buggy outcome, and the patch
removes that outcome. That's how you verify the fix landed: the PoCs
flip from green to red.

> Once you've validated the fix, the PoCs can stay in the repo as
> regression tests by inverting the assertions, or be retired with the
> audit-fix PR.

---

## Reproduction

```sh
cd packages/contracts-bedrock
DEV_FEATURE__ZK_DISPUTE_GAME=true forge test --match-path 'test/dispute/zk/poc/*'
```

Expected output:
```
Ran 2 tests for test/dispute/zk/poc/ZKDeepReview_DR02.t.sol:ZKDeepReview_DR02
[PASS] test_dr02_earlyProveLocksOutChallenger()
[PASS] test_dr02_fullAttackBondsBurnedToZeroAddress()

2 tests passed, 0 failed, 0 skipped
```

The PoC inherits `DisputeGameFactory_TestInit` so it gets the same
deployment plumbing as the in-tree ZK tests, and uses `ZKMockVerifier`
(always-pass) so the proof-validity question is decoupled from the
state-machine bug being demonstrated.

---

## Discoveries that did **not** become findings

The deep-review pass investigated and rejected several first-pass
concerns. These are worth understanding so reviewers don't re-derive
them:

- **Permissionless prover earns `challengerBond` when proposer ≠
  prover** (initially flagged as proposer-bonus theft). This is the
  *intended* design: the prover bounty incentivises anyone with
  witness data to construct a proof of a valid root claim, regardless
  of whether they are the proposer. The challenger-as-prover scenario
  (where a challenger pays `challengerBond`, then proves themselves,
  recovering their bond) is a valid economic move under this design,
  not a finding. `challengerBond` is best understood as escrow for the
  prover bounty rather than as slashable collateral against frivolous
  challenges.
- **`closeGame()` EIP-150 OOG griefing on `try setAnchorState`.** The
  `nosemgrep` annotation at L619 is correctly applied. `isGameProper`
  in `AnchorStateRegistry.sol:275–297` checks only registration,
  blacklist, retirement, and pause — it does **not** depend on
  `setAnchorState` having succeeded. A swallowed OOG inside the `try`
  block is harmless to bond distribution.
- **`publicValues` ABI vs packed encoding mismatch.** Encoding is
  `abi.encode` end-to-end (192 bytes); the SP1 program decodes the
  same way. The "172 bytes" figure that appeared in the original
  audit-scope was a counting error — `address` pads to 32 bytes in
  `abi.encode`.
- **Proof-replay across sibling-parented games.** Even when a single
  prover satisfies `verify()` for two sibling games sharing
  `publicValues`, each game has its own bond pool, no invariant is
  violated, and no fund flow is unauthorised. At worst it's a
  "compute-once-prove-twice" optimisation for honest provers.
- **`DelayedWETH.withdraw(_guy, _wad)` double-spend.**
  `DelayedWETH.sol:96–104` routes ETH to `msg.sender` (the game), then
  the game forwards via `_recipient.call{value}`. Single payment. No
  double-spend.

## Out-of-scope (per audit-scope agreement, not investigated)

- **uint64 deadline truncation** at `L350` and `L392`. With a
  misconfigured `maxChallengeDuration` or `maxProveDuration` (set in
  `gameArgs` at impl-registration time by the factory operator),
  `block.timestamp + duration` can overflow when cast to uint64,
  instantly making `gameOver()` true. Two-line fix with
  `SafeCast.toUint64(...)` if scope later expands to factory-operator
  misconfig.
- **Parent blacklisted post-init** — guardian flow.
- **Permissionless `closeGame` race vs guardian** — guardian flow.
- **Verifier address swap at impl registration** — factory-operator
  centralisation.

## Audit metadata

- **Source commit reference:** `ZKDisputeGame` is derived from
  `succinctlabs/op-succinct@c13844a9bbc330cca69eef2538d8f8ec123e1653`
  per the contract docstring at `L49`. M-02 may exist upstream;
  coordinated disclosure is worth considering before merging the fix
  publicly.
- **Solidity:** `0.8.15`, Foundry-built, CWIA via Solady's `Clone`.
- **Reviewer:** evm-security-audit pipeline (sc-first-pass →
  vulnerability-scanner → deep-reviewer → poc-builder).
- **Scope confirmed with audit caller:** whole `src/dispute/zk/`
  subtree + ZK interfaces; verifier trusted; adversaries are
  proposer/challenger/prover; H/C/M floor; PoCs required for
  confirmed H/C, voluntary for M (delivered for M-02 anyway).
- **Final counts:** 0 Critical · 0 High · 1 Medium. Lows,
  Informationals, and Gas observations were not enumerated by request.
