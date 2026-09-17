# TrustBounty Architecture

## System Overview

TrustBounty is a blockchain-based protocol for trust-minimized settlement of open-source software contribution bounties. It connects maintainer acceptance requirements with off-chain verification oracles and on-chain escrow.

Maintainers define acceptance requirements in a machine-readable specification committed to the blockchain before development begins. Contributors submit specific software revisions, off-chain containerized verification engines evaluate the revision against the committed criteria, and on-chain escrow deterministically settles the bounty based on reported verification outcomes and bounded challenge mechanisms.

## Components

1. **Escrow Smart Contract**:
   - Manages bounty deposits, challenge bonds, and state transitions.
   - Enforces the 7-state machine: `ACTIVE`, `SUBMITTED`, `VERIFYING`, `REPORTED`, `DISPUTED`, `SETTLED`, `REFUNDED`.
   - Stores and enforces protocol-level verifier identities (`PRIMARY_VERIFIER` and `SECONDARY_VERIFIER`) configured at deployment and immutable for the contract lifetime; the contract is non-upgradeable and maintainers cannot select or override verifiers per bounty.
   - Enforces protocol-level parameters, including challenge bond bounds ($B_{chal} \le \min(\text{reward}, \text{MAX\_BOND\_CAP})$).
   - Tracks timeouts (`submissionDeadline`, `T_claim`, `T_v1`, `T_challenge`, `T_v2`) and exposes permissionless progression functions (including `expireBounty()`).
   - Disburses funds upon reaching terminal settlement or refund.

2. **Acceptance Specification Module**:
   - Formulates machine-readable criteria (`BUILD`, `TEST`, `COVERAGE`) under schema v1.1.
   - Binds the execution environment to an immutable container digest (`image@sha256:...`).
   - Normalizes data via RFC 8785 JSON Canonicalization Scheme (JCS).
   - Generates the immutable on-chain commitment `specHash = Keccak-256(RFC8785(specification))`.

3. **Primary Verification Oracle (V1)**:
   - Protocol-configured off-chain execution service (`PRIMARY_VERIFIER`) monitoring on-chain submissions.
   - Clones target repositories, checks out submitted commit hashes, and executes commands inside the committed container image.
   - Submits structured on-chain reports: `PASS` or `FAIL` (advancing to `REPORTED`), or `ERROR`/`INCONCLUSIVE` (recording the result, `evidenceHash`, and timestamp on-chain and advancing directly to `DISPUTED`), preserving the primary evidence commitment.
   - When timing out, transitions to `DISPUTED` without requiring or fabricating a result or `evidenceHash`.
   - Permanently loses authority after its timeout deadline or upon transition to `DISPUTED`.

4. **Secondary Verification Oracle (V2)**:
   - Protocol-configured dispute arbitration and fallback verification service (`SECONDARY_VERIFIER`).
   - Evaluates submissions when a challenge is lodged during the challenge window or when automatic dispute recovery occurs (claim timeout, V1 timeout, or V1 `ERROR`/`INCONCLUSIVE`).
   - Provides a strictly binary `PASS` or `FAIL` determination on-chain.

5. **Storage & Evidence Layer**:
   - Retains off-chain test logs, execution streams, and coverage artifacts.
   - Computes the `evidenceHash` commitment submitted to the smart contract.

## Trust Boundaries

- **On-Chain vs. Off-Chain**: The smart contract enforces custody, state transitions, and deadlines without executing software. Software evaluation is delegated to off-chain verification oracles (V1 and V2).
- **Maintainer vs. Contributor**: Neither party is trusted. The maintainer is bound by the immutable specification commitment and cannot retroactively adjust criteria. The contributor is bound by their submitted commit hash for the current submission lifecycle. Both parties have symmetric challenge rights with protocol-bounded challenge bonds.
- **Protocol vs. Oracles**: V1 and V2 remain trusted off-chain oracles in a centralized oracle model. In v0.1, the protocol fixes verifier identities (`PRIMARY_VERIFIER`, `SECONDARY_VERIFIER`) at the deployment level as immutable, non-upgradeable parameters, preventing maintainers from selecting deliberately dead or collusive verifiers for individual bounties. However, compromised or colluding protocol-level verifiers remain a residual trust assumption. The protocol constrains oracle authority through strictly bounded execution windows (`timestamp < deadline`), complete expiration of V1 authority upon timeout, symmetric challenge mechanisms, and deterministic timeout fallbacks without retry loops.
- **Protocol vs. Code Hosting**: The blockchain tracks cryptographic hashes (`commitHash`, `specHash`). Availability and integrity of repository history depend on external Git hosting infrastructure.

## Data Flow

```text
Maintainer                     Blockchain Escrow                   Contributor
    │                                  │                                │
    ├─ 1. Create Bounty (specHash) ───►│ [Binds protocol V1/V2]         │
    │     Deposit Bounty Escrow        │                                │
    │     [cancelBounty() /            │                                │
    │      expireBounty() -> Refund]   │◄── 2. submitWork(commitHash) ──┤
    │                                  │       [ts < submissionDeadline]│
Primary Verifier (V1)                  │                                │
    │                                  │                                │
    ├─ 3. claimVerification() [ts<T_cl]►│                               │
    │     [Executes in container]      │                                │
    ├─ 4. reportResult(PASS/FAIL) ────►│ [or DISPUTED on timeout/ERR]   │
    │                                  │                                │
Maintainer / Contributor               │                                │
    │                                  │                                │
    ├─── 5. challenge(bond) [ts<T_ch] ─►│                               │
    │                                  │                                │
Secondary Verifier (V2)                │                                │
    │                                  │                                │
    ├─ 6. resolveDispute(PASS/FAIL) ──►│ [or fallback on V2 timeout]    │
    │                                  │                                │
    │                                  ├─ 7. Payout / Refund ───────────┴─►
```

1. **Specification & Funding**: Maintainer canonicalizes the specification, computes `specHash`, specifies `submissionDeadline`, deploys the bounty contract using protocol-configured immutable verifier identities, and deposits escrow funds. State becomes `ACTIVE`. Maintainers cannot override verifiers per bounty. Before submission, the maintainer may voluntarily cancel (`cancelBounty()`); if no submission is made before the deadline (`timestamp >= submissionDeadline`), anyone can permissionlessly trigger an expiry refund via `expireBounty()`. A funded `ACTIVE` bounty cannot remain indefinitely locked if the maintainer disappears.
2. **Work Submission**: Contributor submits the exact Git `commitHash` while `timestamp < submissionDeadline`. State becomes `SUBMITTED`.
3. **Primary Claim & Execution**: V1 claims the task while `timestamp < submissionTimestamp + T_claim`. State becomes `VERIFYING`. If unclaimed when `timestamp >= submissionTimestamp + T_claim`, `expireClaim()` advances state directly to `DISPUTED` for V2 fallback.
4. **Outcome Reporting**: V1 evaluates the contribution in the committed container. While `timestamp < verificationDeadline`:
   - Reporting `PASS` or `FAIL` transitions to `REPORTED` with the `evidenceHash`.
   - Reporting `ERROR` or `INCONCLUSIVE` records the result, `evidenceHash`, and report timestamp on-chain and transitions directly to `DISPUTED` without requiring a challenge bond, preserving the evidence commitment.
   - Timing out (`timestamp >= verificationDeadline`) triggers a permissionless transition directly to `DISPUTED` without requiring or fabricating a result or `evidenceHash`. V1 permanently loses authority.
5. **Challenge Window**:
   - If `PASS`, maintainer may challenge while `timestamp < reportedTimestamp + T_challenge` by depositing the protocol-configured `challengeBond` ($B_{chal} \le \min(\text{reward}, \text{MAX\_BOND\_CAP})$).
   - If `FAIL`, contributor may challenge while `timestamp < reportedTimestamp + T_challenge` by depositing the protocol-configured `challengeBond`.
   - If unchallenged, once `timestamp >= reportedTimestamp + T_challenge`, bounty finalizes to `SETTLED` (if `PASS`) or `REFUNDED` (if `FAIL`).
6. **Dispute Resolution**: If `DISPUTED` (challenge-originated or automatic recovery):
   - V2 independently verifies the submission and submits strictly `PASS` (→ `SETTLED`) or `FAIL` (→ `REFUNDED`) while `timestamp < disputeDeadline`.
   - If challenge-originated: upheld challenge returns 100% of bond to challenger; rejected challenge transfers the bond to the confirmed counterparty.
   - If V2 times out (`timestamp >= disputeDeadline`): challenge-originated disputes fall back to V1's verdict with 100% bond return; automatic recovery disputes fall back to `REFUNDED` as unresolved-verification recovery (without asserting contributor fault; bounded MVP recovery rule; total oracle outage can prevent contributor payment). Split settlement (e.g. 50/50) is strictly prohibited.
7. **Settlement**: Funds are disbursed to the contributor (`SETTLED`) or returned to the maintainer (`REFUNDED`). Every non-terminal state has a finite, permissionlessly executable progression or recovery mechanism.

## Blockchain Responsibilities

- **Custody**: Holding bounty escrow and challenge bonds securely with strict segregation.
- **State Enforcement**: Ensuring state transitions strictly obey DAG transition rules and authorizations without retry cycles.
- **Commitment Registration**: Storing immutable hashes (`specHash`, `commitHash`, `evidenceHash`).
- **Liveness & Timeout Progression**: Enforcing standardized deadlines (`action < deadline`, `timeout >= deadline`) and enabling permissionless progression and timeout mechanisms (including `expireBounty()`, `expireClaim()`, `timeoutV1()`, `finalize()`, and `timeoutV2()`). Every non-terminal state has a finite, permissionlessly executable progression or recovery mechanism.
- **Disbursement**: Executing atomic payout or refund based on terminal states.
- **Out of Scope**: The blockchain does NOT execute code, clone Git repositories, parse test output, or communicate directly with external APIs.

## Off-Chain Responsibilities

- **Repository Operations**: Fetching repository source code and checking out the submitted commit hash.
- **Container Provisioning**: Pulling and verifying the container image designated by the immutable digest (`image@sha256:...`).
- **Execution & Monitoring**: Running specified commands (`BUILD`, `TEST`, `COVERAGE`) under process isolation.
- **Metric Verification**: Parsing test exit codes and coverage outputs against specified thresholds.
- **Evidence Packaging**: Storing execution logs, computing the Keccak-256 `evidenceHash`, and reporting outcomes on-chain.

## Open Design Questions

1. **Anti-Front-Running Architecture**: Evaluating two-phase commit-reveal schemes to shield submissions in public mempools in protocol v0.2.
2. **Decentralized Oracle Networks**: Exploring multi-verifier staking consensus, threshold signatures, or TEE/zkVM attestations to reduce reliance on designated oracles.
3. **Concurrent Multi-Contributor Workflows**: Designing queuing or parallel evaluation pipelines for open competitive bounties.
