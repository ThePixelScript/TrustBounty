# TrustBounty Protocol

> [!WARNING]
> **HISTORICAL / SUPERSEDED DOCUMENTATION**
> This document contains historical narrative and preliminary protocol design notes. For the authoritative, frozen smart contract specification, function signatures, state machine transitions, error handling, events, and accounting logic for TrustBounty v0.1, refer strictly to **[`docs/CONTRACT_SPEC.md`](CONTRACT_SPEC.md)**.

## Scope

TrustBounty Protocol v0.1 defines the on-chain state machine, escrow mechanisms, and off-chain oracle interactions for trust-minimized software contribution settlement.

In v0.1, the protocol supports a single maintainer escrowing funds for a defined acceptance specification, evaluated against contributions from a single contributor, using primary and secondary off-chain verification oracles.

## Actors

1. **Maintainer**: The bounty sponsor who defines the acceptance specification, deposits bounty funds, specifies the `submissionDeadline`, and holds the right to challenge a `PASS` verification outcome. Maintainers can voluntarily cancel an unclaimed bounty prior to submission. Maintainers cannot select or replace V1 or V2 for an individual bounty; verifier identities are fixed at the contract deployment level.
2. **Contributor**: The software author who submits an exact software commit hash in satisfaction of the specification before the submission deadline (`timestamp < submissionDeadline`) and holds the right to challenge a `FAIL` verification outcome.
3. **Primary Verifier (V1)**: The protocol-configured off-chain verification oracle (`PRIMARY_VERIFIER`, configured at contract deployment level) authorized to claim submissions within `T_claim` (`timestamp < submissionTimestamp + T_claim`), execute containerized verification against the committed acceptance specification, and report structured results on-chain within `T_v1` (`timestamp < verificationDeadline`). If V1 reports `ERROR` or `INCONCLUSIVE`, or times out (`timestamp >= verificationDeadline`), the bounty automatically escalates to `DISPUTED` for automatic recovery by V2. V1 permanently loses authority once its timeout expires and cannot reclaim the bounty or submit late reports.
4. **Secondary Verifier (V2)**: The protocol-configured dispute resolution and fallback verification oracle (`SECONDARY_VERIFIER`, configured at contract deployment level) authorized to re-verify submissions and provide a binding final determination (`PASS` or `FAIL` only) for both challenge-originated disputes and automatic recovery cases (claim timeout, V1 timeout, or V1 `ERROR`/`INCONCLUSIVE`).
5. **Keepers / Anyone**: Unrestricted actors who can invoke permissionless progression or recovery mechanisms when deadlines expire (`timestamp >= deadline`)—including `expireBounty()` if no work is submitted before `submissionDeadline`—to prevent deadlock and advance the state machine.

> [!NOTE]
> **Verifier Immutability & Contract Non-Upgradeability**: `PRIMARY_VERIFIER` and `SECONDARY_VERIFIER` are set at contract deployment. Neither can be changed during the contract lifetime, maintainers cannot override either verifier on a per-bounty basis, and the v0.1 contract is strictly non-upgradeable. In v0.1, no verifier registry, staking, slashing, governance, proxy upgrade mechanisms, or multi-verifier quorums exist. While this remains a centralized oracle model, it prevents maintainers from selecting deliberately uncooperative, dead, or colluding verifiers for individual bounties.

## Bounty Lifecycle

```text
       ┌───────────────┐  cancelBounty() (maintainer, voluntary)
       │               ├─────────────────────────────────────────┐
       │    ACTIVE     │  expireBounty() (permissionless, ts>=D) │
       │               ├─────────────────────────────────────────┤
       └───────┬───────┘                                         │
               │ submitWork(commitHash)                          │
               │ (contributor, timestamp < submissionDeadline)   │
               ▼                                                 │
       ┌───────────────┐  expireClaim()                          │
       │   SUBMITTED   ├───────────────────────────────┐         │
       └───┬───────────┘  (timestamp >= T_claim)       │         │
           │                                           │         │
           │ claimVerification()                       │         │
           │ (timestamp < T_claim)                     │         │
           ▼                                           │         │
       ┌───────────────┐  timeoutV1() (ts >= T_v1)     │         │
       │   VERIFYING   ├─► or reportResult(ERR/INCONC) │         │
       └───┬───────────┘  (V1 loses authority)         │         │
           │                                           │         │
           │ reportResult(PASS/FAIL)                   │         │
           │ (timestamp < T_v1)                        │         │
           ▼                                           ▼         │
       ┌───────────────┐  challenge(bond)             ┌─────────┐│
       │   REPORTED    ├─────────────────────────────►│         ││
       └───┬───────────┘  (timestamp < T_challenge)   │         ││
           │                                          │         ││
           ├─► PASS: finalize() (ts >= T_chal) ──► SETTLED      ││
           ├─► FAIL: finalize() (ts >= T_chal) ──► REFUNDED ◄───┼┤
           │                                          │         ││
           ▼                                          │DISPUTED ││
                                                      │         ││
           ┌──────────────────────────────────────────┤         ││
           │                                          │         ││
           ├─► resolveDispute(PASS) (ts < T_v2) ──► SETTLED     ││
           ├─► resolveDispute(FAIL) (ts < T_v2) ──► REFUNDED ◄──┼┘
           ├─► timeoutV2() (ts >= T_v2):              │         │
           │   ├── V1 was PASS ───────────────────► SETTLED     │
           │   └── V1 was FAIL / Auto-Recovery ───► REFUNDED ◄──┘
```

## State Machine

The protocol defines exactly seven states. `SETTLED` and `REFUNDED` are strictly terminal. No `EXPIRED` state exists.

With the elimination of all retry cycles, the protocol state graph is strictly a Directed Acyclic Graph (DAG) with guaranteed acyclic progression to terminal states (`SETTLED` or `REFUNDED`). Every non-terminal state has a finite, permissionlessly executable progression or recovery mechanism. In particular, a funded `ACTIVE` bounty cannot remain indefinitely locked if the maintainer disappears, because anyone can permissionlessly trigger an expiry refund via `expireBounty()` once the submission deadline has elapsed (`timestamp >= submissionDeadline`).

All timeout and execution conditions adhere strictly to standardized inequality rules:
- An action is allowed if and only if `timestamp < deadline`.
- A timeout progression or finalization is allowed if and only if `timestamp >= deadline`.

| State | Description | Next Allowed States |
| :--- | :--- | :--- |
| `ACTIVE` | Escrow funded with specification commitment and `submissionDeadline`; awaiting work submission (`timestamp < submissionDeadline`), maintainer voluntary cancellation, or permissionless expiry refund (`timestamp >= submissionDeadline`). | `SUBMITTED` (`ACTIVE → SUBMITTED`), `REFUNDED` (`ACTIVE → REFUNDED`) |
| `SUBMITTED` | Contributor has locked commit hash; awaiting V1 claim or claim timeout progression. | `VERIFYING`, `DISPUTED` |
| `VERIFYING` | V1 has claimed submission; off-chain verification running. | `REPORTED`, `DISPUTED` |
| `REPORTED` | V1 has reported affirmative or negative verdict; awaiting challenge window expiration or challenge. | `DISPUTED`, `SETTLED`, `REFUNDED` |
| `DISPUTED` | Secondary verification under V2 (challenge-originated or automatic fallback from claim timeout, V1 timeout, or V1 `ERROR`/`INCONCLUSIVE`). | `SETTLED`, `REFUNDED` |
| `SETTLED` | **Terminal**: Bounty escrow disbursed to contributor. | *None* |
| `REFUNDED` | **Terminal**: Bounty escrow returned to maintainer. | *None* |

### Transition Rules

1. **`ACTIVE → SUBMITTED`**:
   - Triggered by `submitWork(commitHash)`.
   - Authorized caller: Contributor.
   - Precondition: Bounty is in `ACTIVE` state and `timestamp < submissionDeadline`.
   - Effects: The first accepted submission binds the bounty to that contributor address and commit hash for the current submission lifecycle. Sets `submissionTimestamp = timestamp` and `claimDeadline = submissionTimestamp + T_claim`. In v0.1, only one submission is permitted per bounty.

2. **`ACTIVE → REFUNDED` (Voluntary Bounty Cancellation)**:
   - Triggered by `cancelBounty()`.
   - Authorized caller: Maintainer.
   - Precondition: Bounty is in `ACTIVE` state before any submission has been made (voluntary cancellation).
   - Effects: Returns the deposited bounty escrow to the maintainer.

3. **`ACTIVE → REFUNDED` (Submission Deadline Expiry)**:
   - Triggered by `expireBounty()`.
   - Authorized caller: Permissionless (anyone).
   - Precondition: Bounty is in `ACTIVE` state, no submission exists, and `timestamp >= submissionDeadline`.
   - Effects: Returns the deposited bounty escrow to the maintainer. Guarantees that a funded `ACTIVE` bounty cannot remain indefinitely locked if the maintainer disappears.

4. **`SUBMITTED → VERIFYING`**:
   - Triggered by `claimVerification()`.
   - Authorized caller: Primary Verifier (V1).
   - Precondition: `timestamp < submissionTimestamp + T_claim`.
   - Effects: Primary verifier takes custody of verification; sets `claimTimestamp = timestamp` and `verificationDeadline = claimTimestamp + T_v1`.

5. **`SUBMITTED → DISPUTED` (Claim Expiry Fallback)**:
   - Triggered by `expireClaim()`.
   - Authorized caller: Permissionless (anyone).
   - Precondition: `timestamp >= submissionTimestamp + T_claim`.
   - Effects: Prevents verifier deadlock when V1 goes offline or fails to claim. Automatically advances to `DISPUTED` for fallback verification by secondary verifier V2 without returning to `ACTIVE` or requiring a challenge bond. V1 loses authority. Sets `disputeTimestamp = timestamp` and `disputeDeadline = disputeTimestamp + T_v2`.

6. **`VERIFYING → REPORTED`**:
   - Triggered by `reportResult(result, evidenceHash)`.
   - Authorized caller: Primary Verifier (V1).
   - Result values: Strictly `PASS` or `FAIL`.
   - Precondition: `timestamp < verificationDeadline`.
   - Effects: Sets `reportedTimestamp = timestamp` and `challengeDeadline = reportedTimestamp + T_challenge`.

7. **`VERIFYING → DISPUTED` (V1 Timeout or Infrastructure Failure)**:
   - Triggered by:
     - `reportResult(result, evidenceHash)`:
       - Authorized caller: Primary Verifier (V1).
       - Precondition: `timestamp < verificationDeadline`, with `result` equal to `ERROR` or `INCONCLUSIVE`.
       - Effects: The contract records the result (`ERROR` or `INCONCLUSIVE`), the provided `evidenceHash`, and the report timestamp (`reportedTimestamp = timestamp`), ensuring the primary evidence commitment is preserved on-chain and not discarded. State transitions directly to `DISPUTED` without requiring a challenge bond. Secondary verifier V2 handles fallback verification. V1 permanently loses authority and cannot reclaim the bounty or submit late reports. Sets `disputeTimestamp = timestamp` and `disputeDeadline = disputeTimestamp + T_v2`.
     - `timeoutV1()`:
       - Authorized caller: Permissionless (anyone).
       - Precondition: `timestamp >= verificationDeadline`.
       - Effects: Transitions directly to `DISPUTED` for secondary verification by V2 without requiring or fabricating a result or an `evidenceHash`. No challenge bond is required. V1 permanently loses authority (revoked) and cannot reclaim the bounty or submit late reports. Sets `disputeTimestamp = timestamp` and `disputeDeadline = disputeTimestamp + T_v2`.

8. **`REPORTED → DISPUTED` (Challenge-Originated Dispute)**:
   - Triggered by `challenge(bond)`.
   - Authorized callers (Challenge Symmetry):
     - If V1 result is `PASS`: Maintainer only.
     - If V1 result is `FAIL`: Contributor only.
   - Precondition: `timestamp < reportedTimestamp + T_challenge`; caller attaches exactly the protocol-configured `challengeBond` ($B_{chal} \le \min(\text{reward}, \text{MAX\_BOND\_CAP})$). Maintainers cannot configure an arbitrary bond per bounty.
   - Effects: State transitions to `DISPUTED` for secondary verification by V2. Exactly one challenge round permitted per bounty. Sets `disputeTimestamp = timestamp` and `disputeDeadline = disputeTimestamp + T_v2`.

9. **`REPORTED → SETTLED` (Unchallenged PASS)**:
   - Triggered by `finalize()`.
   - Authorized caller: Permissionless.
   - Precondition: V1 result is `PASS` and `timestamp >= reportedTimestamp + T_challenge`.
   - Effects: Disburses bounty escrow to contributor.

10. **`REPORTED → REFUNDED` (Unchallenged FAIL)**:
    - Triggered by `finalize()`.
    - Authorized caller: Permissionless.
    - Precondition: V1 result is `FAIL` and `timestamp >= reportedTimestamp + T_challenge`.
    - Effects: Returns bounty escrow to maintainer.

11. **`DISPUTED → SETTLED` (V2 PASS Verdict or V2 Timeout on V1 PASS)**:
    - Triggered by `resolveDispute(PASS)`:
      - Authorized caller: Secondary Verifier (V2).
      - Precondition: `timestamp < disputeDeadline`; verdict must be strictly `PASS`.
      - Effects: Disburses bounty escrow to contributor.
        - For challenge-originated disputes:
          - If V1 reported `FAIL` (challenge upheld; V2 overturns V1): Challenger receives 100% of the challenge bond back.
          - If V1 reported `PASS` (challenge rejected; V2 confirms V1): Challenger (maintainer) loses the challenge bond; the bond is transferred to the contributor (the party whose V1 PASS result was confirmed).
        - For automatic recovery disputes (claim timeout, V1 timeout, or V1 `ERROR`/`INCONCLUSIVE`): No challenge bond was deposited; full bounty escrow is disbursed to contributor.
    - Triggered by `timeoutV2()`:
      - Authorized caller: Permissionless.
      - Precondition: `timestamp >= disputeDeadline` and V1 reported `PASS` (challenge-originated).
      - Effects: Preserves documented V1-result fallback to `SETTLED`. Bounty escrow disbursed to contributor. Challenger receives 100% challenge bond back. Documented residual oracle/liveness limitation.

12. **`DISPUTED → REFUNDED` (V2 FAIL Verdict or V2 Timeout Fallback)**:
    - Triggered by `resolveDispute(FAIL)`:
      - Authorized caller: Secondary Verifier (V2).
      - Precondition: `timestamp < disputeDeadline`; verdict must be strictly `FAIL`.
      - Effects: Returns bounty escrow to maintainer.
        - For challenge-originated disputes:
          - If V1 reported `PASS` (challenge upheld; V2 overturns V1): Challenger receives 100% of the challenge bond back.
          - If V1 reported `FAIL` (challenge rejected; V2 confirms V1): Challenger (contributor) loses the challenge bond; the bond is transferred to the maintainer (the party whose V1 FAIL result was confirmed).
        - For automatic recovery disputes (claim timeout, V1 timeout, or V1 `ERROR`/`INCONCLUSIVE`): No challenge bond was deposited; full bounty escrow is returned to maintainer.
    - Triggered by `timeoutV2()`:
      - Authorized caller: Permissionless.
      - Precondition: `timestamp >= disputeDeadline` and:
        - If challenge-originated where V1 reported `FAIL`: Preserves documented fallback to `REFUNDED`; challenger receives 100% challenge bond back.
        - If automatic recovery dispute (V1 `ERROR`/`INCONCLUSIVE`, V1 timeout, or V1 claim timeout): Preserves documented fallback to `REFUNDED` as unresolved-verification recovery. This does not assert contributor fault; it is a bounded MVP recovery rule; total oracle outage can prevent contributor payment. Documented residual oracle/liveness limitation.

## Acceptance Specification

Acceptance criteria are formalized in a v1.1 machine-readable specification schema:
- **Version**: `"1.1"`
- **Repository Reference**: `owner` and `name` strings.
- **Base Commit**: Target Git commit SHA.
- **Execution Environment**: Immutable container reference pinned by SHA-256 digest (`image: "<reference>@sha256:<64-hex-digest>"`).
- **Criteria**: Array of requirements (`BUILD`, `TEST`, `COVERAGE`).

The specification is canonicalized using RFC 8785 (JCS) and committed on-chain as a 32-byte hexadecimal hash:
```text
specHash = Keccak-256(RFC8785(specification))
```
The specification commitment is immutable once the bounty is active. Modifying criteria requires creating a new bounty.

## Submission

In v0.1:
- The protocol binds exactly **one bounty to one contributor**.
- A contributor submits work via `submitWork(commitHash)`.
- Upon submission:
  - The first accepted submission binds the bounty to that contributor address for the current submission lifecycle.
  - The exact Git commit hash is locked to the bounty for the current submission lifecycle.
  - Subsequent submissions from the same or other contributors are rejected.
- No contributor submission bond is required in v0.1.
- **Front-Running Limitation**: In public mempools, submission transactions can be observed. A malicious observer could duplicate a commit hash in a racing transaction. Using private RPC routing mitigates exposure; a cryptographic commit-reveal mechanism is deferred to v0.2.

## Verification

Verification is performed off-chain by designated verification oracles:
1. **Primary Verifier (V1)** claims a submission while `timestamp < submissionTimestamp + T_claim`.
2. V1 pulls the designated repository, checks out the submitted commit, initializes the pinned container environment (`image`), and executes the criteria commands.
3. V1 submits an on-chain report while `timestamp < verificationDeadline`:
   - If `result` is `PASS` or `FAIL`, the bounty transitions to `REPORTED` alongside the `evidenceHash`.
   - If `result` is `ERROR` or `INCONCLUSIVE`, the contract records the result, the `evidenceHash`, and the report timestamp, ensuring the primary evidence commitment is preserved on-chain and not discarded. The bounty transitions directly to `DISPUTED` without requiring a challenge bond, where secondary verifier V2 performs fallback verification.
4. If V1 fails to respond within `T_v1` (`timestamp >= verificationDeadline`), a permissionless `timeoutV1()` call transitions the bounty directly to `DISPUTED`. No result or `evidenceHash` is required or fabricated. V1 authority is permanently revoked.
5. Upon timing out or transitioning to `DISPUTED`, V1 permanently loses authority; it cannot reclaim the bounty or submit late reports. All retry cycles and attempt counters (`attempts`, `MAX_ATTEMPTS`) are removed from the protocol.

### Verification Semantics

Protocol v0.1 enforces strictly bounded, acyclic execution without retry loops:
- **No Retry Cycles**: V1 executes at most once. There are no retry cycles back to `SUBMITTED`, and `MAX_ATTEMPTS` is eliminated from the state-transition logic.
- **Direct Escalation on Failure**: If V1 encounters non-deterministic, infrastructure, or environment failures (`ERROR` or `INCONCLUSIVE`), the contract records the result, `evidenceHash`, and report timestamp, preserving the primary evidence commitment on-chain, and transitions directly to `DISPUTED`. If V1 times out (`timestamp >= verificationDeadline`), a permissionless call transitions directly to `DISPUTED` without requiring or fabricating a result or evidenceHash. Secondary verifier V2 conducts the secondary verification.
- **Claim Timeout Escalation**: If V1 fails to claim within `T_claim` (`timestamp >= submissionTimestamp + T_claim`), `expireClaim()` transitions directly to `DISPUTED` for fallback verification by V2, preventing deadlock.
- **V1 Authority Expiration**: V1 loses all authority after its timeout deadline (`timestamp >= verificationDeadline`) or upon transition to `DISPUTED`. It cannot reclaim the bounty or perform later reports.
- **Strict Binary V2 Verdicts**: V2 acts as the dispute and fallback verification oracle and returns strictly `PASS` or `FAIL`.

## Evidence

The `evidenceHash` is an on-chain cryptographic commitment to off-chain logs, output streams, and metric summaries generated during verification.

The `evidenceHash` is a tamper-evident commitment mechanism. It provides an integrity trail for off-chain transcripts, but it does NOT prove execution honesty or code quality.

## Settlement

Settlement is strictly binary and terminal:
- **`SETTLED`**: Full bounty escrow is transferred to the contributor.
- **`REFUNDED`**: Full bounty escrow is returned to the maintainer.
- No partial distributions, fractional streaming, or governance overrides exist in v0.1.

## Dispute Handling

Disputes follow a bounded, deterministic resolution mechanism:
1. **Dispute Origins**:
   The protocol distinguishes exactly two origins of `DISPUTED`:
   - **A. Challenge-Originated**:
     - `V1 PASS` + maintainer challenge
     - `V1 FAIL` + contributor challenge
     Submitted strictly within the challenge window (`timestamp < reportedTimestamp + T_challenge`) accompanied by the protocol-configured `challengeBond` ($B_{chal}$).
   - **B. Automatic Recovery**:
     - `V1 ERROR`
     - `V1 INCONCLUSIVE`
     - V1 verification timeout (`timestamp >= verificationDeadline`)
     - V1 claim timeout (`timestamp >= submissionTimestamp + T_claim`)
     Automatic recovery transitions directly to `DISPUTED` where secondary verifier V2 takes over. Automatic recovery requires no challenge bond.
2. **Challenge Symmetry**:
   - Maintainer may challenge an affirmative report (`V1 = PASS`).
   - Contributor may challenge a negative report (`V1 = FAIL`).
3. **Single-Round Limit**: At most one challenge round is permitted per bounty.
4. **Secondary Verifier (V2)**:
   - Dispatches verification to the protocol-configured secondary verifier (`SECONDARY_VERIFIER`).
   - V2 returns strictly `PASS` or `FAIL` while `timestamp < disputeDeadline`. V2 determination is final for that dispute:
     - `V2 PASS → SETTLED`
     - `V2 FAIL → REFUNDED`
5. **V2 Timeout Semantics**:
   If V2 fails to provide a verdict before its deadline (`timestamp >= disputeDeadline`), the dispute executes deterministic fallback resolution:
   - **For Challenge-Originated DISPUTED**:
     - `V1 PASS + V2 timeout → SETTLED` (bounty escrow disbursed to contributor; challenger receives 100% of challenge bond back).
     - `V1 FAIL + V2 timeout → REFUNDED` (bounty escrow returned to maintainer; challenger receives 100% of challenge bond back).
   - **For Automatic DISPUTED**:
     - `V1 ERROR/INCONCLUSIVE + V2 timeout → REFUNDED`
     - `V1 timeout + V2 timeout → REFUNDED`
     - `V1 claim timeout + V2 timeout → REFUNDED`
     This outcome is designated as **unresolved-verification recovery** (rather than neutral settlement):
     - This does not assert contributor fault.
     - It is a bounded MVP recovery rule to prevent indefinite escrow lockup.
     - Total oracle outage can prevent contributor payment.
   - **Prohibited Settlements**: Split settlement (e.g., 50/50) is strictly prohibited.
   - This fallback is explicitly documented as a residual oracle and liveness limitation.
6. **Out of Scope**: Verifier slashing, token staking, DAO voting, multi-verifier quorums, and commit-reveal are omitted from v0.1.

### Challenge Bond Accounting

The protocol enforces deterministic accounting rules for the challenge bond in v0.1:
- **Protocol-Level Parameter**: The challenge bond ($B_{chal}$) is configured at the protocol/deployment level. Maintainers cannot choose an arbitrary bond per bounty.
- **Hard Upper Bound**: The protocol enforces the invariant $B_{chal} \le \min(\text{reward}, \text{MAX\_BOND\_CAP})$. No optimal bond ratio is claimed.
- **Challenge Upheld (V2 Overturns V1)**: Challenger receives 100% of the challenge bond back.
- **Challenge Rejected (V2 Confirms V1)**: Challenger loses the bond; the smart contract transfers the bond to the party whose V1 result was confirmed:
  - If maintainer challenged `PASS` and V2 confirmed `PASS`, the bond is transferred to the contributor.
  - If contributor challenged `FAIL` and V2 confirmed `FAIL`, the bond is transferred to the maintainer.
- **V2 Timeout**: Challenger receives 100% of the challenge bond back.
- **Automatic Recovery**: Automatic `DISPUTED` cases (claim timeout, V1 timeout, or V1 `ERROR`/`INCONCLUSIVE`) require no challenge bond.
- **Escrow Segregation**: The challenge bond is accounted for strictly separately from the bounty reward and must never be used as bounty escrow.

## Security Invariants

The protocol enforces fourteen core invariants:

1. **Protocol-Level Verifier Immutability & Non-Upgradeability**: `PRIMARY_VERIFIER` and `SECONDARY_VERIFIER` are fixed at contract deployment and immutable for the contract lifetime; neither can be changed, maintainers cannot select or override verifiers for an individual bounty, and the v0.1 contract is strictly non-upgradeable.
2. **ACTIVE Liveness**: A funded `ACTIVE` bounty requires an explicit `submissionDeadline`. A contributor can submit work while `timestamp < submissionDeadline`. If no submission exists, the maintainer can voluntarily cancel (`cancelBounty()`), or anyone can permissionlessly call `expireBounty()` when `timestamp >= submissionDeadline` to refund the maintainer. A funded `ACTIVE` bounty cannot remain indefinitely locked if the maintainer disappears.
3. **No Claim Deadlock**: A submission not claimed within `T_claim` (`timestamp >= submissionTimestamp + T_claim`) permissionlessly advances to `DISPUTED` for fallback verification by V2.
4. **Strict DAG State Progression**: Elimination of all retry cycles guarantees monotonic acyclic forward progression to terminal states (`SETTLED` or `REFUNDED`).
5. **Bounded V1 Window & Authority Expiry**: Primary verification is bounded by `T_v1`; V1 permanently loses authority once `timestamp >= verificationDeadline` and cannot reclaim or submit late reports.
6. **Direct Dispute on Verification Failure**: V1 `ERROR` or `INCONCLUSIVE` records the result, `evidenceHash`, and report timestamp on-chain, preserving the primary evidence commitment, and transitions directly to `DISPUTED` without a challenge bond. V1 timeout transitions directly to `DISPUTED` without requiring or fabricating a result or `evidenceHash`. Both trigger secondary resolution by V2 without retry loops or attempt counters.
7. **Bounded V2 Dispute & Unresolved-Verification Recovery**: Secondary verifier evaluation is bounded by `T_v2`. Challenge-originated timeouts fall back to V1's verdict; automatic recovery timeouts execute unresolved-verification recovery to `REFUNDED` without asserting contributor fault.
8. **Terminal Finality**: `SETTLED` and `REFUNDED` states are strictly terminal with no outbound transitions.
9. **No Double Payout / Refund**: Escrow funds can be disbursed at most once.
10. **Specification Immutability**: Committed `specHash` cannot be altered after bounty activation.
11. **Submission Immutability**: The first accepted submission binds the bounty to that contributor address for the current submission lifecycle.
12. **Challenge Symmetry & Bounded Bond**: Maintainer can challenge `PASS`; contributor can challenge `FAIL`. The challenge bond is bounded by $B_{chal} \le \min(\text{reward}, \text{MAX\_BOND\_CAP})$ at the protocol level. Rejected challenges transfer the bond to the confirmed counterparty.
13. **One Challenge Maximum**: Exactly one challenge round is permitted per bounty.
14. **Escrow Conservation & Universal Liveness**: Contract balance strictly accounts for bounty funds and active challenge bonds; challenge bonds are never commingled with bounty escrow and no funds can be trapped. Every non-terminal state has a finite, permissionlessly executable progression or recovery mechanism.

## Open Questions

1. **Anti-Front-Running**: Design and evaluation of a two-phase commit-reveal submission scheme for v0.2.
2. **Multi-Contributor Support**: Mechanisms for concurrent submission handling, queue ordering, or parallel evaluation.
3. **Decentralized Verification**: Moving from designated oracles (V1/V2) to staked, multi-verifier quorums or cryptographic zero-knowledge/TEE proofs.
4. **Economic Parameter Optimization**: Empirical calibration of `challengeBond`, `T_claim`, `T_v1`, `T_challenge`, and `T_v2`.
