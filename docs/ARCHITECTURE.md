# TrustBounty System Architecture (v0.1)

## 1. System Overview

TrustBounty is a blockchain-based protocol for trust-minimized settlement of open-source software contribution bounties. It coordinates maintainer acceptance requirements with containerized off-chain verification oracles and non-blocking on-chain escrow.

Maintainers define acceptance requirements in a machine-readable specification committed to the blockchain before development begins. Contributors submit specific software revisions, off-chain containerized verification engines evaluate the revision against the committed criteria, and on-chain escrow deterministically settles the bounty based on reported verification outcomes and bounded challenge mechanisms.

---

## 2. System Architecture & Tiered Structure

TrustBounty v0.1 architecture is organized across five distinct tiers, strictly separating on-chain enforcement from off-chain processing:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│              TIER 1: ON-CHAIN ESCROW & STATE MACHINE                    │
│                        (TrustBounty.sol) [IMPLEMENTED NOW]              │
│  - Native ETH Escrow & Segregated Liability Accounting                  │
│  - 7-State Directed Acyclic Graph (DAG) State Transitions               │
│  - Non-Blocking Pull-Payment Subsystem (withdraw, withdrawTo)           │
├─────────────────────────────────────────────────────────────────────────┤
│          TIER 2: OPAQUE COMMITMENTS & ROLE ANCHORS                      │
│                (Storage & External Interface) [IMPLEMENTED NOW]         │
│  - Opaque Cryptographic Commitments: specHash, commitHash, evidenceHash │
│  - Immutable Verifier Role Bindings: PRIMARY_VERIFIER, SECONDARY_VERIFIER│
├─────────────────────────────────────────────────────────────────────────┤
│        TIER 3: OFF-CHAIN ACCEPTANCE SPECIFICATION ENGINE                │
│                 (specification/) [PLANNED / PHASE 2]                    │
│  - Schema v1.1 Validation & RFC 8785 (JCS) Canonicalization             │
│  - Off-Chain Keccak-256 specHash Generation                             │
├─────────────────────────────────────────────────────────────────────────┤
│        TIER 4: OFF-CHAIN VERIFIER & EXECUTION INFRASTRUCTURE            │
│               (verifier/ & testbed) [PLANNED / PHASE 2]                 │
│  - Autonomous V1 & V2 Verification Oracle Daemons                       │
│  - Isolated Docker Sandbox & Criteria Execution Harness                 │
│  - Evidence Bundle Generator & Anvil Integration Harness                │
├─────────────────────────────────────────────────────────────────────────┤
│              TIER 5: EXTERNAL INFRASTRUCTURE & DEPENDENCIES             │
│  - Git Repositories (GitHub, GitLab), OCI Registries, EVM Nodes         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Tier 1: On-Chain Escrow & State Machine (`contracts/src/TrustBounty.sol`) [IMPLEMENTED NOW]
* **Role**: Non-upgradeable, monolithic smart contract holding escrowed funds and enforcing protocol invariants.
* **State Machine**: Enforces monotonic forward progression across the 7-state DAG (`ACTIVE`, `SUBMITTED`, `VERIFYING`, `REPORTED`, `DISPUTED`, `SETTLED`, `REFUNDED`) without retry cycles.
* **Accounting**: Maintains explicit segregated liabilities (`totalRewardLiability`, `totalBondLiability`, `totalWithdrawableLiability`) preventing insolvency or fund mingling.
* **Pull-Payment Subsystem**: Credits recipient balances during terminalization without external calls, exposing `withdraw()` and `withdrawTo(destination)` for secure pull-based fund retrieval.

### 2.2 Tier 2: Opaque Commitment Anchors & On-Chain Interface [IMPLEMENTED NOW]
* **Role**: On-chain storage fields and interfaces binding off-chain data commitments and oracle roles.
* **Specification Commitment**: The contract receives and stores an opaque `bytes32 specHash`. The contract does NOT parse, validate, or canonicalize JSON.
* **Work Attribution**: The contributor submits an opaque `bytes20 commitHash`. The contract validates only that it is non-zero (`commitHash != bytes20(0)`) and stores that identifier. The contract does not verify repository membership, Git object validity, tree contents, or commit ancestry. `reportVerification()` does NOT accept a second commit hash from V1 for an on-chain equality check.
* **Evidence Commitment**: Verifiers submit an opaque `bytes32 evidenceHash`. The contract stores the hash without inspecting or verifying the underlying transcript on-chain.
* **Verifier Role Authorization**: The contract authorizes V1/V2 through fixed deployment-level verifier addresses using `msg.sender == PRIMARY_VERIFIER` and `msg.sender == SECONDARY_VERIFIER`. The contract does NOT verify oracle cryptographic signatures, perform `ecrecover`, or verify EIP-712 signatures.

### 2.3 Tier 3: Acceptance Specification Processing Module [PLANNED / PHASE 2]
* **Role**: Tooling for authoring, validating, and serializing machine-readable criteria under Schema v1.1.
* **Environment Pinning**: Binds the execution environment to a container image digest (`image@sha256:...`).
* **Deterministic Hashing**: Applies RFC 8785 JSON Canonicalization Scheme (JCS) and computes the 32-byte commitment `specHash = Keccak-256(RFC8785(specification))` entirely off-chain prior to bounty creation.

### 2.4 Tier 4: Off-Chain Verifier & Execution Infrastructure [PLANNED / PHASE 2]
* **Primary Verifier (V1) Daemon**: Autonomous off-chain execution service holding the private key for `PRIMARY_VERIFIER`. Monitors on-chain `WorkSubmitted` events, claims tasks within `T_claim`, clones the target repository, checks out the submitted commit, and executes `BUILD`, `TEST`, and `COVERAGE` criteria inside an isolated container. Reports verdicts (`PASS`, `FAIL`, `ERROR`, `INCONCLUSIVE`) and evidence commitments on-chain within `T_v1`.
* **Secondary Verifier (V2) Daemon**: Autonomous dispute arbitration service holding the private key for `SECONDARY_VERIFIER`. Activated upon transition to `DISPUTED` (via challenge or automatic recovery), re-executes criteria in an independent sandbox, and reports strictly binary verdicts (`PASS` or `FAIL`) within `T_v2`.
* **Evidence Bundle Generation & Anvil Harness**: Off-chain tools collecting structured execution transcripts and driving integration testing against local Anvil nodes.

### 2.5 Tier 5: External Infrastructure & Dependencies
* **External Services**: Git hosting platforms, container registries, and EVM network nodes outside the direct control of the protocol.

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

## 5. Trust Boundaries & Protocol Guarantees

### 5.1 What the Blockchain Guarantees

* **Custody & Segregation**: Escrowed funds and challenge bonds are strictly secured on-chain. Challenge bonds cannot be used as bounty rewards.
* **Solvency Invariant**: The contract satisfies the accounting invariant:
  $$\text{address}(\text{this}).\text{balance} \ge \text{totalRewardLiability} + \text{totalBondLiability} + \text{totalWithdrawableLiability}$$
  This is an accounting/solvency invariant maintained by the contract implementation and validated by the test suite; it is not an on-chain runtime assertion executed after each operation.
* **Strict State Invariance**: State transitions follow the 7-state DAG without back-tracking or retry cycles.
* **Commitment Integrity**: `specHash`, `commitHash`, and `evidenceHash` cannot be altered once written to storage.
* **Liveness & Timeout Progression**: The protocol provides permissionless progression to terminal states after the relevant deadlines, but this does not guarantee successful verification or contributor payment when verifier infrastructure fails.
* **DOS-Immune Pull Settlement**: Unpayable smart contracts (reverting on `.call` or gas-limited) cannot block bounty terminalization because terminal transitions credit `withdrawableBalance` internally without making external calls.
* **Forced ETH Surplus**: Forced or unallocated ETH (e.g. from `selfdestruct` or mining coinbase) may increase `address(this).balance` above the sum of liabilities. Such surplus is not represented in liability counters. Version 0.1 has no sweep or recovery mechanism; such surplus therefore remains trapped and unallocated in the contract without compromising solvency or accounting for legitimate credits.

### 5.2 What the Blockchain Does NOT Guarantee

* **Semantic Correctness of Software**: The smart contract commits to oracle verdicts; it does not compile or execute code on-chain.
* **Git Repository & Object Verification**: The smart contract validates only that `commitHash != bytes20(0)` and stores the identifier. It does not verify repository membership, Git object validity, tree contents, or commit ancestry. Off-chain verifier infrastructure is responsible for obtaining and checking out the commit. `reportVerification()` does NOT accept a second commit hash from V1 for an on-chain equality check.
* **Oracle Signature Verification**: The contract authorizes V1/V2 through fixed deployment-level verifier addresses using `msg.sender == PRIMARY_VERIFIER` and `msg.sender == SECONDARY_VERIFIER`. It does NOT verify oracle cryptographic signatures, perform `ecrecover`, or verify EIP-712 signatures.
* **Container Execution Reproducibility**: The pinned container digest (`image@sha256:...`) binds image filesystem contents. However, host kernel, hardware architecture, CPU scheduling, network access, and external runtime dependencies can still introduce variability across execution hosts.
* **Test Suite Quality**: A poorly authored test suite that passes non-functional code will result in a `PASS` verdict and fund disbursement.
* **Oracle Honesty**: If both V1 and V2 collude or fail, the contract will execute their reported verdicts. Protocol v0.1 mitigates this via fixed deployment identities, symmetric challenge bonds, and deterministic timeout fallbacks, but verifier independence remains an off-chain trust assumption.
* **External Git Availability**: If GitHub or Git hosting goes offline, oracles cannot clone the repository.
* **Public Mempool Privacy**: In v0.1, submissions sent to public mempools can be observed by third parties (commit-reveal schemes are deferred to v0.2).
