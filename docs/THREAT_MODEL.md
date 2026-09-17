# TrustBounty Threat Model

## Assets

1. **Bounty Escrow Funds**: Cryptocurrency or tokens deposited by the maintainer into the smart contract escrow.
2. **Challenge Bonds**: Security deposits posted by either maintainer or contributor to initiate dispute arbitration.
3. **Specification Commitment**: The cryptographic `specHash` representing the canonicalized acceptance requirements.
4. **Submission Attribution**: The irrevocable binding between the contributor's identity and their submitted commit hash.
5. **Execution Evidence**: The `evidenceHash` tying off-chain execution transcripts and artifacts to verification reports.

## Actors

- **Maintainer**: Bounty creator who funds escrow, specifies `submissionDeadline`, and may act adversarially by refusing to settle, deploying flawed specifications, or submitting malicious challenges. Maintainers can voluntarily cancel an unclaimed bounty prior to submission (`cancelBounty()`), but cannot select or override verifiers per bounty.
- **Contributor**: Developer who submits work and may act adversarially by submitting broken code, exploiting test suite weaknesses, or challenging valid rejections.
- **Primary Verifier (V1)**: Off-chain verification oracle that executes tests; may fail by crashing, becoming unresponsive, or reporting incorrect verdicts.
- **Secondary Verifier (V2)**: Off-chain dispute arbitration oracle; may fail through collusion, unresponsiveness, or incorrect determinations.
- **Mempool Front-Runner**: Opportunistic actor monitoring the public transaction pool to copy submitted commit hashes and claim bounties.
- **Keepers / Callers**: Untrusted parties who invoke timeout, progression, and settlement functions on-chain.

## Trust Assumptions

- **Off-Chain Verification Oracles**: V1 and V2 are trusted off-chain verification oracles executing containerized tests off-chain.
- **Protocol-Level Verifier Immutability & Non-Upgradeability**: In v0.1, `PRIMARY_VERIFIER` and `SECONDARY_VERIFIER` are set at contract deployment and neither can be changed during the contract lifetime. Maintainers cannot override either verifier for an individual bounty, and the v0.1 contract is strictly non-upgradeable. No verifier registry, staking, governance, or proxy upgrade mechanisms exist. This prevents maintainers from selecting deliberately dead or collusive verifiers for individual bounties.
- **Centralized Oracle Trust**: While per-bounty maintainer verifier selection is eliminated, V1 and V2 remain trusted off-chain oracles; compromised or colluding protocol-level verifiers remain a residual trust assumption.
- **Dispute Oracle Finality**: V2 is trusted as the secondary dispute and fallback verification oracle in v0.1.
- **Test Quality**: Test criteria quality and test harness correctness remain assumptions outside smart contract enforcement.
- **External Git Hosting**: Git repository and commit availability depend on external hosting infrastructure.
- **EVM Execution & Timestamps**: EVM state execution and block timestamps are trusted within normal protocol bounds.

## Threats

### 1. Front-Running Submissions
In a public transaction pool, an adversary observing a `submitWork(commitHash)` transaction could submit the same commit hash with higher gas fees to claim the bounty.
- *Status in v0.1*: Acknowledged protocol limitation. Private transaction routing can mitigate exposure, but full cryptographic prevention (commit-reveal) is deferred to v0.2.

### 2. Abandoned ACTIVE Bounties (Maintainer Inaction)
A maintainer may create and fund an `ACTIVE` bounty and subsequently disappear or abandon the project without cancelling it, potentially locking escrow funds indefinitely.
- *Status in v0.1*: Mitigated by mandatory `submissionDeadline`. A contributor can submit work while `timestamp < submissionDeadline`. Before any submission is made, the maintainer may voluntarily cancel via `cancelBounty()`. If no submission exists once `timestamp >= submissionDeadline`, anyone can permissionlessly call `expireBounty()` to return escrow to the maintainer. A funded `ACTIVE` bounty cannot remain indefinitely locked if the maintainer disappears.

### 3. Verifier Inaction (Liveness Failure)
A primary verifier may never claim a submission (`SUBMITTED`), or claim it and never submit a report (`VERIFYING`), potentially freezing escrowed funds.
- *Status in v0.1*: Mitigated by `T_claim` (permissionless escalation to `DISPUTED` for V2 fallback when `timestamp >= submissionTimestamp + T_claim`) and `T_v1` (permissionless escalation to `DISPUTED` for V2 fallback when `timestamp >= verificationDeadline`). When V1 times out, no result or `evidenceHash` is required or fabricated, and V1 permanently loses authority.

### 4. Verification Failures and Non-Determinism
Flaky tests, non-deterministic environments, or crashed infrastructure could cause `ERROR` or `INCONCLUSIVE` verification executions.
- *Status in v0.1*: Mitigated by eliminating all retry cycles and attempt counters (`MAX_ATTEMPTS`). When V1 reports `ERROR` or `INCONCLUSIVE`, the contract records the result, the `evidenceHash`, and the report timestamp, preserving the primary evidence commitment on-chain without discarding it. The bounty transitions directly to `DISPUTED` without requiring a challenge bond, where secondary verifier V2 conducts secondary evaluation, ensuring acyclic forward progress.

### 5. Malicious Verifier Reporting
V1 may report a false `PASS` (harming maintainer) or false `FAIL` (harming contributor).
- *Status in v0.1*: Mitigated by the bounded challenge mechanism, allowing the aggrieved party to stake the protocol-configured `challengeBond` while `timestamp < reportedTimestamp + T_challenge` and trigger secondary arbitration by V2.

### 6. Secondary Verifier Inaction
V2 may become unresponsive after a dispute is initiated (`DISPUTED`), threatening to freeze funds during arbitration.
- *Status in v0.1*: Mitigated by `T_v2` timeout (`timestamp >= disputeDeadline`):
  - For challenge-originated disputes, resolves using V1's original report (`PASS` → `SETTLED`, `FAIL` → `REFUNDED`) and refunds 100% of the challenge bond to the challenger.
  - For automatic recovery disputes (V1 `ERROR`/`INCONCLUSIVE`, V1 timeout, or claim timeout + V2 timeout), resolves to `REFUNDED` as unresolved-verification recovery. This does not assert contributor fault; it is a bounded MVP recovery rule to prevent trapped funds; total oracle outage can prevent contributor payment.
  - Split settlement (e.g. 50/50) is strictly prohibited. This fallback is explicitly documented as a residual oracle/liveness limitation.

### 7. Griefing via Unwarranted Challenges
An actor may challenge a correct report solely to delay settlement or harass the counterparty.
- *Status in v0.1*: Mitigated by protocol-level `challengeBond` parameter enforcing $B_{chal} \le \min(\text{reward}, \text{MAX\_BOND\_CAP})$ (maintainer cannot select an arbitrary bond) and limiting disputes to exactly one challenge round. If the challenge is rejected (V2 confirms V1), the bond is transferred to the party whose V1 result was confirmed. Challenger receives 100% back if upheld or if V2 times out.

## Security Properties

- **Escrow Conservation**: Bounty funds cannot be extracted without reaching a valid terminal state (`SETTLED` or `REFUNDED`). Challenge bonds are strictly segregated and never used as bounty escrow.
- **Protocol-Level Verifier Immutability & Non-Upgradeability**: `PRIMARY_VERIFIER` and `SECONDARY_VERIFIER` are fixed at contract deployment and immutable for the contract lifetime; neither can be changed during contract lifetime, maintainers cannot override verifiers per bounty, and the contract is strictly non-upgradeable.
- **Strict DAG State Progression**: Elimination of all retry cycles guarantees monotonic, acyclic forward progression to terminal states (`SETTLED` or `REFUNDED`).
- **Universal Liveness Guarantee**: Every non-terminal state has a finite, permissionlessly executable progression or recovery mechanism (governed by exact `timestamp >= deadline` checks), ensuring the protocol cannot deadlock. In particular, a funded `ACTIVE` bounty cannot remain indefinitely locked if the maintainer disappears, as anyone can permissionlessly execute `expireBounty()` when `timestamp >= submissionDeadline`.
- **Primary Evidence Commitment Preservation**: When V1 calls `reportResult(ERROR)` or `reportResult(INCONCLUSIVE)`, the contract records the result, `evidenceHash`, and report timestamp on-chain before escalating to `DISPUTED`, ensuring the primary evidence commitment is preserved. When V1 times out, no fabricated result or `evidenceHash` is required.
- **Oracle Authority Expiry**: V1 permanently loses all authority upon its timeout deadline (`timestamp >= verificationDeadline`) or upon transition to `DISPUTED`, preventing late reports or re-claims.
- **Binary Dispute Outcomes**: V2 returns strictly `PASS` or `FAIL`.
- **Bounded Challenge Bond & Transfer**: Challenge bonds are bounded by $B_{chal} \le \min(\text{reward}, \text{MAX\_BOND\_CAP})$, returned 100% on upheld challenges or V2 timeouts, and transferred to the confirmed counterparty upon rejected challenges.
- **Unresolved-Verification Recovery**: Oracle timeouts and failures during automatic recovery exhaust to `REFUNDED` without asserting contributor fault.
- **Specification Immutability**: The criteria and environment commitments are immutable after bounty activation, preventing retroactive requirement changes.
- **Submission Immutability**: The first accepted submission binds the bounty to that contributor address for the current submission lifecycle; no concurrent or subsequent overwrites are permitted.
- **Challenge Symmetry**: Maintainers can challenge `PASS` reports; contributors can challenge `FAIL` reports under identical structural conditions.

## Mitigations

| Threat | Protocol Mitigation |
| :--- | :--- |
| Abandoned ACTIVE Bounty Deadlock | Mandatory `submissionDeadline`; permissionless `expireBounty()` refund (`timestamp >= submissionDeadline`) if no submission exists. |
| Voluntary Bounty Cancellation | Maintainer `cancelBounty()` allowed while `ACTIVE` and before any submission exists. |
| Unclaimed Submission Deadlock | Permissionless `T_claim` timeout (`timestamp >= deadline`) escalates to `DISPUTED` for V2 fallback. |
| Unresponsive Primary Verifier | Permissionless `T_v1` timeout (`timestamp >= deadline`) escalates to `DISPUTED` for V2 fallback; V1 loses authority without requiring fabricated evidence. |
| Infrastructure Failures & Errors | V1 `ERROR` or `INCONCLUSIVE` records result, `evidenceHash`, and timestamp on-chain and transitions directly to `DISPUTED` for V2 fallback verification without retry loops. |
| Erroneous V1 Verdicts | Bounded challenge window `T_challenge` (`timestamp < deadline`) with secondary verification by V2. |
| Unresponsive Secondary Verifier | Permissionless `T_v2` dispute timeout (`timestamp >= deadline`) falling back to V1 verdict or unresolved-verification recovery. |
| Malicious Maintainer Verifier Selection | Protocol-level immutable verifier identities (`PRIMARY_VERIFIER`, `SECONDARY_VERIFIER`); non-upgradeable contract; cannot be overridden per bounty. |
| Specification Tampering | RFC 8785 canonicalization and Keccak-256 `specHash` commitment. |
| Environment Drift | Mandatory container image commitment with SHA-256 digest (`image@sha256:...`). |
| Public Mempool Exposure | Private RPC submission recommendation (commit-reveal deferred to v0.2). |

## Residual Risks

1. **Oracle Trust Dependency**: Both V1 and V2 operate as trusted off-chain verification oracles. A collusive or compromised oracle pair can produce incorrect settlement.
2. **Centralized Protocol Verifier Trust**: Verifier identities are fixed at deployment rather than selected per-bounty by maintainers, mitigating per-bounty maintainer sybil selection. However, compromised or colluding protocol-level verifiers remain a fundamental residual trust assumption in this centralized oracle model.
3. **Public Mempool Front-Running**: The protocol does not cryptographically eliminate front-running in public mempools in v0.1.
4. **Test Quality Assumption**: Passing tests verify only the criteria defined in the specification; they do not guarantee absence of backdoors, regressions outside test coverage, or broader specification gaming.
5. **Execution Commitment vs. Execution Proof**: Pinned execution-environment commitment (`image@sha256:...`) guarantees specification integrity, but is not cryptographic proof of execution honesty by the off-chain oracle.
6. **External Git Hosting Dependency**: The protocol relies on third-party Git hosting platforms for source tree and commit availability.
7. **Secondary Verifier Timeout Fallback**: If V2 times out during a dispute (`timestamp >= disputeDeadline`), falling back to V1's verdict inherently re-trusts V1 despite an active challenge.
8. **Total Oracle Outage Risk**: Total oracle outage (V1 failure/timeout + V2 timeout) triggers unresolved-verification recovery, returning funds to the maintainer without asserting contributor fault, which can prevent payment for valid work during severe oracle infrastructure failure. No 50/50 split settlement is supported.

## Open Questions

- Implementation of a cryptographic commit-reveal mechanism for work submission in v0.2.
- Decentralized oracle selection, staking, or multi-verifier consensus to reduce single-oracle trust.
- Integration of zero-knowledge proofs or trusted execution environments (TEEs) to provide verifiable execution traces.
- Empirical modeling of dynamic challenge bond pricing to balance dispute accessibility with griefing resistance.
