# ZKDisputeGame — Audit PoCs

Findings and Forge proof-of-concept tests from a security review of
`src/dispute/zk/ZKDisputeGame.sol`. Two Medium-severity issues were confirmed
with passing PoCs.

## How to run

```sh
cd packages/contracts-bedrock
DEV_FEATURE__ZK_DISPUTE_GAME=true forge test --match-path 'test/dispute/zk/poc/*'
```

Expect 3 tests, all passing.

## Findings

| ID | Severity | Title | PoC |
|---|---|---|---|
| [M-01](#m-01--permissionless-prover-race-denies-the-proposers-challengerbond-bonus) | Medium | Permissionless prover race denies the proposer's `challengerBond` bonus | `ZKDeepReview_DR01.t.sol::test_dr01_challengerAsProver_griefsProposer` |
| [M-02](#m-02--early-prover-front-runs-challenge-window-bonds-burned-to-address0-when-parent-resolves-challenger_wins) | Medium | Early prover front-runs challenge window; bonds burned to `address(0)` when parent resolves CHALLENGER_WINS | `ZKDeepReview_DR02.t.sol::test_dr02_earlyProveLocksOutChallenger`, `::test_dr02_fullAttackBondsBurnedToZeroAddress` |

Both findings exploit the same architectural seam: `prove()` is permissionless,
`gameOver()` flips on first prove, and prover identity controls bond credit
allocation. A single coordinated fix closes both — see [Recommended
mitigation](#recommended-mitigation-applies-to-both-findings).

## Scope

- **In scope:** `src/dispute/zk/ZKDisputeGame.sol` and the ZK interfaces under
  `interfaces/dispute/zk/`.
- **Trusted (out of scope):** `IZKVerifier` internals, `AnchorStateRegistry`,
  `DelayedWETH`, `DisputeGameFactory`, guardian / pause / admin centralisation,
  factory-operator `gameArgs` configuration risks.
- **Adversarial actors:** proposer / game creator, challenger, prover.

---

## [M-01] — Permissionless prover race denies the proposer's `challengerBond` bonus

- **Severity:** Medium
- **Location:** `src/dispute/zk/ZKDisputeGame.sol:406-435, 497-511`
- **Class:** Economic griefing / MEV / state-machine misuse

### How it occurs

In the `ChallengedAndValidProofProvided` branch of `resolve()`, the bond split
depends on prover identity:

```solidity
// ZKDisputeGame.sol:497-511
} else if (claimData.status == ProposalStatus.ChallengedAndValidProofProvided) {
    status = GameStatus.DEFENDER_WINS;

    if (claimData.prover == gameCreator()) {
        normalModeCredit[claimData.prover] = totalBonds;          // proposer takes everything
    }
    else {
        normalModeCredit[claimData.prover] = challengerBond();    // prover gets challengerBond
        normalModeCredit[gameCreator()] = totalBonds - challengerBond(); // proposer gets only initBond
    }
}
```

`prove()` is permissionless and the verifier-bound `publicValues` (line 417)
include `msg.sender`, so any party with witness data — including the
challenger themselves — can bind a valid proof to their own address.

### Attack path (challenger-as-prover variant — the cleanest demonstration)

1. Challenger calls `challenge()`, paying `challengerBond`.
2. Challenger immediately calls `prove(_proofBytes)` themselves. `claimData.prover = challenger`.
3. After deadline, anyone calls `resolve()`. Branch is
   `ChallengedAndValidProofProvided`, prover ≠ proposer, so:
   - `normalModeCredit[challenger] = challengerBond` ← challenger gets their full bond back
   - `normalModeCredit[proposer]   = initBond`        ← proposer is denied the `challengerBond` bonus

### Impact

- The proposer is denied `challengerBond` of expected reward for defending
  their valid claim. The reward becomes a public mempool race rather than a
  guaranteed payout for the honest defender.
- The challenger pays only gas + proof-generation cost; their bond is fully
  refunded regardless of outcome. The "skin in the game" property of
  `challengerBond` is removed — challenges become a near-free option.
- Repeatable per game; permissionless trigger; no cap on `challengerBond`,
  so loss can be material on production deployments.

### Mitigation

Three options, in order of intrusiveness:

1. **Always credit the bonus to `gameCreator`** in the
   `ChallengedAndValidProofProvided` branch, regardless of who submitted
   the proof. If a separate prover did the work, compensate them with a
   fixed reward funded outside the bond pool (or simply remove the
   third-party-prover incentive).

   ```diff
    } else if (claimData.status == ProposalStatus.ChallengedAndValidProofProvided) {
        status = GameStatus.DEFENDER_WINS;
   -    if (claimData.prover == gameCreator()) {
   -        normalModeCredit[claimData.prover] = totalBonds;
   -    } else {
   -        normalModeCredit[claimData.prover] = challengerBond();
   -        normalModeCredit[gameCreator()] = totalBonds - challengerBond();
   -    }
   +    // Defender wins — proposer always takes the full pot, regardless of prover.
   +    normalModeCredit[gameCreator()] = totalBonds;
    }
   ```

2. **Proposer-only prove window**, then permissionless. Reserve the first
   N seconds (e.g., a fraction of `maxProveDuration`) for `gameCreator` to
   prove unopposed. After the window, `prove()` opens to anyone. This
   preserves the safety net of a third-party prover while protecting the
   honest proposer's bonus.

3. **Slashable challenger bond.** If the challenger themselves submits the
   proof (or otherwise acts dishonestly), forfeit a portion of
   `challengerBond` to the proposer to restore skin-in-the-game.

Option 1 is the smallest diff and addresses the core economic harm.
Cannot patch deployed CWIA games — fix lives in a new impl plus a
`DisputeGameFactory.setImplementation` call.

---

## [M-02] — Early prover front-runs challenge window; bonds burned to `address(0)` when parent resolves CHALLENGER_WINS

- **Severity:** Medium
- **Location:** `src/dispute/zk/ZKDisputeGame.sol:377, 406-435, 471-477, 644`
- **Class:** State-machine griefing / loss-of-funds (recoverable only via guardian)

### How it occurs

Three pieces of contract logic compose into a real loss vector:

1. **`initialize()` permits parents in `IN_PROGRESS` state.** Line 329 only
   rejects `parent.status() == GameStatus.CHALLENGER_WINS`; an `IN_PROGRESS`
   parent passes the check.

   ```solidity
   // ZKDisputeGame.sol:329
   if (parent.status() == GameStatus.CHALLENGER_WINS) revert InvalidParentGame();
   ```

2. **`prove()` permits parents in `IN_PROGRESS` state.** Line 411 only blocks
   `getParentGameStatus() == CHALLENGER_WINS`. The verifier itself only
   attests to the local L2 transition (`startingProposal.root → rootClaim`
   for `l2SequenceNumber`); it does **not** attest to parent-game validity.

   ```solidity
   // ZKDisputeGame.sol:411
   if (getParentGameStatus() == GameStatus.CHALLENGER_WINS) revert InvalidParentGame();
   ```

3. **`gameOver()` flips to true once a prover lands.** Line 644 returns true
   when `claimData.prover != address(0)`. After a successful `prove()`, any
   later `challenge()` reverts at line 377 (`if (gameOver()) revert GameOver();`).

   ```solidity
   // ZKDisputeGame.sol:644
   gameOver_ = claimData.deadline.raw() < uint64(block.timestamp) || claimData.prover != address(0);
   ```

### Attack path

1. Adversary creates child `C` with `parentIndex` pointing at a parent `P`
   that is currently `IN_PROGRESS`.
2. Adversary calls `prove(_proof)` immediately. Verifier accepts the
   locally-valid L2 transition. `claimData.prover = adversary`,
   `claimData.status = UnchallengedAndValidProofProvided`.
3. **`gameOver()` is now true** — the challenge window is permanently
   closed. No challenger can ever reach `claimData.challenger`.
4. `P` later resolves `CHALLENGER_WINS` (the parent was bad).
5. Anyone calls `resolve()` on `C`. The parent-CHALLENGER_WINS branch
   executes:

   ```solidity
   // ZKDisputeGame.sol:471-477
   if (parentGameStatus == GameStatus.CHALLENGER_WINS) {
       status = GameStatus.CHALLENGER_WINS;
       normalModeCredit[claimData.challenger] = totalBonds;
   }
   ```

   But `claimData.challenger == address(0)` — no challenger ever managed
   to land. **All of `C`'s `totalBonds` is credited to `address(0)`** and
   recoverable only via the DelayedWETH guardian's `hold()/recover()` flow.

### Impact

- Bonds intended to compensate an honest challenger for catching a bad
  child game are burned to `address(0)`. Recovery requires guardian
  intervention via `DelayedWETH.hold()/recover()` — operationally costly.
- A challenger who would have been entitled to `totalBonds` is denied that
  compensation entirely.
- Adversary cost: gas + one proof generation. Adversary has no direct
  monetary gain (the bonds go to `address(0)`, not to them) — the harm
  is denial-of-compensation that breaks the protocol's challenger-incentive
  model in any active dispute network.

### Why this is distinct from M-01

M-01 covers the honest race for the prover bonus on a *valid* claim. M-02
covers the case where the local claim is technically provable but the
parent chain is invalid — the prover weaponises the design seam where
parent validity is decoupled from the per-game proof.

### Mitigation

The cleanest fix is to require parent finality before allowing `prove()`:

```diff
 function prove(bytes calldata _proofBytes) external returns (ProposalStatus) {
     if (status != GameStatus.IN_PROGRESS) revert ClaimAlreadyResolved();

-    if (getParentGameStatus() == GameStatus.CHALLENGER_WINS) revert InvalidParentGame();
+    GameStatus parentStatus = getParentGameStatus();
+    if (parentStatus == GameStatus.CHALLENGER_WINS) revert InvalidParentGame();
+    // Block prove() until the parent is finalised. An in-flight parent could
+    // still resolve CHALLENGER_WINS and route bonds to address(0).
+    if (parentStatus == GameStatus.IN_PROGRESS) revert ParentGameNotResolved();

     if (gameOver()) revert GameOver();
     ...
 }
```

Alternatives:

- **Or** require parent `DEFENDER_WINS` in `initialize()` itself, so a
  child can never be created over an in-flight parent (more aggressive;
  may break legitimate proposer pipelining).
- **Or** in the parent-CHALLENGER_WINS branch of `resolve()`, route bonds
  to a guaranteed-recoverable address (DAO treasury or slashing fund)
  instead of `address(0)`. This stops the loss-of-funds but doesn't
  restore the challenger-incentive model.

The `prove()` guard is the minimal change and fully resolves the loss vector.
Cannot patch deployed CWIA games — fix lives in a new impl deployment.

---

## Recommended mitigation (applies to both findings)

A single new `ZKDisputeGame` impl that combines the two diffs above closes
both M-01 and M-02. Re-register via `DisputeGameFactory.setImplementation`
(or, in production, via OPCM's `upgrade()` flow with the new impl + updated
`gameArgs`). Existing in-flight games are not affected — the change applies
only to games created after the new impl is registered.

## Out-of-scope but worth knowing

These exist in the contract but were excluded from this audit's threat
model. Re-evaluate if the threat model changes:

- **uint64 deadline truncation** at lines 350 and 392.
  `block.timestamp + maxXxxDuration().raw()` is computed in `uint256` then
  explicit-cast `uint64(...)`. With a malicious or accidentally-large
  `maxChallengeDuration` / `maxProveDuration` set at impl-registration time,
  the deadline truncates to a past timestamp and `gameOver()` is instantly
  true. Other CWIA fields have explicit guards (`l2ChainId == 0` at line 299,
  `l2SequenceNumber > type(uint64).max` at line 340). Two-line fix:
  `SafeCast.toUint64(...)` or `require(maxXxxDuration() <= type(uint32).max)`.
- **Parent blacklisted post-init.** `initialize()` checks parent blacklist at
  create-time (lines 310–312) but `resolve()` does not re-check. Mitigation
  lives in guardian flow per the contract docstring at lines 463–466.
- **Permissionless `closeGame` race vs guardian.** Anyone can lock the bond
  distribution mode before a guardian blacklist tx lands.
- **Verifier address swap.** Factory-operator can change `gameArgs.verifier`
  at `setImplementation`-time. Each registered impl is pinned, but the
  registration itself is a privileged action.

## What was checked but is *not* a finding

The deep-review pass invalidated several first-pass concerns. Highlights:

- **`closeGame()` EIP-150 OOG griefing on `try setAnchorState`** — the
  `nosemgrep` annotation at line 619 is correctly applied. `isGameProper`
  (`AnchorStateRegistry.sol:275-297`) checks only registration / blacklist /
  retirement / pause and does **not** depend on `setAnchorState` having
  succeeded. A swallowed OOG is harmless.
- **`publicValues` ABI vs packed encoding** — encoding is `abi.encode`
  end-to-end (192 bytes); the SP1 program decodes the same way.
- **Proof-replay across sibling-parented games** — even when same prover
  satisfies `verify` for two sibling games sharing publicValues, each game
  has its own bond pool, no invariant is violated, no fund flow is
  unauthorised. At worst it's a "compute-once-prove-twice" optimisation for
  honest provers.
- **`DelayedWETH.withdraw(_guy, _wad)` double-spend** — `DelayedWETH.sol:96-104`
  confirms ETH lands at `msg.sender` (the game), then the game forwards via
  `_recipient.call{value}`. Single payment.

## Audit metadata

- **Source commit:** ZKDisputeGame derived from
  `succinctlabs/op-succinct@c13844a9bbc330cca69eef2538d8f8ec123e1653`
  per the contract docstring at line 49.
- **Solidity:** 0.8.15.
- **Reviewer:** `evm-security-audit` pipeline (sc-first-pass → vulnerability-scanner → deep-reviewer).
- **Findings counts:** 0 Critical, 0 High, 2 Medium. Lows, Informationals,
  and Gas observations were intentionally not enumerated — the floor was
  set to H/C/M.
