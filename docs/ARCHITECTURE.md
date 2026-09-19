# TrustBounty System Architecture (v0.1)

## 1. System Overview

TrustBounty is a blockchain-based protocol for trust-minimized settlement of open-source software contribution bounties. It coordinates maintainer acceptance requirements with containerized off-chain verification oracles and non-blocking on-chain escrow.

Maintainers define acceptance requirements in a machine-readable specification committed to the blockchain before development begins. Contributors submit specific software revisions, off-chain containerized verification engines evaluate the revision against the committed criteria, and on-chain escrow deterministically settles the bounty based on reported verification outcomes and bounded challenge mechanisms.

---

## 2. Core Components & System Roles

TrustBounty v0.1 consists of four primary components:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                      ACCEPTANCE SPECIFICATION ENGINE                     │
│  Schema v1.1  ──►  RFC 8785 (JCS) Canonicalization  ──►  Keccak-256 Hash │
│                             (specHash)                                  │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     ON-CHAIN ESCROW & STATE MACHINE                     │
│                           (TrustBounty.sol)                             │
│  - Native ETH Escrow & Liability Accounting (Reward, Bond, Withdrawable)│
│  - 7-State Directed Acyclic Graph (DAG) State Transitions               │
│  - Deployment-Immutable Verifiers (PRIMARY_VERIFIER, SECONDARY_VERIFIER)│
│  - Non-Blocking Pull-Payment Subsystem (withdraw, withdrawTo)           │
└───────────────────▲─────────────────────────────────▲───────────────────┘
                    │                                 │
           claim / reportVerification              reportV2
                    │                                 │
┌───────────────────┴────────────────┐   ┌────────────┴───────────────────┐
│     PRIMARY VERIFIER (V1)          │   │     SECONDARY VERIFIER (V2)    │
│  - Clones repo & checks out commit │   │  - Re-executes containerized   │
│  - Runs container criteria         │   │    criteria on dispute         │
│  - Generates evidenceHash (logs)   │   │  - Returns strictly PASS/FAIL  │
│  - Reports PASS, FAIL, or ERROR    │   │  - Resolves challenges/timeouts│
└────────────────────────────────────┘   └────────────────────────────────┘
```

### 2.1 Acceptance Specification Module (`specification/`)
* **Role**: Formulates, validates, and serializes machine-readable criteria under schema v1.1.
* **Environment Pinning**: Binds the execution environment to an immutable container image digest (`image@sha256:...`).
* **Deterministic Hashing**: Applies RFC 8785 JSON Canonicalization Scheme (JCS) and computes the 32-byte commitment `specHash = Keccak-256(RFC8785(specification))` prior to bounty creation.

### 2.2 Escrow Smart Contract (`contracts/src/TrustBounty.sol`)
* **Role**: Non-upgradeable, monolithic smart contract holding escrowed funds and enforcing protocol invariants.
* **State Machine**: Enforces monotonic forward progression across the 7-state DAG (`ACTIVE`, `SUBMITTED`, `VERIFYING`, `REPORTED`, `DISPUTED`, `SETTLED`, `REFUNDED`).
* **Accounting**: Maintains explicit liability segregation (`totalRewardLiability`, `totalBondLiability`, `totalWithdrawableLiability`) preventing insolvency or griefing.
* **Verifier Binding**: Immutably pins `PRIMARY_VERIFIER` and `SECONDARY_VERIFIER` addresses at deployment. Maintainers cannot select or override verifiers per bounty.
* **Pull-Payment Subsystem**: Credits recipient balances during terminalization without external calls, exposing `withdraw()` and `withdrawTo(destination)` for secure fund retrieval.

### 2.3 Primary Verification Oracle (V1)
* **Role**: Designated off-chain execution daemon (`PRIMARY_VERIFIER`) monitoring on-chain `SUBMITTED` events.
* **Execution**: Claims tasks within `T_claim`, pulls the target repository, checks out the exact submitted `commitHash`, and runs `BUILD`, `TEST`, and `COVERAGE` commands in the committed container environment.
* **Reporting**: Submits on-chain reports within `T_v1`:
  * `PASS` or `FAIL`: Transitions bounty to `REPORTED` alongside an `evidenceHash` commitment.
  * `ERROR` or `INCONCLUSIVE`: Preserves the evidence commitment on-chain and escalates directly to `DISPUTED` for V2 fallback without requiring a challenge bond.
* **Authority Revocation**: Permanently loses authority upon timing out or upon transitioning out of `VERIFYING`.

### 2.4 Secondary Verification Oracle (V2)
* **Role**: Designated dispute arbitration and fallback verification daemon (`SECONDARY_VERIFIER`).
* **Trigger Conditions**: Activated when a bounty enters `DISPUTED` via a maintainer/contributor challenge or via automatic recovery (claim timeout, V1 timeout, or V1 `ERROR`/`INCONCLUSIVE`).
* **Binary Verdict**: Re-evaluates the submission in an independent environment and reports strictly `PASS` (→ `SETTLED`) or `FAIL` (→ `REFUNDED`) within `T_v2`.

---

## 3. End-to-End Data Flow

```text
Maintainer                   Escrow Smart Contract                 Contributor
    │                                  │                                │
    ├─ 1. createBounty(specHash) ─────►│ [Reward escrow deposited]      │
    │     [State: ACTIVE]              │                                │
    │                                  │◄── 2. submitWork(commitHash) ──┤
    │                                  │       [State: SUBMITTED]       │
Primary Verifier (V1)                  │                                │
    │                                  │                                │
    ├─ 3. claimVerification() ────────►│ [State: VERIFYING]             │
    │     [Executes in container]      │                                │
    ├─ 4. reportVerification() ───────►│ [State: REPORTED / DISPUTED]   │
    │                                  │                                │
Maintainer / Contributor               │                                │
    │                                  │                                │
    ├─── 5. challengePass / Fail ─────►│ [Bond deposited; DISPUTED]     │
    │                                  │                                │
Secondary Verifier (V2)                │                                │
    │                                  │                                │
    ├─ 6. reportV2(PASS / FAIL) ──────►│ [Terminal Credit Created]      │
    │                                  │                                │
    │                                  │◄── 7. withdraw() / withdrawTo()┴─►
    │                                  │       [ETH transferred via pull]
```

### Detailed Lifecycle Steps

1. **Specification Commitment & Escrow Funding**:
   * Maintainer authors a JSON specification matching Schema v1.1.
   * Specification is canonicalized via RFC 8785 and hashed: `specHash = Keccak-256(RFC8785(spec))`.
   * Maintainer invokes `createBounty(specHash, submissionDeadline)` sending native ETH (`msg.value > 0`).
   * Contract records bounty in `ACTIVE` state and increments `totalRewardLiability`.

2. **Work Submission**:
   * Contributor checks out the base repository, implements the changes, commits them to Git, and obtains the 20-byte SHA-1 `commitHash`.
   * Contributor invokes `submitWork(bountyId, commitHash)` while `block.timestamp < submissionDeadline`.
   * Contract binds the contributor and commit hash, computes `claimDeadline = block.timestamp + T_claim`, and transitions bounty to `SUBMITTED`.

3. **Primary Verification**:
   * `PRIMARY_VERIFIER` claims the submission by invoking `claimVerification(bountyId)` while `block.timestamp < claimDeadline`.
   * Contract sets `verificationDeadline = block.timestamp + T_v1` and advances state to `VERIFYING`.
   * If V1 fails to claim before `claimDeadline`, anyone can call `expireClaim(bountyId)`, escalating the bounty directly to `DISPUTED` (`origin = CLAIM_TIMEOUT`) with `disputeDeadline = block.timestamp + T_v2`.

4. **Outcome Reporting**:
   * V1 executes the test suite in the container and computes `evidenceHash = Keccak-256(transcript)`.
   * V1 invokes `reportVerification(bountyId, outcome, evidenceHash)` while `block.timestamp < verificationDeadline`:
     * If `outcome` is `PASS` or `FAIL`: state becomes `REPORTED`, `challengeDeadline = block.timestamp + T_challenge`.
     * If `outcome` is `ERROR` or `INCONCLUSIVE`: state transitions to `DISPUTED` (`origin = V1_ERROR` or `V1_INCONCLUSIVE`), `disputeDeadline = block.timestamp + T_v2`, zero bond required.
   * If V1 fails to report before `verificationDeadline`, anyone can call `timeoutV1(bountyId)`, escalating directly to `DISPUTED` (`origin = V1_TIMEOUT`).

5. **Challenge Window**:
   * While in `REPORTED` and `block.timestamp < challengeDeadline`:
     * If V1 reported `PASS`: Maintainer can challenge by calling `challengePass(bountyId)` attaching the required bond $B_{chal} = \min(\text{reward}, \text{MAX\_BOND\_CAP})$. State transitions to `DISPUTED` (`origin = CHALLENGE_PASS`).
     * If V1 reported `FAIL`: Contributor can challenge by calling `challengeFail(bountyId)` attaching the required bond $B_{chal}$. State transitions to `DISPUTED` (`origin = CHALLENGE_FAIL`).
   * If unchallenged when `block.timestamp >= challengeDeadline`:
     * Anyone can call `finalizeReport(bountyId)`:
       * `PASS` → `SETTLED` (credits contributor `withdrawableBalance`).
       * `FAIL` → `REFUNDED` (credits maintainer `withdrawableBalance`).

6. **Secondary Dispute Resolution & Fallback**:
   * While in `DISPUTED` and `block.timestamp < disputeDeadline`:
     * `SECONDARY_VERIFIER` invokes `reportV2(bountyId, outcome, evidenceHash)` where `outcome` is strictly `PASS` or `FAIL`:
       * `PASS` → `SETTLED` (credits contributor reward; bond returned to challenger if upheld or transferred to counterparty if rejected).
       * `FAIL` → `REFUNDED` (credits maintainer reward; bond returned to challenger if upheld or transferred to counterparty if rejected).
   * If V2 times out (`block.timestamp >= disputeDeadline`):
     * Anyone can call `finalizeV2Timeout(bountyId)`:
       * `CHALLENGE_PASS` → `SETTLED` (contributor gets reward; maintainer gets 100% bond back).
       * `CHALLENGE_FAIL` → `REFUNDED` (maintainer gets reward; contributor gets 100% bond back).
       * Automatic Disputes (`V1_ERROR`, `V1_INCONCLUSIVE`, `V1_TIMEOUT`, `CLAIM_TIMEOUT`) → `REFUNDED` (unresolved-verification recovery; maintainer refunded).

7. **Pull-Payment Withdrawal**:
   * Terminal transitions NEVER execute external ETH calls (`.call`, `send`, `transfer`).
   * Payouts safely accrue in `withdrawableBalance[recipient]`.
   * Recipients call `withdraw()` (funds transferred to `msg.sender`) or `withdrawTo(destination)` (funds transferred to `destination`).

---

## 4. State Transition Model (7-State DAG)

The state machine implements a strict Directed Acyclic Graph (DAG) across seven states:

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
       │   VERIFYING   ├─► or reportVerification(ERR)  │         │
       └───┬───────────┘  (V1 loses authority)         │         │
           │                                           │         │
           │ reportVerification(PASS/FAIL)             │         │
           │ (timestamp < T_v1)                        │         │
           ▼                                           ▼         │
       ┌───────────────┐  challengePass / challengeFail ┌────────┐│
       │   REPORTED    ├──────────────────────────────►│        ││
       └───┬───────────┘  (timestamp < T_challenge)    │        ││
           │                                           │        ││
           ├─► PASS: finalizeReport() (ts>=T_ch) ─► SETTLED     ││
           ├─► FAIL: finalizeReport() (ts>=T_ch) ─► REFUNDED ◄──┼┤
           │                                           │        ││
           ▼                                           │DISPUTED││
                                                       │        ││
           ┌───────────────────────────────────────────┤        ││
           │                                           │        ││
           ├─► reportV2(PASS) (ts < T_v2) ────────► SETTLED     ││
           ├─► reportV2(FAIL) (ts < T_v2) ────────► REFUNDED ◄──┼┘
           ├─► finalizeV2Timeout() (ts >= T_v2):       │        │
           │   ├── origin == CHALLENGE_PASS ──────► SETTLED     │
           │   └── origin == other / Auto-Recovery► REFUNDED ◄──┘
```

| State | Description | Inbound Triggers | Outbound Transitions | Terminal? |
| :--- | :--- | :--- | :--- | :--- |
| `ACTIVE` | Bounty funded, awaiting work submission. | `createBounty()` | `SUBMITTED`, `REFUNDED` | No |
| `SUBMITTED` | Commit hash locked, awaiting V1 claim. | `submitWork()` | `VERIFYING`, `DISPUTED` | No |
| `VERIFYING` | V1 executing tests off-chain. | `claimVerification()` | `REPORTED`, `DISPUTED` | No |
| `REPORTED` | V1 reported PASS/FAIL, challenge window open. | `reportVerification()` | `DISPUTED`, `SETTLED`, `REFUNDED` | No |
| `DISPUTED` | Secondary verification under V2. | `challengePass()`, `challengeFail()`, `reportVerification(ERR)`, `expireClaim()`, `timeoutV1()` | `SETTLED`, `REFUNDED` | No |
| `SETTLED` | Terminal sink: reward disbursed to contributor. | `finalizeReport()`, `reportV2()`, `finalizeV2Timeout()` | *None* | **Yes** |
| `REFUNDED` | Terminal sink: reward returned to maintainer. | `cancelBounty()`, `expireBounty()`, `finalizeReport()`, `reportV2()`, `finalizeV2Timeout()` | *None* | **Yes** |

---

## 5. Trust Boundaries & Blockchain Guarantees

### 5.1 What the Blockchain Guarantees

* **Custody & Segregation**: Escrowed funds and challenge bonds are strictly secured on-chain. Challenge bonds cannot be used as bounty rewards.
* **Deterministic Accounting**: Internal liability counters (`totalRewardLiability`, `totalBondLiability`, `totalWithdrawableLiability`) guarantee solvency at all times:
  $$\text{address}(\text{this}).\text{balance} \ge \text{totalRewardLiability} + \text{totalBondLiability} + \text{totalWithdrawableLiability}$$
* **Strict State Invariance**: State transitions follow the 7-state DAG without back-tracking or retry cycles.
* **Commitment Integrity**: `specHash`, `commitHash`, and `evidenceHash` cannot be altered once written to storage.
* **Liveness & Timeout Enforcement**: Every state has a deterministic, permissionlessly callable progression once its deadline passes (`timestamp >= deadline`).
* **DOS-Immune Pull Settlement**: Unpayable smart contracts (reverting on `.call` or gas-limited) cannot block bounty terminalization because terminal transitions credit `withdrawableBalance` internally without making external calls.

### 5.2 What the Blockchain Does NOT Guarantee

* **Semantic Correctness of Software**: The smart contract commits to oracle verdicts; it does not compile or execute code on-chain.
* **Test Suite Quality**: A poorly authored test suite that passes buggy code will result in a `PASS` verdict and fund disbursement.
* **Oracle Honesty**: If both V1 and V2 collude or fail, the contract will execute their reported verdicts. Protocol v0.1 mitigates this via fixed deployment identities, symmetric challenge bonds, and deterministic timeout fallbacks, but verifier independence remains an off-chain trust assumption.
* **External Git Availability**: If GitHub or Git hosting goes offline, oracles cannot clone the repository.
* **Public Mempool Privacy**: In v0.1, submissions sent to public mempools can be observed by third parties (commit-reveal schemes are deferred to v0.2).
