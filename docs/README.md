# TrustBounty Documentation Directory (v0.1)

Welcome to the TrustBounty protocol documentation. This directory contains the normative specifications, architectural designs, security threat models, verification contracts, and research roadmaps for the TrustBounty system.

---

## 1. Normative Precedence Rule

> [!IMPORTANT]
> **Authoritative Precedence**:
> In the event of any ambiguity, discrepancy, or conflict between narrative documentation and on-chain protocol behavior, **[`CONTRACT_SPEC.md`](CONTRACT_SPEC.md)** is the frozen, authoritative normative specification for on-chain smart contract behavior, storage layout, error handling, events, and accounting.

---

## 2. Documentation Index

### 2.1 Normative Specifications
* **[`CONTRACT_SPEC.md`](CONTRACT_SPEC.md)** — **Authoritative Protocol Specification (v0.1)**
  * Complete EVM smart contract specification: 7-state DAG, storage layout, error selectors, exact event signatures, pull-payment accounting, authorization matrices, and formal invariants.
* **[`VERIFICATION_SPEC.md`](VERIFICATION_SPEC.md)** — **Off-Chain Verification Contract**
  * Specification input formatting (Schema v1.1), RFC 8785 JCS canonicalization, container execution constraints, `BUILD`/`TEST`/`COVERAGE` criteria evaluation, outcome mapping, and `evidenceHash` commitments.
* **[`SPECIFICATION.md`](SPECIFICATION.md)** — **Acceptance Specification Module Reference**
  * Reference documentation for the TypeScript specification library in `specification/`.

### 2.2 System Architecture & Design Records
* **[`ARCHITECTURE.md`](ARCHITECTURE.md)** — **Protocol Architecture & System Design**
  * End-to-end data flows, component relationships, on-chain/off-chain trust boundaries, and blockchain responsibility limits.
* **[`DECISIONS.md`](DECISIONS.md)** — **Architectural Decision Records (ADRs)**
  * Log of all foundational architectural decisions (7-state DAG, native ETH only, pull payments, immutable verifiers, stack-depth mitigation, etc.).

### 2.3 Security & Quality Assurance
* **[`THREAT_MODEL.md`](THREAT_MODEL.md)** — **Security Analysis & Threat Model**
  * Adversarial actor profiles, threat vectors (maintainer, contributor, V1, V2, front-running, reentrancy, unpayable recipients), protocol mitigations, and residual trust assumptions.
* **[`TESTING.md`](TESTING.md)** — **Testing Strategy & Test Matrix**
  * Test hierarchy, complete testing suite status (256 tests in `TrustBounty.t.sol` covering deterministic unit, boundary, invariant, fuzz, adversarial, and stateful multi-bounty tests).

### 2.4 Research & Evaluation
* **[`RESEARCH.md`](RESEARCH.md)** — **Research Framing & Empirical Metrics**
  * Problem definition, trust-minimized positioning, measurable research questions (RQ1–RQ5), benchmark datasets, and evaluation metrics (dispute rate, verifier agreement, gas, settlement latency).

### 2.5 Historical & Reference Material
* **[`PROTOCOL.md`](PROTOCOL.md)** — *Historical / Narrative Reference*
  * High-level conceptual overview of protocol v0.1 mechanics. Note: On-chain implementation details and function signatures in `CONTRACT_SPEC.md` supersede this narrative document.

---

## 3. Implementation Status Summary

### Implemented Now
* **Smart Contracts (`contracts/src/`)**: `TrustBounty.sol`, `ITrustBounty.sol`, and `TrustBountyTypes.sol` are fully implemented, verified, and frozen. All 15 external functions, 13 events, 16 custom errors, segregated liability accounting, and non-blocking pull payments are complete.
* **Test Suite (`contracts/test/`)**: 256 passing Foundry tests in `TrustBounty.t.sol` providing extensive deterministic, fuzzed, invariant, adversarial, and bounded stateful coverage.

### Planned / Phase 2
* **Acceptance Specification Module (`specification/`)**: RFC 8785 / JCS canonicalization, Schema v1.1 validation, and off-chain `specHash` generation.
* **Verifier Infrastructure (`verifier/`)**: Autonomous V1/V2 daemon services, Docker execution sandbox, evidence bundle generation, and Anvil integration harness.
