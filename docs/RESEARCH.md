# TrustBounty Research Framing & Empirical Evaluation (v0.1)

## 1. Research Motivation & Problem Definition

Open-source software (OSS) bounties represent a critical economic mechanism for funding software development. However, existing bounty platforms face systemic trust, coordination, and incentive breakdowns:

1. **Information Asymmetry & Subjective Rejection**: Maintainers retain unilateral discretionary authority over pull request acceptance. Contributors risk investing substantial engineering effort only to have PRs rejected without compensation or merged without bounty disbursement.
2. **Oracle Lock-in & Single-Point-of-Failure**: Centralized bounty platforms rely on platform staff for dispute arbitration. If the platform is non-responsive or biased, funds are trapped or arbitrarily disbursed.
3. **Griefing & Indefinite Escrow Deadlock**: In existing blockchain escrow protocols, unresponsive counterparties or failing oracles can freeze escrowed assets indefinitely, or force expensive retry cycles.

### 1.1 Why Standard Building Blocks Alone Are Insufficient

Combining smart contracts, continuous integration (CI) runners, and Docker containers does not inherently establish academic or protocol novelty:
* **Smart contract escrows** exist in numerous financial and gig-economy applications.
* **CI/CD container runners** (e.g. GitHub Actions, GitLab CI) are well-established engineering tools.
* **Oracles** (e.g. Chainlink, UMA) routinely bridge off-chain data to on-chain state.

The research problem TrustBounty tackles is: **How can a decentralized protocol achieve deterministic, dispute-resilient software bounty settlement without creating retry deadlocks, griefing vulnerabilities, or unbounded oracle trust?**

---

## 2. Positioning: Trust-Minimized Oracle Coordination

TrustBounty v0.1 positions itself as a **trust-minimized oracle coordination protocol**, explicitly distinguishing its scope from cryptographic proof systems:

* **What TrustBounty IS**:
  * An acyclic 7-state DAG state machine providing permissionless timeout progression to deterministic terminalization (`SETTLED` or `REFUNDED`) once deadlines expire, preventing indefinite contract deadlock across oracle crash scenarios.
  * A dual-verifier architecture (`PRIMARY_VERIFIER` and `SECONDARY_VERIFIER`) with bounded symmetric challenge bonds ($B_{chal} = \min(\text{reward}, \text{MAX\_BOND\_CAP})$) to deter griefing while enabling error correction.
  * A non-blocking pull-payment architecture with strict internal liability conservation.
* **What TrustBounty IS NOT**:
  * It is **not** a zero-knowledge proof of software correctness.
  * It does **not** claim novel cryptographic hash functions or primitives (it relies on standard Keccak-256 and RFC 8785 JCS).
  * It does **not** solve general code correctness or eliminate the need for sound human-authored test suites.

---

## 3. Measurable Research Questions (RQs)

TrustBounty’s future empirical evaluation will investigate five specific research questions:

* **RQ1 (Deadlock Resistance & Timeout Progression)**: Does the acyclic 7-state DAG state machine prevent indefinite escrow lockups via permissionless timeout fallbacks across single-oracle and dual-oracle failure modes compared to retry-based state machines?
* **RQ2 (Economic Efficiency of Challenge Bonds)**: Does bounding challenge bonds by $B_{chal} = \min(\text{reward}, \text{MAX\_BOND\_CAP})$ deter malicious challenges while keeping dispute arbitration economically accessible for contributors?
* **RQ3 (Verifier Divergence & Reproducibility)**: What is the empirical divergence rate between independent off-chain verifiers (V1 vs. V2) executing identical RFC 8785-canonicalized specifications across standardized open-source benchmarks?
* **RQ4 (On-Chain & Off-Chain Overhead)**: What are the gas costs, settlement latency, and compute/storage requirements across each execution path (happy path, unchallenged rejection, challenge-upheld, challenge-rejected, and timeout fallback)?
* **RQ5 (False Acceptance vs. False Rejection)**: What is the rate of false positive settlements (buggy code passing weak test suites) versus false negative refunds (valid code failing due to test environment drift)?

---

## 4. Planned Evaluation Metrics & Benchmarking Methodology

### 4.1 Quantitative Evaluation Metrics

| Metric | Category | Description | Target / Measurement Unit |
| :--- | :--- | :--- | :--- |
| **Dispute Rate** | Economic | Proportion of bounties that enter `DISPUTED` via challenge. | Percentage ($\%$) |
| **Verifier Agreement** | Reliability | Rate at which V1 and V2 independently produce identical outcomes. | Concordance ($\%$) |
| **Time-to-Settlement** | Performance | Wall-clock latency from `createBounty` to terminal withdrawal. | Hours / Days |
| **Gas Consumption** | On-Chain Cost | Gas consumed per lifecycle function and total lifecycle cost. | Gas units (and ETH equivalent at target base fee) |
| **False Acceptance Rate (FAR)** | Security | Proportion of bounties settled despite known defects present. | Percentage ($\%$) |
| **False Rejection Rate (FRR)** | Liveness | Proportion of bounties refunded despite correct implementations. | Percentage ($\%$) |
| **Deadlock Occurrence** | Safety | Number of bounties stuck in non-terminal state after timeout. | Exactly 0 |

### 4.2 Planned Benchmark Datasets & Testbeds

1. **Defects4J / SWE-bench Evaluation**:
   * Use curated, real-world bug-fix datasets (e.g. SWE-bench, Defects4J, ManyBugs).
   * Formulate canonical v1.1 specifications for benchmark tasks with pinned container environments.
   * Evaluate verifier determinism, execution consistency, and coverage thresholds across thousands of commits.
2. **Adversarial Fault-Injection Testbed**:
   * Simulate flaky tests, non-deterministic timers, memory exhaustion, network drops, and corrupted oracle nodes.
   * Verify that the smart contract advances to `DISPUTED` and reaches terminal states cleanly via verifier report or permissionless timeout.

---

## 5. Scope, Limitations & Novelty Boundaries

To maintain rigorous scientific and engineering integrity, TrustBounty explicitly delineates:

* **Engineering Integration vs. Research Contribution**:
  * *Engineering Integration*: Wiring Foundry smart contracts, Docker containers, GitHub webhooks, and TypeScript serializers.
  * *Research Contribution*: Formal analysis of the acyclic state machine, game-theoretic analysis of symmetric challenge bonds, and empirical characterization of off-chain containerized verifier agreement.
* **No Cryptographic Primitive Claims**: The protocol utilizes standard, existing cryptography (Keccak-256, off-chain Git SHA-1, RFC 8785).
* **Current Limitations in v0.1**:
  * Designated, centralized oracle accounts (deployment-immutable V1/V2 checked via `msg.sender == PRIMARY_VERIFIER` / `msg.sender == SECONDARY_VERIFIER`, with no cryptographic signature or EIP-712 verification on-chain).
  * Opaque commit identifiers: `commitHash` is an opaque `bytes20` parameter checked only for non-zero; no Git tree or object parsing occurs on-chain.
  * Container reproducibility constraints: While digest pinning fixes container rootfs bits, host kernel, CPU architecture, scheduler, and runtime flags can cause divergent test outcomes.
  * Susceptibility to public mempool front-running (commit-reveal deferred to v0.2).
  * Single-contributor binding per bounty (multi-contributor competition deferred to v0.2).
