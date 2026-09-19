# TrustBounty Phase 2C-0: V1 Verifier Daemon & Blockchain Event Integration Architecture

> **Document Status**: Normative Architecture & Design Specification<br/>
> **Protocol Stage**: Phase 2C-0 (V1 Verifier Daemon, Event Poller, Spec Resolver, Tx Manager, Local Persistence)<br/>
> **Target Branch**: `feature/offchain-verifier`<br/>
> **Frozen On-Chain Baseline**: Commit `7822265` (`TrustBounty.sol` v0.1)<br/>
> **Phase 2A Baseline**: Commit `71f237a` (Hardened Git Workspace Manager)<br/>
> **Phase 2B-1 Baseline**: Commit `bc256bd` (Minimal Secure Docker Sandbox Runner)<br/>
> **Phase 2B-2 Baseline**: Commit `fc5e4d0` (Criterion Evaluation & Evidence Commitment Pipeline)

---

## 1. Purpose & Scope

This document defines the normative architecture, lifecycle transitions, state machines, persistence schemas, transaction management, error recovery, and security boundaries for **Phase 2C** of the TrustBounty Protocol: the **V1 Verifier Daemon**.

The V1 Verifier Daemon is an autonomous, single-process off-chain oracle service responsible for:
1. Monitoring the on-chain TrustBounty smart contract for bounty lifecycle events (specifically `WorkSubmitted`).
2. Treating on-chain state as the sole authoritative truth while using event logs strictly as triggers.
3. Resolving, validating, and verifying the acceptance specification preimage before initiating an on-chain commitment.
4. Broadcasting `claimVerification(bountyId)` to bind the Primary Verifier to the verification deadline.
5. Orchestrating isolated execution through the frozen Phase 2A (Git workspace) and Phase 2B-1 (Docker sandbox) subsystems.
6. Computing deterministic criteria verdicts and committing cryptographically bound evidence via Phase 2B-2.
7. Submitting `reportVerification(bountyId, outcome, evidenceHash)` via a robust, crash-resilient transaction manager.
8. Persisting all state, cursor positions, job progress, and transaction journals in a durable, local SQLite database with Write-Ahead Logging (WAL).

### 1.1 Architectural Identity: Off-Chain Oracle Boundaries
The V1 Verifier Daemon functions as an off-chain oracle bridging decentralized EVM state with bounded local computation. In strict adherence to TrustBounty design principles:
- **No Claims of Trustless Computation**: Off-chain container execution and git operations occur on physical host infrastructure; the EVM cannot natively verify physical execution truthfulness.
- **No Claims of Verifier Honesty**: `evidenceHash` serves strictly as a **tamper-evident evidence commitment** and **cryptographically bound evidence** to recorded inputs, outputs, and digests. It does **not** cryptographically prove truthful execution or verifier non-repudiation.
- **Economic & Multi-Oracle Security**: Oracle correctness is economically incentivized and enforced via maintainer dispute bonds and secondary verifier (V2) arbitration as formalized in `contracts/src/TrustBounty.sol`.
- **Bounded Reorg Handling**: The daemon implements bounded reorg detection and cursor rewinding, but explicitly disclaims universal immunity against arbitrarily deep reorganizations exceeding configured finality depths.

---

## 2. Frozen Baselines

Phase 2C integrates directly with prior frozen baselines without modifying their semantics, interfaces, or security boundaries:

```text
┌──────────────────────────────────────────────────────────────────────────────────┐
│                             FROZEN BASELINES                                     │
├──────────────────┬─────────────┬─────────────────────────────────────────────────┤
│ Layer            │ Commit      │ Frozen Invariant & Scope Boundary               │
├──────────────────┼─────────────┼─────────────────────────────────────────────────┤
│ On-Chain Protocol│ 7822265     │ 7 states, 5 outcomes, solvency invariants,       │
│                  │             │ immutables: T_claim, T_v1, T_challenge, T_v2.   │
├──────────────────┼─────────────┼─────────────────────────────────────────────────┤
│ Phase 2A         │ 71f237a     │ Detached HEAD git workspace manager, strict     │
│ (Git Workspace)  │             │ commit SHA-1 validation, path traversal defense.│
├──────────────────┼─────────────┼─────────────────────────────────────────────────┤
│ Phase 2B-1       │ bc256bd     │ UID 10001 unprivileged execution, cap-drop ALL, │
│ (Docker Sandbox) │             │ read-only rootfs, tmpfs workspace, no-network.  │
├──────────────────┼─────────────┼─────────────────────────────────────────────────┤
│ Phase 2B-2       │ fc5e4d0     │ Multi-criterion evaluator, JCS canonicalization,│
│ (Evidence Store) │             │ Keccak-256 evidenceHash, atomic bundle storage. │
└──────────────────┴─────────────┴─────────────────────────────────────────────────┘
```

---

## 3. Phase 2C Goals

1. **Autonomous Lifecycle Driving**: Enable end-to-end automated processing of bounties from `WorkSubmitted` through `VerificationReported` without human intervention.
2. **Authoritative-State Primacy**: Guarantee that no state-changing on-chain transaction or heavy sandbox execution is triggered solely by unconfirmed or stale event logs.
3. **Spec-Hash Invariant Enforcement**: Guarantee that `claimVerification` is never broadcast unless a valid specification preimage matching `onChain.specHash` is durably resolved.
4. **Crash-Resilient Nonce Management**: Implement a single-signer transaction manager with persistent journaling, startup reconciliation against RPC pending nonces, and idempotent replacement.
5. **Deterministic Failure Quarantine**: Ensure that missing specifications, malformed inputs, timeouts, OOMs, and local infrastructure crashes never falsely penalize contributors as `FAIL`.
6. **Zero External Daemon Dependencies**: Rely exclusively on standard HTTP JSON-RPC and an embedded SQLite database (`better-sqlite3`), avoiding Redis, message queues, Docker socket exposure to network, or secondary background daemons.

---

## 4. System Architecture

The daemon operates as a single Node.js runtime process organized into clean functional layers.

```text
                         Ethereum Node (HTTP JSON-RPC)
                                      ▲
                                      │ JSON-RPC Polling & Tx Broadcast
                                      ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                          V1 VERIFIER DAEMON                                    │
│                                                                                │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │                            Chain Subsystem                               │  │
│  │  ┌────────────────────────┐              ┌────────────────────────────┐  │  │
│  │  │   Block-Range Poller   │              │    Transaction Manager     │  │  │
│  │  │  (HTTP JSON-RPC logs)  │              │ (Mutex, Nonce, Journal)    │  │  │
│  │  └───────────┬────────────┘              └────────────▲───────────────┘  │  │
│  └──────────────┼────────────────────────────────────────┼──────────────────┘  │
│                 │ (Event Trigger)                        │ (claim / report)    │
│                 ▼                                        │                     │
│  ┌───────────────────────────────────────────────────────┴──────────────────┐  │
│  │                        Daemon Job Engine                                 │  │
│  │  ┌────────────────────────────────────────────────────────────────────┐  │  │
│  │  │              Local State Machine Orchestrator                      │  │  │
│  │  │  DISCOVERED ──► CLAIMING ──► CLAIMED ──► EXECUTING ──► EVIDENCED   │  │  │
│  │  │      │                                                    │        │  │  │
│  │  │      ▼                                                    ▼        │  │  │
│  │  │   ABORTED                                              REPORTING   │  │  │
│  │  │                                                           │        │  │  │
│  │  │                                                           ▼        │  │  │
│  │  │                                                    REPORT_CONFIRMED│  │  │
│  │  └─────────────────────────────────┬──────────────────────────────────┘  │  │
│  └────────────────────────────────────┼─────────────────────────────────────┘  │
│                                       │                                        │
│          ┌────────────────────────────┼───────────────────────────┐            │
│          ▼                            ▼                           ▼            │
│  ┌───────────────┐          ┌──────────────────┐        ┌───────────────────┐  │
│  │ Spec Resolver │          │  Phase 2A / 2B   │        │   SQLite Store    │  │
│  │ (Store / Git) │          │ Execution Engine │        │   (WAL Mode)      │  │
│  └───────────────┘          └──────────────────┘        └───────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Component Boundaries

Phase 2C components reside strictly within modular directories inside `verifier/src/`. No microservices or standalone network servers are introduced.

```text
verifier/src/
├── chain/                       # On-chain communication & transaction execution
│   ├── chain-client.ts          # Ethers/viem HTTP JSON-RPC wrapper & typed contract queries
│   ├── event-poller.ts          # Bounded block-range log poller with confirmation depth
│   ├── tx-manager.ts            # Global signer mutex, nonce tracking, replacement & journal
│   └── chain-types.ts           # Chain-level data structures and configuration types
│
├── daemon/                      # Daemon lifecycle & job orchestration
│   ├── daemon.ts                # Daemon bootstrap, main loop, graceful shutdown
│   ├── job-engine.ts            # Local job state machine runner and lifecycle executor
│   ├── daemon-types.ts          # Job status enums, event payloads, config interfaces
│   └── orchestrator.ts          # Glue: connects event triggers, spec resolver, 2A/2B pipeline
│
├── spec/                        # Specification resolution subsystem
│   ├── spec-resolver.ts         # Pre-claim resolution: local store + Phase 2A Git extraction
│   └── spec-types.ts            # Resolution results, candidate diagnostics, error types
│
├── store/                       # Local SQLite persistence subsystem
│   ├── schema.sql               # DDL for sync_cursor, processed_events, jobs, tx_journal
│   ├── database.ts              # better-sqlite3 connection manager with WAL initialization
│   ├── job-repository.ts        # Atomic CRUD operations for jobs and event idempotency
│   └── cursor-repository.ts     # Bounded cursor state, rewind, and reorg tracking
│
├── workspace.ts                 # FROZEN (Phase 2A Git Workspace Manager)
├── docker.ts                    # FROZEN (Phase 2B-1 Secure Docker Sandbox Runner)
├── criterion-evaluator.ts       # FROZEN (Phase 2B-2 Criterion Evaluation)
├── evidence-builder.ts          # FROZEN (Phase 2B-2 Manifest & Hash Builder)
└── evidence-store.ts            # FROZEN (Phase 2B-2 Atomic Evidence Bundle Store)
```

### 5.1 Component Responsibilities
- **`chain/`**: Pure I/O layer. Never makes policy decisions. Exposes typed methods to query `getBounty()`, poll event logs, and broadcast transactions with guaranteed nonce ordering.
- **`daemon/`**: Policy and lifecycle engine. Enforces state transitions, respects timeouts, coordinates recovery, and halts on fatal errors.
- **`spec/`**: Self-contained resolution module. Given an on-chain `specHash`, finds, validates, and hashes candidate specifications.
- **`store/`**: Data persistence layer. Wraps SQLite transactions to ensure that cursor updates, event recording, and job state transitions occur atomically.

---

## 6. Protocol-to-Daemon Lifecycle

The daemon manages the complete lifecycle of a bounty from discovery to report confirmation:

```text
On-Chain Event           V1 Daemon Action                          On-Chain State
─────────────────────────────────────────────────────────────────────────────────
WorkSubmitted(bountyId)
        │
        ▼
   [Poller Ingestion] ──► Query getBounty(bountyId)
                                 │
                                 ├─► State != SUBMITTED? ────────► IGNORE / NOOP
                                 ├─► now >= claimDeadline? ──────► ABORT (Claim Expired)
                                 │
                                 ▼
                     [Resolve Specification]
                                 │
                                 ├─► Hash Mismatch / Missing? ───► ABORT (No Claim Tx)
                                 │
                                 ▼
                     [Broadcast claimVerification()]
                                 │
                                 ▼
                     [Confirm claimVerification()] ──────────────► VERIFYING
                                 │
                                 ▼
                     [Phase 2A Workspace Preparation]
                                 │
                                 ▼
                     [Phase 2B-1 Docker Sandbox Execution]
                                 │
                                 ▼
                     [Phase 2B-2 Manifest & Evidence Store]
                                 │
                                 ▼
                     [Query getBounty(bountyId)]
                                 │
                                 ├─► State != VERIFYING? ────────► ABORT (Timeout/Interrupted)
                                 ├─► now >= verificationDeadline?► ABORT (Timeout Passed)
                                 │
                                 ▼
                     [Broadcast reportVerification()]
                                 │
                                 ▼
                     [Confirm reportVerification()] ─────────────► REPORTED / DISPUTED
```

---

## 7. Specification Resolution

### 7.1 Pre-Claim Resolution Invariant
The daemon **MUST** possess a validated specification preimage matching the on-chain `specHash` before broadcasting `claimVerification(bountyId)`.

$$\text{state} == \text{SUBMITTED} \quad \land \quad \text{now} < \text{claimDeadline} \quad \land \quad \text{hashSpecification}(\text{resolvedSpec}) == \text{onChain.specHash}$$

If this invariant cannot be satisfied:
- The daemon **must not** broadcast `claimVerification()`.
- The daemon **must not** broadcast `reportVerification()`.
- The failure **must not** be reported as contributor `FAIL`.
- The job transitions to local `ABORTED` with diagnostic reason recorded in the local store.
- The bounty remains on-chain in `SUBMITTED` until natural expiration via `expireClaim()` / `V1_TIMEOUT`.

### 7.2 Specification Sources in v0.1
The resolver inspects two sources in priority order:
1. **Local Content-Addressed Store**: `specs/<specHash>.json` (pre-cached specifications provided by the node operator or submitter).
2. **Repository-Embedded Specification**: Retrieved from the submitted Git commit via Phase 2A workspace extraction at `.trustbounty/spec.json`.

### 7.3 Resolution Semantics Matrix

| Local Store Candidate | Repository Candidate | Resolution Action | Resulting Status |
|:---|:---|:---|:---|
| Valid, matches `specHash` | *Not checked* or Valid | Accept local candidate | Proceed to Claim |
| Invalid / Mismatch / Missing | Valid, matches `specHash` | Accept repository candidate; flag local as stale | Proceed to Claim |
| Valid, matches `specHash` | Valid, matches `specHash` | Accept (cryptographically equivalent) | Proceed to Claim |
| Mismatched `specHash` | Mismatched `specHash` | Reject both; resolution fails | **`ABORTED`** |
| Missing | Missing | Resolution fails | **`ABORTED`** |
| Corrupted JSON / Schema Fail | Corrupted JSON / Schema Fail | Reject both; resolution fails | **`ABORTED`** |

### 7.4 Strict Validation Rules
Every candidate specification must:
1. Parse as valid RFC 8259 JSON without prototype pollution.
2. Pass complete Schema v1.1 validation via `specification/src/validate.ts`.
3. Compute `specHash = "0x" + keccak256(canonicalizeSpecification(spec))`.
4. Exactly equal the on-chain `bytes32 specHash` (case-insensitive hex comparison).

A file path or filename containing the hash is never trusted as evidence of correctness. Cryptographic verification of the parsed content is mandatory.

---

## 8. Event Ingestion

### 8.1 Polling Model
To eliminate WebSocket reconnection instability, dropped frames, and stateful socket complexity, Phase 2C adopts **HTTP JSON-RPC block-range polling** (`eth_getLogs`).

- **Polling Loop Interval (`pollIntervalMs`)**: Operator-configurable (default: `1000ms` for development/Anvil, `6000ms` for live testnets).
- **Block Range Cap (`maxBlockRange`)**: Operator-configurable (default: `500` blocks per query to comply with RPC provider limits).
- **Confirmation Depth (`confirmationDepth`)**:
  - Defines the number of confirmation blocks required before logs are processed.
  - Formally: $\text{toBlock} = \min(\text{latestBlock} - \text{confirmationDepth}, \text{cursorBlock} + \text{maxBlockRange})$.
  - Defaults: `0` or `1` on Anvil; operator-configured for live networks (e.g. `12` on Ethereum mainnet, `32` on L2s).
  - Confirmation depth is strictly a local deployment configuration, never a protocol-level rule.

### 8.2 Ingestion Pipeline
1. Query `eth_blockNumber`.
2. Compute safe `toBlock`. If `toBlock < fromBlock`, sleep until the next cycle.
3. Query `eth_getLogs` for contract address across topics: `[WorkSubmitted]`.
4. Sort returned logs strictly by `blockNumber ASC, transactionIndex ASC, logIndex ASC`.
5. Process each log within an atomic database transaction (see §10 & §13).
6. Verify on-chain state via `getBounty(bountyId)` before triggering job creation.

---

## 9. Reorg & Cursor Recovery

### 9.1 Bounded Reorg Detection
The daemon tracks the blockchain cursor using both block number and block hash:
- `sync_cursor.cursor_block_number`
- `sync_cursor.cursor_block_hash`

At the start of each polling cycle, before scanning forward:
1. Query `eth_getBlockByNumber(cursor_block_number, false)`.
2. Compare the returned block's `hash` with `cursor_block_hash`.
3. **If hashes match**: Chain continuity is verified; proceed to scan forward from `cursor_block_number + 1`.
4. **If hashes mismatch**: A chain reorganization has occurred.

### 9.2 Reorg Rewind & Reconciliation
Upon detecting a reorg:
1. Rewind the cursor by `REORG_REWIND_DEPTH` (default: 20 blocks):
   $$\text{rewindBlock} = \max(0, \text{cursor\_block\_number} - \text{REORG\_REWIND\_DEPTH})$$
2. Query `eth_getBlockByNumber(rewindBlock, false)` and update `sync_cursor` with the new hash.
3. Reconcile non-terminal jobs:
   - Identify all jobs created or transitioned from blocks $> \text{rewindBlock}$.
   - Query authoritative contract state `getBounty(bountyId)` for each affected job.
   - If the bounty on-chain is no longer in the expected state, reconcile the local job state accordingly (e.g. revert `CLAIMING` to `DISCOVERED` if the claim tx was reorged out).
4. Re-scan the block range. Event deduplication (§10) ensures that re-scanned logs that were already confirmed and processed are cleanly skipped.

> [!WARNING]
> **Bounded Reorg Limitation**
> This mechanism provides robust recovery against shallow reorgs ($< \text{REORG\_REWIND\_DEPTH}$). It explicitly does not guarantee recovery from catastrophic deep reorganizations exceeding configured finality depths or long-range consensus forks. In such cases, operator intervention is required.

---

## 10. Idempotency

### 10.1 Event Identity
Every blockchain event log is identified by a composite primary key:

$$\text{idempotency\_key} = \text{keccak256}(\text{chainId} \parallel \text{contractAddress} \parallel \text{transactionHash} \parallel \text{logIndex})$$

### 10.2 Idempotency Rules
1. **No Duplicate Jobs**: If an event log with an existing `idempotency_key` is received during re-polling or reorg replay, it is silently acknowledged and discarded.
2. **No Duplicate Claims**: If a job for `bountyId` is already in state `CLAIMING`, `CLAIMED`, `EXECUTING`, `EVIDENCED`, or `REPORTING`, incoming `WorkSubmitted` events for the same `bountyId` are rejected.
3. **No Duplicate Reports**: Once a job has generated an `evidenceHash`, the local state machine permits exactly one broadcast of `reportVerification()`.

---

## 11. Local Job State Machine

The daemon tracks each verification task through a closed, deterministic local state machine.

```text
                              ┌──────────────┐
                              │  DISCOVERED  │
                              └──────┬───────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │ (Valid Spec & On-Chain SUBMITTED)│ (Missing Spec / Expired / Invalid)
                    ▼                                 ▼
             ┌──────────────┐                  ┌─────────────┐
             │   CLAIMING   │                  │   ABORTED   │ (Terminal)
             └──────┬───────┘                  └─────────────┘
                    │
           ┌────────┴────────┐
           │ (Tx Confirmed)  │ (Revert / Lost Race / Timeout)
           ▼                 ▼
    ┌──────────────┐   ┌──────────────┐
    │   CLAIMED    │   │ CLAIM_FAILED │ (Terminal)
    └──────┬───────┘   └──────────────┘
           │
           ▼
    ┌──────────────┐
    │  EXECUTING   │ ◄─── Phase 2A (Git) + Phase 2B-1 (Docker)
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │  EVIDENCED   │ ◄─── Phase 2B-2 Manifest + atomic bundle commit
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │  REPORTING   │ ◄─── Phase 2C TxManager broadcast
    └──────┬───────┘
           │
           ▼
 ┌───────────────────┐
 │ REPORT_CONFIRMED  │ (Terminal for V1 Daemon)
 └───────────────────┘
```

### 11.1 State Definitions & Invariants

| State | Description | Authoritative Precondition | Allowed Transitions |
|:---|:---|:---|:---|
| **`DISCOVERED`** | `WorkSubmitted` log ingested. Spec resolution in progress. | On-chain state == `SUBMITTED`. | `CLAIMING`, `ABORTED` |
| **`CLAIMING`** | `claimVerification` transaction broadcast; awaiting receipt. | Spec valid; `now < claimDeadline`. | `CLAIMED`, `CLAIM_FAILED`, `ABORTED` |
| **`CLAIMED`** | Claim tx confirmed on-chain. | On-chain state == `VERIFYING`. | `EXECUTING`, `ABORTED` |
| **`EXECUTING`** | Git clone/checkout + Docker sandbox execution running. | `now < verificationDeadline`. | `EVIDENCED`, `ABORTED` |
| **`EVIDENCED`** | Verdict mapped; manifest created; bundle committed to disk. | Valid `evidenceHash` generated. | `REPORTING`, `ABORTED` |
| **`REPORTING`** | `reportVerification` transaction broadcast; awaiting receipt. | `now < verificationDeadline`. | `REPORT_CONFIRMED`, `ABORTED` |
| **`REPORT_CONFIRMED`** | Report tx confirmed on-chain. Verification complete. | On-chain state == `REPORTED` or `DISPUTED`. | *None (Terminal)* |
| **`CLAIM_FAILED`** | Claim tx reverted (e.g. lost race or deadline elapsed). | On-chain state != `VERIFYING`. | *None (Terminal)* |
| **`ABORTED`** | Unrecoverable precondition failure, missing spec, or timeout. | Terminal failure recorded locally. | *None (Terminal)* |

### 11.2 Scope Clarification for `REPORT_CONFIRMED`
`REPORT_CONFIRMED` indicates that the V1 Verifier Daemon has successfully executed its role and confirmed its verification report on-chain. It **DOES NOT** imply that the bounty is finalized or settled. The bounty protocol enters the challenge window (`REPORTED`) or dispute arbitration (`DISPUTED`) per on-chain rules.

---

## 12. Transaction & Nonce Management

### 12.1 Single-Signer Invariant
The daemon operates strictly with **one PRIMARY_VERIFIER Ethereum address**. While multiple verification jobs may theoretically be monitored, all transaction allocations are globally serialized across the signer.

### 12.2 Transaction Mutex & Pipeline
To prevent nonce gaps, race conditions, and out-of-order execution:
1. **Global Transaction Mutex**: Exactly one transaction broadcast and confirmation pipeline is active at any time (`maxConcurrentTx = 1`).
2. **Local Nonce Tracking with RPC Grounding**:
   - The daemon tracks an internal `nextNonce`.
   - On daemon startup or recovery, the authoritative starting nonce is initialized directly from:
     $$\text{startingNonce} = \text{eth\_getTransactionCount}(\text{signerAddress}, \text{"pending"})$$
   - Local database records transaction intent, but RPC pending nonce remains the ultimate reality check.
3. **Transaction Journaling**:
   - Before broadcasting any transaction, intent is written to SQLite `tx_journal` with status `PENDING`.
   - Upon receiving a confirmed receipt, status updates to `CONFIRMED`.
   - If a transaction reverts, status updates to `REVERTED`. Reverted transactions are **never blindly retried** without querying contract state.
4. **Gas Pricing & Replacement**:
   - Transactions query `eth_feeHistory` / `eth_gasPrice` dynamically.
   - If a transaction remains unmined after `TX_CONFIRMATION_TIMEOUT_MS` (default: 60s), the transaction manager queries `eth_getTransactionReceipt`.
   - If unconfirmed, the manager broadcasts a replacement transaction using the **exact same nonce** with an operator-configured gas price bump (`maxFeePerGas` and `maxPriorityFeePerGas`):
     - `replacementGasBumpPercent`: operator-configured
     - `default: 20%`
   - Transaction replacement gas bumping is strictly an operator/deployment configuration, NOT a TrustBounty protocol invariant.

---

## 13. Persistence Model

The daemon uses a single, embedded, robust storage engine: **`better-sqlite3`** operating in **WAL mode** (`PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;`).

### 13.1 Normative DDL Schema

```sql
-- 1. Blockchain Synchronization Cursor
CREATE TABLE IF NOT EXISTS sync_cursor (
    chain_id             INTEGER NOT NULL,
    contract_address     TEXT NOT NULL,
    cursor_block_number  INTEGER NOT NULL,
    cursor_block_hash    TEXT NOT NULL,
    updated_at           TEXT NOT NULL,
    PRIMARY KEY (chain_id, contract_address)
);

-- 2. Ingested Event Idempotency Registry
CREATE TABLE IF NOT EXISTS processed_events (
    idempotency_key      TEXT PRIMARY KEY,
    chain_id             INTEGER NOT NULL,
    contract_address     TEXT NOT NULL,
    bounty_id            TEXT NOT NULL,
    event_name           TEXT NOT NULL,
    block_number         INTEGER NOT NULL,
    tx_hash              TEXT NOT NULL,
    log_index            INTEGER NOT NULL,
    created_at           TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_processed_events_bounty
ON processed_events (bounty_id);

-- 3. Verification Jobs
CREATE TABLE IF NOT EXISTS jobs (
    bounty_id            TEXT PRIMARY KEY,
    commit_hash          TEXT NOT NULL,
    spec_hash            TEXT NOT NULL,
    status               TEXT NOT NULL, -- DISCOVERED, CLAIMING, CLAIMED, EXECUTING, EVIDENCED, REPORTING, REPORT_CONFIRMED, CLAIM_FAILED, ABORTED
    claim_tx_hash        TEXT,
    report_tx_hash       TEXT,
    outcome              TEXT,          -- PASS, FAIL, ERROR, INCONCLUSIVE (Stored as semantic strings, NOT Solidity enum integers)
    evidence_hash        TEXT,
    evidence_bundle_path TEXT,
    failure_reason       TEXT,
    event_block_number   INTEGER NOT NULL,
    event_block_hash     TEXT NOT NULL,
    created_at           TEXT NOT NULL,
    updated_at           TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_jobs_status
ON jobs (status);

-- 4. Transaction Manager Journal
CREATE TABLE IF NOT EXISTS tx_journal (
    tx_hash              TEXT PRIMARY KEY,
    nonce                INTEGER NOT NULL,
    to_address           TEXT NOT NULL,
    data                 TEXT NOT NULL,
    gas_limit            TEXT NOT NULL,
    max_fee_per_gas      TEXT,
    max_priority_fee     TEXT,
    bounty_id            TEXT NOT NULL,
    tx_type              TEXT NOT NULL, -- CLAIM, REPORT
    status               TEXT NOT NULL, -- PENDING, CONFIRMED, REVERTED, REPLACED
    broadcast_at         TEXT NOT NULL,
    confirmed_at         TEXT,
    receipt_block_number INTEGER,
    revert_reason        TEXT
);

CREATE INDEX IF NOT EXISTS idx_tx_journal_nonce
ON tx_journal (nonce);
```

### 13.2 Atomicity Invariant
Log ingestion and cursor advancement are executed within a single atomic SQLite transaction:
```typescript
db.transaction(() => {
  insertProcessedEvent.run(event);
  createOrUpdateJob.run(job);
  updateSyncCursor.run(cursor);
})();
```
This guarantees the crash rule: **At-least-once delivery with idempotent processing**. It is impossible for the cursor to advance while failing to durably persist the event or job.

---

## 14. Failure Semantics

To uphold protocol integrity and protect bounty participants, all failure modes are mapped to explicit, deterministic behaviors:

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                               FAILURE SEMANTICS MATRIX                                 │
├──────────────────────────┬─────────────────────────────┬───────────────────────────────┤
│ Failure Point            │ Local Daemon Action         │ Protocol / Settlement Effect  │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ Spec missing / unresolv. │ ABORT job. Do NOT claim.    │ No claim. Expires on-chain    │
│ Spec hash mismatch       │ ABORT job. Do NOT claim.    │ via natural claim timeout.    │
│ Spec JSON malformed      │ ABORT job. Do NOT claim.    │ Contributor NEVER penalized.  │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ Claim deadline passed    │ ABORT job. Do NOT claim.    │ Claim timeout escalates to V2.│
│ Claim tx reverted        │ Set status CLAIM_FAILED.    │ Handled by on-chain lifecycle.│
│ Lost claim race          │ Set status CLAIM_FAILED.    │ Another verifier claimed.     │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ Git clone/checkout fail  │ Record ERROR outcome.       │ Phase 2B-2 error manifest.    │
│ Container Timeout / OOM  │ Record ERROR outcome.       │ Auto-escalates to DISPUTED.   │
│ Docker daemon crash      │ Record ERROR outcome.       │ Contributor NEVER gets FAIL.  │
│ Evidence commit fail     │ Record ERROR outcome.       │ Evidence failure = ERROR.     │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ Verification deadline hit│ Halt execution. ABORT job.  │ On-chain timeoutV1() callable.│
│ Report tx reverted       │ Re-query getBounty().       │ If already reported/disputed, │
│                          │ Do not blindly retry.       │ mark terminal. No loops.      │
└──────────────────────────┴─────────────────────────────┴───────────────────────────────┘
```

---

## 15. Crash Recovery

Upon restart after an ungraceful shutdown, power loss, or host crash, the daemon executes a deterministic recovery sequence before resuming normal operation:

```text
[Daemon Startup]
       │
       ▼
1. Initialize SQLite Database (Pragmas: WAL mode, synchronous=NORMAL)
       │
       ▼
2. Query RPC for Nonce: eth_getTransactionCount(PRIMARY_VERIFIER, "pending")
       │
       ▼
3. Reconcile Transaction Journal:
   - For all PENDING transactions in tx_journal:
     - Query eth_getTransactionReceipt(tx_hash)
     - If confirmed: update tx_journal -> CONFIRMED, reconcile associated job
     - If not found & nonce < rpcPendingNonce: update tx_journal -> REPLACED
       │
       ▼
4. Reconcile In-Flight Jobs:
   - For each non-terminal job (CLAIMING, CLAIMED, EXECUTING, EVIDENCED, REPORTING):
     - Query authoritative on-chain state getBounty(bountyId)
     - If state == SUBMITTED:
       - If local was CLAIMING: check if tx pending; if dead, reset to DISCOVERED
     - If state == VERIFYING:
       - If now >= verificationDeadline: transition to ABORTED (timeout expired)
       - If local was EXECUTING: clean stale workspace/containers; resume execution
       - If local was EVIDENCED: resume broadcast to REPORTING
     - If state == REPORTED or DISPUTED:
       - Local report already landed on-chain; transition to REPORT_CONFIRMED
     - If state == SETTLED or REFUNDED:
       - Bounty terminated elsewhere; transition to ABORTED
       │
       ▼
5. Clean Stale Containers:
   - Invoke reconcileStaleContainers() to purge orphan TrustBounty containers
       │
       ▼
6. Verify Cursor Hash against Chain & Start Polling Loop
```

---

## 16. Concurrency

Phase 2C defines strict, conservative concurrency boundaries for v0.1:

```typescript
export const DAEMON_CONCURRENCY_DEFAULTS = {
  /** Maximum number of verification jobs processed concurrently */
  maxConcurrentJobs: 1,
  /** Maximum number of active transaction broadcast pipelines */
  maxConcurrentTx: 1,
  /** SQLite connection pool */
  maxDatabaseConnections: 1, // better-sqlite3 is single-process synchronous
} as const;
```

### Rationale for `maxConcurrentJobs = 1` in v0.1:
1. **Simplified Crash Recovery**: Eliminates race conditions during multi-job restart and pending nonce reconciliation.
2. **Deterministic Host Resource Allocation**: Prevents two simultaneous Docker sandbox instances from competing for CPU, I/O bandwidth, and memory caps, avoiding synthetic OOM/timeout errors.
3. **Signer Mutex Alignment**: With a single PRIMARY_VERIFIER key, jobs cannot broadcast transactions concurrently without serializing.
4. **Upgrade Path**: Modular job queue architecture allows increasing `maxConcurrentJobs` in future releases without modifying protocol contracts or specification formats.

---

## 17. Security Boundaries

Phase 2C operates across four distinct trust and security boundaries:

```text
       ┌─────────────────────────────────────────────────────────┐
       │                   UNTRUSTED REPOSITORY                  │
       │  • Malicious code in repo    • Fork bombs / crypto miners│
       │  • Traversal commits         • Toxic node_modules        │
       └────────────────────────────┬────────────────────────────┘
                                    │
    BOUNDARY 1: Phase 2A Isolation  ▼ (Strict commit match, detached HEAD, no hooks)
       ┌─────────────────────────────────────────────────────────┐
       │                 ISOLATED GIT WORKSPACE                  │
       └────────────────────────────┬────────────────────────────┘
                                    │
    BOUNDARY 2: Phase 2B-1 Sandbox  ▼ (UID 10001, read-only rootfs, tmpfs, net=none)
       ┌─────────────────────────────────────────────────────────┐
       │                SECURE DOCKER CONTAINER                  │
       └────────────────────────────┬────────────────────────────┘
                                    │
    BOUNDARY 3: Phase 2B-2 Evidence ▼ (JCS canonicalization, Keccak-256 evidenceHash)
       ┌─────────────────────────────────────────────────────────┐
       │                DETERMINISTIC EVIDENCE                   │
       └────────────────────────────┬────────────────────────────┘
                                    │
    BOUNDARY 4: Phase 2C Oracle     ▼ (On-chain state primacy, nonce mutex, WAL store)
       ┌─────────────────────────────────────────────────────────┐
       │                 TRUSTBOUNTY SMART CONTRACT              │
       └─────────────────────────────────────────────────────────┘
```

1. **Host Isolation**: All contributor commands execute strictly within Phase 2B-1 containers (`--network none`, `--cap-drop ALL`, read-only rootfs, unprivileged user `10001:10001`). The host daemon never invokes `/bin/sh` on contributor code.
2. **Specification Preimage Gate**: The daemon never executes a container or broadcasts a claim transaction without verifying `hashSpecification(spec) == onChain.specHash`.
3. **Private Key Protection**: The PRIMARY_VERIFIER private key is loaded from local environment variables / keystore and never logged, emitted in error traces, or exposed to containers.
4. **Path Traversal Defense**: All artifact paths, bundle locations, and spec file paths are strictly validated against `/^[A-Za-z0-9_-]{1,64}$/` and asserted within their base directories.

---

## 18. Testing Strategy

Phase 2C verification requires a multi-tier test pyramid:

### 18.1 Unit Tests
- **`event-poller.test.ts`**: Bounded range computation, mock log sequencing, confirmation depth filtering.
- **`spec-resolver.test.ts`**: Pre-claim hash matching, malformed JSON rejection, missing file fallback, resolution failure paths.
- **`tx-manager.test.ts`**: Mutex locking, nonce tracking, receipt confirmation, replacement transaction gas bumping, revert handling.
- **`job-repository.test.ts`**: SQLite schema migrations, idempotent event insertion, job state transitions, crash-safe WAL commits.

### 18.2 Integration Tests (Mock RPC)
- **`daemon-lifecycle.test.ts`**: Full simulation of `SUBMITTED` $\to$ `CLAIMING` $\to$ `CLAIMED` $\to$ `EXECUTING` $\to$ `EVIDENCED` $\to$ `REPORT_CONFIRMED` using a mock JSON-RPC server.
- **`reorg-recovery.test.ts`**: Simulation of cursor hash mismatch, rewind by `REORG_REWIND_DEPTH`, and idempotent log replay.
- **`crash-restart.test.ts`**: Hard termination of process midway through execution; restart asserting correct resumption from SQLite state.

### 18.3 End-to-End Tests (Local Anvil)
- **`e2e-daemon.test.ts`**:
  - Deploy `TrustBounty.sol` on local Anvil testnet.
  - Fund Maintainer, Contributor, and Primary Verifier accounts.
  - Maintainer creates bounty (`createBounty`).
  - Contributor submits work (`submitWork`).
  - V1 Daemon automatically discovers event, resolves spec, claims verification on-chain, executes tests in real Docker container, commits evidence bundle, and reports `PASS` on-chain.
  - Maintainer finalizes bounty after challenge period; escrow is released to contributor.

---

## 19. Phase 2C Decomposition

Implementation of Phase 2C is partitioned into five focused, sequential sub-phases:

```text
Phase 2C-0: Architecture & Design Freeze (THIS DOCUMENT)
     │
     ▼
Phase 2C-1: Chain Client, Event Poller & Transaction Manager
     │       • verifier/src/chain/chain-client.ts
     │       • verifier/src/chain/event-poller.ts
     │       • verifier/src/chain/tx-manager.ts
     ▼
Phase 2C-2: SQLite Persistence & Local Job State Machine
     │       • verifier/src/store/schema.sql
     │       • verifier/src/store/database.ts
     │       • verifier/src/store/job-repository.ts
     │       • verifier/src/store/cursor-repository.ts
     ▼
Phase 2C-3: Specification Resolver & 2A/2B Pipeline Orchestrator
     │       • verifier/src/spec/spec-resolver.ts
     │       • verifier/src/daemon/orchestrator.ts
     ▼
Phase 2C-4: V1 Daemon Main Loop & Lifecycle Automation
     │       • verifier/src/daemon/daemon.ts
     │       • verifier/src/daemon/job-engine.ts
     ▼
Phase 2C-5: End-to-End Anvil Integration & Full Lifecycle Testing
             • verifier/test/chain/
             • verifier/test/daemon/
             • verifier/test/e2e/
```

---

## 20. Non-Goals

To maintain strict research boundaries and avoid scope creep, the following are explicitly non-goals for Phase 2C:

1. **No zkVM / Zero-Knowledge Proofs**: Verification relies on optimistic economic games and tamper-evident evidence manifests, not cryptographic zk-SNARK / zk-STARK execution proofs.
2. **No Trusted Execution Environments (TEEs)**: SGX, Nitro Enclaves, and TDX hardware attestations are out of scope.
3. **No Secondary Verifier (V2) Daemon in Phase 2C**: V2 dispute arbitration logic is deferred to a future phase; Phase 2C implements strictly the V1 Primary Verifier.
4. **No New Blockchain or Layer 1/2 Consensus**: TrustBounty operates exclusively as a smart contract protocol deployed on EVM-compatible networks.
5. **No Token or DAO Governance**: Bounty pricing, escrow, and dispute bonds use native currency (ETH).
6. **No AI Correctness Oracles**: Evaluation is deterministic code execution based strictly on pre-committed shell commands.
7. **No Decentralized Storage Integration**: IPFS / Arweave storage of evidence bundles is deferred; Phase 2C uses local content-addressed bundle stores.
8. **No WebSockets Requirement**: Polling is based entirely on HTTP JSON-RPC.

---

## 21. Freeze Checklist

Before any Phase 2C-1 implementation code is written, this checklist confirms protocol immutability and architectural compliance:

- [x] **On-Chain Protocol Frozen**: `TrustBounty.sol` v0.1 at commit `7822265` remains immutable. Zero Solidity contract modifications permitted.
- [x] **Phase 2A Baseline Frozen**: Git workspace manager at commit `71f237a` remains immutable.
- [x] **Phase 2B-1 Baseline Frozen**: Docker sandbox runner at commit `bc256bd` remains immutable.
- [x] **Phase 2B-2 Baseline Frozen**: Criteria evaluation and evidence commitment pipeline at commit `fc5e4d0` remains immutable.
- [x] **Specification Schema Frozen**: Schema v1.1 in `specification/` remains immutable.
- [x] **Pre-Claim Spec Invariant Formalized**: Daemon requires valid spec preimage matching `onChain.specHash` prior to broadcasting `claimVerification()`. Pre-claim failures become local `ABORTED` with zero on-chain penalty to contributors.
- [x] **Authoritative-State Rule Frozen**: On-chain state is the sole authority; events serve strictly as triggers.
- [x] **Single-Signer Mutex & WAL Storage Frozen**: Global transaction serialization with `better-sqlite3` WAL persistence.
- [x] **Phase 2C-0 Architecture Frozen**: Complete design documented in `docs/PHASE2C_ARCHITECTURE.md`.
- [x] **Implementation Deferred**: Zero production or test code modified in this phase.
