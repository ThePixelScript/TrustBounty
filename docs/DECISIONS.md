# TrustBounty Architectural Decision Records (ADRs)

This document records the architectural and protocol design decisions for TrustBounty Protocol v0.1.

---

## ADR-001: 7-State Directed Acyclic Graph (DAG) State Machine

* **Status**: Accepted
* **Context**: Earlier bounty protocols employed retry loops (allowing multiple submission attempts or re-claims) with `MAX_ATTEMPTS` counters. This introduced unbounded latency, complex state-tracking, and edge cases where funds could remain locked during verifier deadlock.
* **Decision**: Adopt a strict 7-state DAG (`ACTIVE`, `SUBMITTED`, `VERIFYING`, `REPORTED`, `DISPUTED`, `SETTLED`, `REFUNDED`) without retry cycles. `SETTLED` and `REFUNDED` are strictly terminal sinks.
* **Alternatives Considered**: Multi-attempt state machines with retry transitions back to `SUBMITTED` or `ACTIVE`.
* **Consequences**: Enforces monotonic forward progression; every non-terminal state has a finite, permissionlessly executable progression or recovery mechanism.

---

## ADR-002: Native ETH Escrow Asset Only

* **Status**: Accepted
* **Context**: Supporting ERC-20 tokens introduces token-standard quirks (fee-on-transfer, rebasing, ERC-777 hooks, blocklists, decimal normalization).
* **Decision**: Protocol v0.1 exclusively accepts and settles in native ETH. No ERC-20, ERC-721, or ERC-1155 tokens are supported.
* **Alternatives Considered**: Multi-token escrow with ERC-20 whitelist.
* **Consequences**: Eliminates token-specific reentrancy/approval attack vectors; simplifies liability accounting. Multi-token support is deferred to v0.2.

---

## ADR-003: Single Contributor Binding per Bounty

* **Status**: Accepted
* **Context**: Multi-contributor competitive bounties require complex on-chain queue management, fractional payouts, or off-chain race-condition arbitration.
* **Decision**: Protocol v0.1 binds exactly one contributor and one Git commit SHA-1 per bounty upon `submitWork()`.
* **Alternatives Considered**: Multi-submission queues, split 50/50 dispute divisions, or continuous streaming.
* **Consequences**: Greatly simplifies the state machine and dispute logic. Concurrent multi-contributor workflows are deferred to post-v0.1.

---

## ADR-004: Deployment-Immutable Verifier Identities

* **Status**: Accepted
* **Context**: Allowing maintainers to configure arbitrary verifier addresses per bounty introduces severe Sybil and collusion vulnerabilities (a maintainer could choose their own second address as verifier).
* **Decision**: `PRIMARY_VERIFIER` and `SECONDARY_VERIFIER` are immutable variables initialized once during contract deployment (`PRIMARY_VERIFIER != SECONDARY_VERIFIER`). Maintainers cannot override verifiers for individual bounties.
* **Alternatives Considered**: Per-bounty maintainer verifier selection; dynamic on-chain verifier registry.
* **Consequences**: Mitigates maintainer Sybil attacks. Centralized oracle trust is transparent and fixed at the protocol level.

---

## ADR-005: Elimination of Staking, Slashing, and Governance in v0.1

* **Status**: Accepted
* **Context**: Verifier staking/slashing and DAO governance add massive smart contract complexity, oracle dependencies, and administrative attack surfaces.
* **Decision**: v0.1 contains zero governance keys, admin roles, verifier staking pools, or slashing mechanics.
* **Alternatives Considered**: DAO-governed verifier registry with token staking.
* **Consequences**: Minimizes attack surface and gas overhead; keeps the contract monolithic, non-upgradeable, and auditable.

---

## ADR-006: RFC 8785 JCS Canonicalization + Keccak-256 Specification Commitment

* **Status**: Accepted
* **Context**: JSON serialization can produce different byte representations for identical data due to whitespace, key ordering, and number formatting.
* **Decision**: Use RFC 8785 (JSON Canonicalization Scheme) to serialize specifications into a deterministic byte array, then compute `specHash = Keccak-256(RFC8785(spec))` for the on-chain commitment.
* **Alternatives Considered**: Plain JSON string hashing; CBOR serialization; Solidity ABI encoding.
* **Consequences**: Enables language-agnostic, deterministic hashing across off-chain tools and smart contracts.

---

## ADR-007: Opaque `bytes20` Git SHA-1 Commit Identifier

* **Status**: Accepted
* **Context**: Git commit hashes in widespread use are 20-byte SHA-1 digests.
* **Decision**: `commitHash` is stored as an opaque `bytes20` field in `Bounty` storage. The contract does not compute or inspect Git hashes.
* **Alternatives Considered**: `bytes32` Git SHA-256 or string commit hashes.
* **Consequences**: Optimal storage efficiency (fits in a single 32-byte storage slot alongside state/outcomes). Git SHA-256 object formats deferred to v0.2.

---

## ADR-008: Pinned Container Digest Environment Specification

* **Status**: Accepted
* **Context**: Container tags (e.g. `node:latest`) are mutable and cause execution non-determinism as underlying images update over time.
* **Decision**: Require container images to be pinned strictly by cryptographic SHA-256 digest (`<image-reference>@sha256:<64-hex>`).
* **Alternatives Considered**: Tag-based references; VM image snapshots.
* **Consequences**: Controls image and environment drift by binding image filesystem contents; however, host kernel, hardware architecture, CPU scheduling, network access, and external runtime dependencies can still affect execution across hosts.

---

## ADR-009: Bounded Verification Criteria MVP (`BUILD`, `TEST`, `COVERAGE`)

* **Status**: Accepted
* **Context**: Overly complex verification schemas increase verifier failure rates and parser bugs.
* **Decision**: Limit v0.1 criteria strictly to three core types: `BUILD` (command + exit code 0), `TEST` (command + exit code 0), and `COVERAGE` (`>=` threshold in basis points).
* **Alternatives Considered**: Custom script hooks, linting rules, and multi-stage pipelines.
* **Consequences**: Clean, unambiguous verification contract with high automated test coverage.

---

## ADR-010: Protocol-Bounded Challenge Bond ($B_{chal} = \min(\text{reward}, \text{MAX\_BOND\_CAP})$)

* **Status**: Accepted
* **Context**: Allowing maintainers to set arbitrary challenge bonds creates griefing vectors (e.g. setting an astronomical bond to prevent contributors from challenging false rejections).
* **Decision**: The challenge bond is computed automatically on-chain as $B_{chal} = \min(\text{reward}, \text{MAX\_BOND\_CAP})$, where `MAX_BOND_CAP` is an immutable deployment parameter.
* **Alternatives Considered**: Fixed percentage of reward (e.g., 20%); maintainer-configured bond.
* **Consequences**: Guarantees fair, predictable challenge costs and caps risk on high-value bounties.

---

## ADR-011: Non-Blocking Pull-Payment Settlement Architecture

* **Status**: Accepted
* **Context**: Executing direct external ETH transfers (`.call`, `transfer`) during bounty terminalization exposes the protocol to denial-of-service (DOS) if the recipient contract reverts on ETH receipt or runs out of gas.
* **Decision**: Terminal transitions (`cancelBounty`, `expireBounty`, `finalizeReport`, `reportV2`, `finalizeV2Timeout`) strictly extinguish internal bounty liabilities and credit `withdrawableBalance[recipient]` without performing external calls.
* **Alternatives Considered**: Push payments with gas limits or fallback balances.
* **Consequences**: Prevents unpayable recipient contracts from blocking terminal state transitions, as state resolution executes without external calls.

---

## ADR-012: Dual Withdrawal Interfaces (`withdraw()` and `withdrawTo(destination)`)

* **Status**: Accepted
* **Context**: Smart contracts that lack `receive()` or `fallback()` handlers cannot directly withdraw ETH, which would trap their funds even under a pull-payment model.
* **Decision**: Expose `withdraw()` (transfers credit to `msg.sender`) AND `withdrawTo(address payable destination)` (allows `msg.sender` to route their own credit to a designated payout address).
* **Alternatives Considered**: Only `withdraw()`; delegated allowances.
* **Consequences**: Seamless integration for both standard EOAs and unpayable smart contracts without adding delegated transfer complexity.

---

## ADR-013: Strictly Non-Upgradeable Monolithic Contract Architecture

* **Status**: Accepted
* **Context**: Upgradeable proxies introduce storage layout collision risks, centralized admin keys, and trust compromises.
* **Decision**: Deploy TrustBounty as an immutable, monolithic contract without proxies (UUPS, Transparent, Beacon) or admin keys.
* **Alternatives Considered**: UUPS upgradeable proxy.
* **Consequences**: Guarantees trust minimization and permanent bytecode immutability.

---

## ADR-014: Dispute Deadline Initialization at Transition Timestamp

* **Status**: Accepted
* **Context**: If `disputeDeadline` were retroactively anchored to earlier submission/report timestamps, timeouts during automatic recovery would immediately expire V2's execution window before V2 could act.
* **Decision**: Across all transition paths into `DISPUTED` (challenges, V1 timeout, claim timeout, V1 error), `disputeDeadline` is set strictly to `block.timestamp + T_v2` at the moment of the transition.
* **Alternatives Considered**: Anchoring V2 deadline to the original submission timestamp.
* **Consequences**: Gives secondary verifier V2 a consistent, full operational window `T_v2` to resolve disputes.

---

## ADR-015: Internal Storage Visibility for `bounties` Mapping

* **Status**: Accepted
* **Context**: The `Bounty` struct contains 18 fields. In Solidity 0.8.37 (legacy codegen without `--via-ir`), declaring `mapping(uint256 => Bounty) public bounties;` directs Solc to generate an external getter returning an 18-element tuple on the stack, triggering an unrecoverable `Stack too deep` compiler error.
* **Decision**: Keep storage visibility internal (`mapping(uint256 => Bounty) internal bounties;`) and expose the canonical getter `function getBounty(uint256 bountyId) external view returns (Bounty memory)`.
* **Alternatives Considered**: Enabling `--via-ir` (which changes deployment bytecode characteristics and compiler pipeline).
* **Consequences**: Standard, reliable compilation under default legacy Solc 0.8.37 while providing identical external access via `getBounty()`.
