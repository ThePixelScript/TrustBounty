# TrustBounty Phase 2B-2: Criterion Evaluation + Evidence Commitment Design

> **Document Status**: Normative Design Specification
> **Target Branch**: `feature/offchain-verifier`
> **Protocol Stage**: Phase 2B-2 (Evaluators, Evidence Bundle Architecture, Canonical Evidence Manifest, `evidenceHash`)
> **Frozen On-Chain Baseline**: Commit `7822265` (`TrustBounty.sol` v0.1)
> **Phase 2A Baseline**: Commit `71f237a` (Hardened Git Workspace Manager)
> **Phase 2B-1 Baseline**: Commit `bc256bd` (Minimal Secure Docker Sandbox Runner)

---

## 1. Purpose & Scope

This document specifies the normative architecture, execution model, evaluation semantics, evidence collection, canonicalization, and cryptographic commitment algorithms for **Phase 2B-2** of the TrustBounty Protocol.

### 1.1 Core Objective
Phase 2B-2 bridges the gap between raw container execution and on-chain protocol settlement. It formalizes the deterministic transition pipeline:

```text
Acceptance Specification (v1.1)
           │
           ▼
[Sequential Criterion Execution]  <── Phase 2B-1 executeInSandbox()
           │
           ▼
[Criterion Verdict Mapping]       <── Bounded ExecutionResult -> PASS / FAIL / ERROR
           │
           ▼
[Multi-Criterion Aggregation]     <── ERROR > INCONCLUSIVE > FAIL > PASS
           │
           ▼
[Retained Artifact Hashing]       <── Keccak-256(retained stdout/stderr bytes)
           │
           ▼
[Canonical Manifest Construction] <── Bound spec, commits, criteria, verdicts, digests
           │
           ▼
[RFC 8785 (JCS) + Keccak-256]     <── Deterministic 0x-prefixed 32-byte evidenceHash
           │
           ▼
[Atomic Evidence Bundle Storage]  <── Staged write to evidence_bundles/<evidenceHash>/
```

### 1.2 Cryptographic Role of evidenceHash: Integrity Commitment vs. Execution Truthfulness
Phase 2B-2 maintains an explicit, normative distinction regarding the cryptographic role of `evidenceHash`:

> [!IMPORTANT]
> **Integrity Commitment vs. Proof of Truthful Execution**
> - `evidenceHash` provides **cryptographically bound evidence** and a **tamper-evident evidence commitment** to the exact inputs, executed commands, exit codes, and output byte digests recorded by the verifier.
> - `evidenceHash` **DOES NOT** provide cryptographic non-repudiation or prove verifier honesty.
> - Formally:
>   $$\text{evidenceHash} = \text{integrity commitment to recorded evidence}$$
>   $$\text{evidenceHash} \ne \text{proof of truthful execution}$$
>
> An off-chain verifier could theoretically record fabricated logs or simulated exit codes without honestly executing Docker. The EVM contract receives and stores an opaque `bytes32 evidenceHash` and cannot determine whether physical container execution actually occurred.
>
> Trust minimization and oracle honesty in TrustBounty are enforced **economically and structurally**, not cryptographically:
> 1. **Symmetric Economic Collateral**: Bonded maintainer escrow and contributor dispute bonds make frivolous or dishonest claims economically punitive.
> 2. **Dual-Oracle Redundancy (V1 vs. V2)**: If V1 commits a fraudulent or disputed `evidenceHash`, the protocol escalates to an independent secondary verifier (V2) for arbitration.
> 3. **Tamper-Evident Forensic Auditing**: If V1 equivocates or produces an invalid manifest, the `evidenceHash` committed on-chain provides immutable forensic proof of oracle fraud during dispute arbitration.

### 1.3 Strict Non-Goals for Phase 2B-2
- **No Specification Schema Alteration**: Consumes Schema v1.1 as frozen in `specification/src/types.ts`.
- **No On-Chain Contract Modifications**: Protocol smart contract `contracts/src/TrustBounty.sol` is frozen at `7822265`.
- **No Decentralized Storage Networks**: IPFS, Arweave, Filecoin, and Swarm integrations are deferred.
- **No On-Chain Evidence Parsing**: The EVM contract receives and stores an opaque `bytes32 evidenceHash`.
- **No Daemon Loops or Ethereum RPC**: Autonomous polling, transaction signing, and event listeners are deferred to Phase 2C.
- **No Host-Side Untrusted Code Execution**: All contributor code and criterion commands execute strictly inside the Phase 2B-1 Docker sandbox.

---

## 2. Repository-Grounded Semantic Inventory

This inventory establishes the authoritative ground truth extracted from the codebase before defining new Phase 2B-2 semantics.

| Component | Source File | Authoritative Ground Truth |
|---|---|---|
| **Specification Schema** | `specification/src/types.ts` | Schema v1.1: `version: "1.1"`, `repository: { owner, name }`, `baseCommit: string`, `environment: { image }`, `criteria: AcceptanceCriterion[]`. |
| **Criterion Types** | `specification/src/types.ts` | Exactly three types: `BUILD` (`command`), `TEST` (`command`), `COVERAGE` (`operator: '>='`, `thresholdBps: number`). |
| **Image Digest Format** | `specification/src/validate.ts` | Strict regex: `^[^\s@]+@sha256:[0-9a-f]{64}$`. |
| **Spec Canonicalization** | `specification/src/canonicalize.ts` | RFC 8785 JSON Canonicalization Scheme (JCS) via `canonicalize` package. |
| **Spec Commitment** | `specification/src/hash.ts` | `specHash = "0x" + keccak256(canonicalize(spec))`. |
| **On-Chain Outcomes** | `contracts/src/TrustBounty.sol` | `enum Outcome { NONE(0), PASS(1), FAIL(2), ERROR(3), INCONCLUSIVE(4) }`. |
| **On-Chain Verification** | `contracts/src/TrustBounty.sol` | `reportVerification(uint256 bountyId, Outcome outcome, bytes32 evidenceHash)`. |
| **Workspace Staging** | `verifier/src/workspace.ts` | Prepared detached-HEAD workspace at `workspacePath` verified against `targetCommit`. |
| **Sandbox Execution** | `verifier/src/docker.ts` | `executeInSandbox(config: SandboxConfig): Promise<ExecutionResult>`. |
| **Execution Statuses** | `verifier/src/docker-types.ts` | `SUCCESS`, `EXECUTION_FAILED`, `TIMEOUT`, `OOM`, `INFRASTRUCTURE_ERROR`. |
| **Error Categories** | `verifier/src/docker-types.ts` | `NONE`, `TIMEOUT`, `OOM`, `OUTPUT_ABUSE`, `IMAGE_ERROR`, `CONFIG_ERROR`, `WORKSPACE_ERROR`, `DOCKER_DAEMON_ERROR`. |

---

## 3. Existing Invariants & Immutability Guarantees

Phase 2B-2 operates strictly within the immutable boundaries established by prior phases:

1. **Frozen On-Chain Protocol (`7822265`)**:
   - `Outcome.PASS` releases bounty escrow to the contributor (subject to maintainer challenge).
   - `Outcome.FAIL` refunds bounty escrow to the maintainer (subject to contributor challenge).
   - `Outcome.ERROR` and `Outcome.INCONCLUSIVE` immediately escalate the bounty to `DISPUTED` for secondary verifier (V2) arbitration without requiring a challenge bond.
   - `evidenceHash` is stored on-chain as an immutable `bytes32` value and emitted in `VerificationReported` and `V2Reported` events.
2. **Phase 2A Workspace Isolation (`71f237a`)**:
   - The workspace directory is prepared strictly from the submitted Git commit in a detached HEAD state.
   - Repository source is mounted strictly as a read-only bind mount (`/input:ro`).
3. **Phase 2B-1 Container Security (`bc256bd`)**:
   - Host shell is never spawned (`shell: false`).
   - Container runs as unprivileged UID/GID `10001:10001` with zero Linux capabilities (`--cap-drop ALL`), `no-new-privileges=true`, `--network none`, and read-only rootfs (`--read-only`).
   - Ephemeral writable execution occurs strictly on dedicated, bounded tmpfs mounts (`/workspace` and `/tmp:noexec`).

---

## 4. New Phase 2B-2 Design Decisions (Explicitly Flagged)

All architectural choices introduced in Phase 2B-2 are explicitly labeled below:

* **[Phase 2B-2 Decision 1]**: **Fresh Ephemeral Sandbox per Executable Criterion**. Each executable criterion executes in a freshly created container with a dedicated ephemeral `/workspace` tmpfs populated from `/input:ro`. No mutable state, generated binaries, or temporary files are shared across criteria.
* **[Phase 2B-2 Decision 2]**: **Decoupled Execution Order vs. Serialization Order**. Criteria execute sequentially in the exact order declared by the specification author. In the canonical evidence manifest, criterion records are deterministically sorted by `criterion.id` ascending.
* **[Phase 2B-2 Decision 3]**: **Zero-Required Specification Rule**. A specification containing zero criteria with `required=true` is not settlement-capable. The verifier planning phase rejects such specifications with overall verdict **`ERROR`** and reason **`INVALID_SPECIFICATION_NO_REQUIRED_CRITERIA`**.
* **[Phase 2B-2 Decision 4]**: **Normative v0.1 Coverage Handling (No Fake Execution)**. In Schema v1.1, `COVERAGE` contains `operator` and `thresholdBps` but lacks a `command` field. The verifier does not invent a command and does not parse host coverage reports. A `COVERAGE` criterion is **not** executed by Docker in v0.1. It produces a deterministic criterion record with `verdict = 'INCONCLUSIVE'`, `exitCode = null`, `durationMs = 0`, and `verdictReason = 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1'`.
* **[Phase 2B-2 Decision 5]**: **Required-Aware Aggregation**. The settlement verdict is determined strictly by $C_{\text{required}} = \{\text{criteria where } required = true\}$. Optional criteria (`required=false`) are evaluated and evidenced when executable, but never override the settlement verdict.
* **[Phase 2B-2 Decision 6]**: **Canonical Decimal `bountyId` Representation**. In the canonical manifest, `bountyId` is formatted strictly as a decimal string (e.g. `"42"`), preventing JavaScript integer precision loss for on-chain `uint256` values exceeding $2^{53}-1$.
* **[Phase 2B-2 Decision 7]**: **Two-Tier Evidence Architecture**. The cryptographic commitment manifest (`manifest.json`) contains only deterministic semantic results and is the sole input to `evidenceHash`. Nondeterministic telemetry (timestamps, durations, container IDs, host paths) is sequestered into uncommitted operational metadata (`runtime-metadata.json`).
* **[Phase 2B-2 Decision 8]**: **Atomic Bundle Staging**. Evidence bundles are written to an ephemeral staging directory and atomically renamed to `evidence_bundles/<evidenceHash>/` only after artifact hashing and manifest verification succeed.

---

## 5. Criterion Model & Execution Lifecycle

### 5.1 Specification Consumption
Phase 2B-2 directly consumes the validated `AcceptanceSpecification` object emitted by `specification/src/validate.ts`. It never re-parses, mutates, or adds default fields to the input specification object.

### 5.2 Fresh Sandbox per Criterion
To guarantee that criteria cannot contaminate one another, hide build regressions, or leak secrets across steps, mutable state sharing is strictly forbidden:

```text
Immutable Host Workspace (/input:ro)
        │
        ├─── Criterion 1 (BUILD)    ───► [Container A (tmpfs /workspace)] ───► Destroy
        │
        ├─── Criterion 2 (TEST)     ───► [Container B (tmpfs /workspace)] ───► Destroy
        │
        └─── Criterion 3 (COVERAGE) ───► [NO EXECUTION in v0.1: Deterministic INCONCLUSIVE]
```

1. **Bootstrap Copy**: For each executable criterion (`BUILD`, `TEST`), Phase 2B-1 executes `cp -P -R /input/. /workspace` within the ephemeral tmpfs.
2. **State Isolation**: Build artifacts (e.g. `node_modules`, compiled `.o` / `.class` files) produced by Criterion 1 are destroyed when Container A terminates and are **not** present when Container 2 starts. Fresh sandbox isolation guarantees that subsequent criteria never depend on prior mutable execution state.
3. **Reproducibility**: Each executable criterion must be self-contained or explicitly declare its build prerequisites in its execution command (e.g. `"npm run build && npm test"`).
4. **Unsupported Coverage Exemption**: Unsupported `COVERAGE` criteria do not consume a sandbox execution because they are not executable under v0.1.

### 5.3 Execution Order vs. Canonical Serialization Order
- **Execution Order (Spec-Declared)**: Executable criteria are executed sequentially in the exact array order defined in `spec.criteria`. This respects intentional ordering defined by repository maintainers (e.g., executing a fast lint/build check before a slow integration test suite).
- **Serialization Order (ID-Sorted)**: When constructing `manifest.json`, criterion entries are sorted lexicographically by `criterion.id` (UTF-16 code unit order per RFC 8785).
- **Rationale for Decoupling**: Execution order represents operational developer intent. Serialization order represents canonical cryptographic identity. Decoupling ensures that two specifications with identical criteria declared in different orders produce identical criterion sorting in evidence manifests, while runtime execution preserves author dependencies.
- **Semantic Meaning of Execution Order in v0.1**: In v0.1, execution order has **operational execution precedence** (e.g., in the event of a fatal infrastructure crash, criteria executed prior to the crash produce evidence while subsequent criteria are skipped), but **no cryptographic commitment meaning**, because `evidenceHash` is computed strictly from the canonical manifest where criteria are sorted deterministically by `id`.

---

## 6. BUILD Semantics

In accordance with TrustBounty v0.1 baseline definitions:

- **Input**: `BuildCriterion` with `id`, `type: 'BUILD'`, `command: string`, `required: boolean`.
- **Execution**: The `command` string is passed as an atomic argument to the Phase 2B-1 runner, executing via `/bin/sh -c "<command>"` inside `/workspace`.
- **Verdict Rules**:
  - `ExecutionResult.status === 'SUCCESS'` (process exited with status `0`) $\rightarrow$ **`PASS`**.
  - `ExecutionResult.status === 'EXECUTION_FAILED'` (process exited with non-zero status $1 \le c \le 255$) $\rightarrow$ **`FAIL`**.
  - `ExecutionResult.status === 'TIMEOUT'` $\rightarrow$ **`ERROR`**.
  - `ExecutionResult.status === 'OOM'` $\rightarrow$ **`ERROR`**.
  - `ExecutionResult.status === 'INFRASTRUCTURE_ERROR'` $\rightarrow$ **`ERROR`**.
- **No Artifact Parsing**: The verifier does not inspect binary formats, ELF headers, or generated file existence. Exit code `0` is the sole normative predicate of build success.

---

## 7. TEST Semantics

In accordance with TrustBounty v0.1 baseline definitions:

- **Input**: `TestCriterion` with `id`, `type: 'TEST'`, `command: string`, `required: boolean`.
- **Execution**: The `command` string executes via `/bin/sh -c "<command>"` inside `/workspace`.
- **Verdict Rules**:
  - `ExecutionResult.status === 'SUCCESS'` (exit code `0`, all assertions satisfied) $\rightarrow$ **`PASS`**.
  - `ExecutionResult.status === 'EXECUTION_FAILED'` (non-zero exit code, test failure, crash) $\rightarrow$ **`FAIL`**.
  - `ExecutionResult.status === 'TIMEOUT'` $\rightarrow$ **`ERROR`**.
  - `ExecutionResult.status === 'OOM'` $\rightarrow$ **`ERROR`**.
  - `ExecutionResult.status === 'INFRASTRUCTURE_ERROR'` $\rightarrow$ **`ERROR`**.
- **No Framework Parsing**: The verifier does not parse JUnit XML, TAP streams, or test runner JSON output. Exit code `0` is the sole normative predicate of test suite success.

---

## 8. COVERAGE Semantics & Schema Reconciliation

### ACTUAL SCHEMA
The exact current `CoverageCriterion` shape defined by the specification package in normalized TypeScript and JSON form is:

```typescript
export interface CoverageCriterion {
  id: string;
  type: 'COVERAGE';
  required: boolean;
  operator: '>=';
  thresholdBps: number;
}
```

Example valid normalized JSON:
```json
{
  "id": "coverage-check",
  "type": "COVERAGE",
  "required": true,
  "operator": ">=",
  "thresholdBps": 8000
}
```

- **Present Fields**: `id` (string), `type` (`'COVERAGE'`), `required` (boolean), `operator` (strictly `'>='`), `thresholdBps` (integer $0 \le x \le 10000$).
- **Absent Fields**: `command` is **strictly absent**. It does not exist on `CoverageCriterion`.

### SOURCE OF TRUTH
The authoritative source of truth for specification schemas is the `specification/` package:
1. **`specification/src/types.ts` (lines 19–23)**: Defines `CoverageCriterion extends BaseCriterion` with strictly `operator` and `thresholdBps`.
2. **`specification/src/validate.ts` (line 8 & lines 190–218)**: Sets `ALLOWED_COVERAGE_CRITERION_KEYS = new Set(['id', 'type', 'operator', 'thresholdBps', 'required'])`. The validator iterates over all object keys and strictly rejects any unexpected property. If a specification provides a `command` field on a `COVERAGE` criterion, `validateSpecification()` returns `valid: false` with error: `Unknown field: "criteria[i].command"`.
3. **`specification/test/validate.test.ts` (lines 31–36 & 244–252)**: Unit tests explicitly prove that valid specifications do not supply `command` for `COVERAGE`, and that unknown fields on `COVERAGE` are strictly rejected.

### DOCUMENTATION DISCREPANCIES
A thorough comparison of the repository documentation against the authoritative implementation reveals the following:

1. **`docs/SPECIFICATION.md` §Criterion Semantics (`COVERAGE`)**:
   - **Status**: **Fully Consistent with Implementation**.
   - **Content**: Declares only `operator`, `thresholdBps`, and `required`. `command` is absent.
2. **`docs/VERIFICATION_SPEC.md` §5.3 (`COVERAGE Criterion`)**:
   - **Status**: **Schema Consistent, Evaluation Narrative Divergent**.
   - **Schema Example**: Shows only `id`, `type: "COVERAGE"`, `operator: ">="`, `thresholdBps: 8500`, `required: true`. `command` is absent.
   - **Narrative Discrepancy**: States: *"Evaluation: Verifier parses generated coverage reports (e.g. LCOV / Istanbul) and extracts total line/branch coverage percentage."* This narrative assumed a shared mutable filesystem between a test step and an off-chain coverage parser.
3. **Prior Architectural Hypotheses**:
   - Earlier exploratory discussions considered whether `CoverageCriterion` could contain `command: string` to invoke an in-container coverage check (e.g. `"npm run coverage"`). The actual codebase disproves this hypothesis: `command` was never added to `CoverageCriterion` in Schema v1.1.

### V0.1 COVERAGE SEMANTICS
Based strictly on the **ACTUAL SCHEMA** (where `command` does not exist), Phase 2B-2 defines the normative v0.1 evaluation rules:

1. **No Invented Command**: The verifier engine will **not** invent, inject, or synthesize a `command` property on `CoverageCriterion`. Doing so would violate the unmutated consumption of Schema v1.1 and corrupt `specHash` verification.
2. **No Host-Side Coverage Report Parsing**: The verifier engine will **not** parse LCOV, Cobertura, or Istanbul coverage files on the verifier host. Parsing untrusted coverage files generated by arbitrary contributor code on the host violates host isolation and introduces significant XML/file parser vulnerability surfaces.
3. **No Docker Sandbox Allocation**: A `COVERAGE` criterion is **not** executed by Docker in v0.1. No container is created, started, or destroyed for unsupported coverage criteria.
4. **Deterministic Criterion Verdict**:
   - `verdict = 'INCONCLUSIVE'`
   - `exitCode = null`
   - `durationMs = 0` (in operational metadata)
   - `verdictReason = 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1'`
   - No sandbox execution occurs, and no mock artifact logs or fake digests are generated.
5. **Settlement Impact via Required Flag**:
   - If `required === true`: The criterion contributes `INCONCLUSIVE` to the settlement-authoritative criterion set ($C_{\text{required}}$) and therefore prevents overall `PASS` (the overall verdict evaluates to `INCONCLUSIVE`, triggering secondary verifier dispute escalation).
   - If `required === false`: It remains visible in the evidence manifest but does not block an overall `PASS` from all required criteria.
   - This is documented as an explicit v0.1 protocol limitation.
6. **Full Definition Bound in Canonical Manifest Without Invented Null Fields**:
   - The canonical evidence manifest binds the **actual normalized definition**: `id`, `type: 'COVERAGE'`, `required`, `operator: '>='`, `thresholdBps: <number>`, `verdict: 'INCONCLUSIVE'`, `verdictReason: 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1'`, `exitCode: null`.
   - `command` is **omitted** (not `null`), matching the actual Schema v1.1 shape.
7. **Forward Schema v1.2 Recommendation**:
   - For post-v0.1, Schema v1.2 should officially introduce `command: string` to `CoverageCriterion` (e.g. `nyc check-coverage` or `pytest --cov-fail-under`), enabling self-contained in-container threshold evaluation with exit code 0/non-zero semantics.

---

## 9. ExecutionResult to CriterionVerdict Mapping

The mapping from Phase 2B-1 `ExecutionResult` to Phase 2B-2 `CriterionVerdict` is strictly deterministic for all executable criteria:

```text
┌───────────────────────────────────────┐
│     Phase 2B-1 ExecutionResult        │
├───────────────────┬───────────────────┤
│ status            │ errorCategory     │
├───────────────────┼───────────────────┤
│ SUCCESS           │ NONE              │ ────► PASS
│ EXECUTION_FAILED  │ NONE              │ ────► FAIL
│ TIMEOUT           │ TIMEOUT           │ ────► ERROR
│ OOM               │ OOM               │ ────► ERROR
│ INFRASTRUCTURE... │ OUTPUT_ABUSE      │ ────► ERROR
│ INFRASTRUCTURE... │ DOCKER_DAEMON...  │ ────► ERROR
│ INFRASTRUCTURE... │ WORKSPACE_ERROR   │ ────► ERROR
│ INFRASTRUCTURE... │ IMAGE_ERROR       │ ────► ERROR
│ INFRASTRUCTURE... │ CONFIG_ERROR      │ ────► ERROR
└───────────────────┴───────────────────┘
```

### 9.1 Mapping Table

| `ExecutionResult.status` | `ExecutionResult.errorCategory` | `CriterionVerdict` | On-Chain Outcome Implication | Rationale |
|---|---|---|---|---|
| `SUCCESS` | `NONE` | **`PASS`** | Contributor advancement | Process exited cleanly with exit code 0. |
| `EXECUTION_FAILED` | `NONE` | **`FAIL`** | Maintainer protection | Criterion command failed (non-zero exit code). |
| `TIMEOUT` | `TIMEOUT` | **`ERROR`** | Automatic dispute escalation | Bounded wall-clock execution limit exceeded. |
| `OOM` | `OOM` | **`ERROR`** | Automatic dispute escalation | Container killed by Linux OOM killer. |
| `INFRASTRUCTURE_ERROR` | `OUTPUT_ABUSE` | **`ERROR`** | Automatic dispute escalation | Stream exceeded active output abuse cap. |
| `INFRASTRUCTURE_ERROR` | `WORKSPACE_ERROR` | **`ERROR`** | Automatic dispute escalation | In-container bootstrap copy or staging failed. |
| `INFRASTRUCTURE_ERROR` | `DOCKER_DAEMON_ERROR` | **`ERROR`** | Automatic dispute escalation | Docker engine failure, crash, or daemon drop. |
| `INFRASTRUCTURE_ERROR` | `IMAGE_ERROR` | **`ERROR`** | Automatic dispute escalation | Image pull failure or digest mismatch. |

### 9.2 Inconclusive Reservation
`INCONCLUSIVE` is **never** emitted as a result of normal process exits or resource exhaustion. It is strictly reserved for:
1. `COVERAGE` criteria defined under Schema v1.1 lacking an executable command (`COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1`).
2. Verified non-deterministic outcomes between redundant runs (e.g. secondary arbitration).

---

## 10. Multi-Criterion Aggregation & Execution Flow

### 10.1 Operational Normativity of `required: boolean`
In Schema v1.1, every criterion includes `required: boolean`. In Phase 2B-2, this property is strictly settlement-authoritative:

- **Required Criterion (`required: true`)**:
  A required criterion is settlement-authoritative. Its result directly participates in determining the on-chain settlement verdict (`reportVerification` / `reportV2`).
- **Optional Criterion (`required: false`)**:
  An optional criterion is evaluated and evidenced when executable, but its result does not determine the settlement verdict.
  - An optional criterion result (`PASS`, `FAIL`, `ERROR`, or `INCONCLUSIVE`) is recorded with full fidelity in `manifest.json` and persisted in the evidence bundle.
  - Optional criteria are **never** called "ignored" or omitted from evidence. They are evaluated for maintainer telemetry and auditable records without blocking settlement.

### 10.2 Zero-Required Rule
If an author submits an acceptance specification containing **zero** criteria with `required === true`, the specification is not settlement-capable (no criterion exists to authoritatively release or refund escrow).

- **Verifier Evaluation Rule**: During verification planning, before container execution, the verifier inspects `spec.criteria`. If every criterion has `required === false`, execution is halted immediately.
- **Overall Verdict**: **`ERROR`**
- **Verdict Reason**: **`INVALID_SPECIFICATION_NO_REQUIRED_CRITERIA`**
- **Scope Note**: Schema v1.1 validator in `specification/` is frozen and validates syntax/types. The zero-required rule is a Phase 2B-2 verification-planning rule enforced before sandbox scheduling.

### 10.3 Required-Aware Aggregation Formula
Let the set of settlement-authoritative criteria be:

$$C_{\text{required}} = \{ c \in \text{spec.criteria} \mid c.\text{required} = \text{true} \}$$

If $|C_{\text{required}}| = 0$, the overall verdict is **`ERROR`** per §10.2.

When $|C_{\text{required}}| \ge 1$, the overall verification verdict is determined **strictly and exclusively** by $C_{\text{required}}$ using the precedence hierarchy:

$$\text{ERROR} \succ \text{INCONCLUSIVE} \succ \text{FAIL} \succ \text{PASS}$$

1. **Any required criterion evaluates to `ERROR`** $\implies$ Overall Verdict = **`ERROR`**
2. **Otherwise, any required criterion evaluates to `INCONCLUSIVE`** $\implies$ Overall Verdict = **`INCONCLUSIVE`**
3. **Otherwise, any required criterion evaluates to `FAIL`** $\implies$ Overall Verdict = **`FAIL`**
4. **Otherwise (all required criteria evaluate to `PASS`)** $\implies$ Overall Verdict = **`PASS`**

**Invariance**: Optional criteria (`required: false`) **never** override, degrade, or elevate the settlement verdict derived from $C_{\text{required}}$.

### 10.4 Concrete Aggregation Examples

| Scenario | Required Criteria Results | Optional Criteria Results | Overall Settlement Verdict | On-Chain Effect |
|:---|:---|:---|:---|:---|
| **1** | `PASS` | `FAIL` | **`PASS`** | Escrow released to contributor (optional failure evidenced but does not block) |
| **2** | `PASS` | `ERROR` | **`PASS`** | Escrow released to contributor (optional error evidenced but does not block) |
| **3** | `FAIL` | `PASS` | **`FAIL`** | Escrow refunded to maintainer (required failure governs) |
| **4** | `PASS`, `INCONCLUSIVE` | *Any* | **`INCONCLUSIVE`** | Escalated to V2 dispute arbitration |
| **5** | `PASS`, `ERROR` | *Any* | **`ERROR`** | Escalated to V2 dispute arbitration |
| **6** | *None* ($|C_{\text{required}}| = 0$) | `PASS`, `PASS` | **`ERROR`** | `INVALID_SPECIFICATION_NO_REQUIRED_CRITERIA` |

### 10.5 Execution Progression & Fatal Error Handling
- **Non-Short-Circuiting Execution for Normal Failures**: In normal execution, if a required criterion evaluates to `FAIL`, subsequent criteria are **still executed**. This ensures complete evidence transcripts are available for dispute arbitration.
- **Fatal Error Short-Circuiting (Timeout, OOM, Infrastructure)**: If a fatal infrastructure error (`INFRASTRUCTURE_ERROR`), process timeout (`TIMEOUT`), or memory exhaustion (`OOM`) occurs during criterion execution, the sandbox environment or host resources are compromised or exhausted. The runner halts further container execution immediately. Subsequent unexecuted criteria are recorded with `verdict: 'ERROR'`, `exitCode: null`, and a specific diagnostic `verdictReason`:
  - `EXECUTION_SKIPPED_DUE_TO_PRIOR_TIMEOUT`
  - `EXECUTION_SKIPPED_DUE_TO_PRIOR_OOM`
  - `EXECUTION_SKIPPED_DUE_TO_PRIOR_INFRASTRUCTURE_ERROR`
- **Omission of Artifact Digests for Unexecuted / Skipped Criteria**: Criteria that were not executed (skipped `BUILD`/`TEST` criteria or unsupported `COVERAGE` criteria) do not produce sandbox streams or retain log files. They strictly omit `stdoutDigest`, `stderrDigest`, `stdoutTruncated`, and `stderrTruncated` rather than generating synthetic empty stream digests or fake logs.
- **Unsupported Coverage Execution**: `COVERAGE` criteria under Schema v1.1 are not scheduled for Docker sandbox execution; they deterministically evaluate to `INCONCLUSIVE` without consuming container slots.

---

## 11. Evidence Architecture: Cryptographic vs. Operational

To ensure byte-level reproducibility of `evidenceHash`, Phase 2B-2 enforces a strict architectural boundary between **committed semantic data** and **uncommitted operational telemetry**:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                    EVIDENCE BUNDLE ARCHITECTURE                         │
├────────────────────────────────────┬────────────────────────────────────┤
│   CRYPTOGRAPHIC COMMITMENT         │      OPERATIONAL METADATA          │
│   (manifest.json)                  │      (runtime-metadata.json)       │
├────────────────────────────────────┼────────────────────────────────────┤
│ • Canonical Schema Version ("1.0") │ • Host wall-clock start/end times  │
│ • specHash commitment              │ • Wall-clock durationMs / total    │
│ • bountyId (canonical decimal str) │ • Local Docker Container IDs       │
│ • repository (owner, name)         │ • Local Host Workspace Paths       │
│ • baseCommit & submittedCommit     │ • Local Process IDs (PIDs)         │
│ • image digest & platform          │ • Host Operating System & Kernel   │
│ • sorted criteria definitions      │ • Host Docker Engine Version       │
│ • executed commands (BUILD/TEST)   │ • Verifier daemon instance ID      │
│ • criterion verdicts & exit codes  │ • Local file system paths          │
│ • artifact Keccak-256 digests      │                                    │
│ • truncation boolean flags         │                                    │
│ • overallVerdict & optional reason │                                    │
│ • verifierVersion                  │                                    │
├────────────────────────────────────┴────────────────────────────────────┤
│                        HASHED WITH KECCAK-256                           │
│                                  │                                      │
│                                  ▼                                      │
│                          bytes32 evidenceHash                           │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 12. Canonical Manifest Schema (`manifest.json`)

The canonical evidence manifest is serialized to `manifest.json`. It is strictly typed, closed to unknown properties, and deterministically formatted.

### 12.1 TypeScript Schema Definition

```typescript
export type ManifestVerdict = 'PASS' | 'FAIL' | 'ERROR' | 'INCONCLUSIVE';

/**
 * Criterion evidence record for executable criteria (BUILD and TEST).
 */
export interface BuildTestCriterionEvidenceRecord {
  /** Criterion ID matching the specification */
  id: string;
  /** Criterion type */
  type: 'BUILD' | 'TEST';
  /** Mandatory settlement-authoritative flag */
  required: boolean;
  /** Exact executed command string */
  command: string;
  /** Evaluated verdict */
  verdict: ManifestVerdict;
  /** Diagnostic verdict reason if failed or errored */
  verdictReason?: string;
  /** Process exit code (null if terminated by signal, timeout, or OOM) */
  exitCode: number | null;
  /** Keccak-256 hash of retained stdout raw bytes (omitted if execution did not occur) */
  stdoutDigest?: string;
  /** Keccak-256 hash of retained stderr raw bytes (omitted if execution did not occur) */
  stderrDigest?: string;
  /** True if stdout exceeded verifier retention cap (omitted if execution did not occur) */
  stdoutTruncated?: boolean;
  /** True if stderr exceeded verifier retention cap (omitted if execution did not occur) */
  stderrTruncated?: boolean;
  /** High-level error classification */
  errorCategory: string;
}

/**
 * Criterion evidence record for Schema v1.1 COVERAGE criteria (unsupported for execution in v0.1).
 * Notice: command, stdoutDigest, stderrDigest, and truncation flags are strictly absent
 * because no container execution occurred.
 */
export interface CoverageCriterionEvidenceRecord {
  /** Criterion ID matching the specification */
  id: string;
  /** Criterion type */
  type: 'COVERAGE';
  /** Mandatory settlement-authoritative flag */
  required: boolean;
  /** Coverage comparison operator from specification */
  operator: '>=';
  /** Coverage threshold in basis points from specification */
  thresholdBps: number;
  /** Evaluated verdict (strictly INCONCLUSIVE in v0.1) */
  verdict: 'INCONCLUSIVE';
  /** Normative reason indicating lack of command in v1.1 */
  verdictReason: 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1';
  /** Process exit code (always null as no execution occurred) */
  exitCode: null;
}

/**
 * Closed union of all valid criterion evidence records in Phase 2B-2.
 */
export type CriterionEvidenceRecord =
  | BuildTestCriterionEvidenceRecord
  | CoverageCriterionEvidenceRecord;

export interface CanonicalEvidenceManifest {
  /** Evidence specification version (strictly "1.0") */
  schemaVersion: '1.0';
  /** Cryptographic hash of the input AcceptanceSpecification (0x-prefixed 64 hex chars) */
  specHash: string;
  /**
   * Target bounty identifier as a canonical decimal string representation of the on-chain uint256.
   * Decimal string representation prevents JavaScript integer precision loss for values > 2^53 - 1.
   * Example: "42"
   */
  bountyId: string;
  /** Target repository coordinates */
  repository: {
    owner: string;
    name: string;
  };
  /** Base commit from specification */
  baseCommit: string;
  /** Evaluated submitted Git commit hash (40 hex characters) */
  submittedCommit: string;
  /** Environment image reference pinned by digest and verified platform */
  environment: {
    image: string;
    platform: 'linux/amd64';
  };
  /** Criteria results sorted ascending by criterion id */
  criteria: CriterionEvidenceRecord[];
  /** Overall aggregated settlement verdict derived from C_required */
  overallVerdict: ManifestVerdict;
  /** Diagnostic reason if overallVerdict is ERROR or INCONCLUSIVE */
  overallVerdictReason?: string;
  /** SemVer release of the verifier engine (e.g. "0.1.0") */
  verifierVersion: string;
}
```

### 12.2 Sorting Invariant
In `CanonicalEvidenceManifest.criteria`, entries **must** be sorted lexicographically ascending by `id` using UTF-16 code unit values:
```typescript
manifest.criteria.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
```

---

## 13. Artifact Model & Hashing

### 13.1 Artifact Storage Set
Phase 2B-2 retains two raw log artifacts per criterion:
1. `stdout`: The exact raw bytes retained by the Phase 2B-1 stream drainer.
2. `stderr`: The exact raw bytes retained by the Phase 2B-1 stream drainer.

### 13.2 Artifact Digest Computation
Artifact digests are computed directly over raw binary buffers prior to any string transcoding or character encoding conversions:

$$\text{artifactDigest} = \text{"0x"} + \text{Keccak-256}(\text{rawRetainedBytes})$$

- **Empty Stream Digest**: If stdout or stderr is completely empty (0 bytes), the digest is the standard Keccak-256 hash of an empty byte array:
  `0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470`.
- **Truncation Semantics**: When output exceeds retention limits (`maxStdoutBytes` or `maxStderrBytes`, default 5 MB), stream capture stops and `stdoutTruncated` or `stderrTruncated` is set to `true`. The digest binds **exactly the retained bytes**. The evidence manifest explicitly records truncation so counterparties and arbitrators are alerted that output was capped.

---

## 14. JCS Canonicalization & `evidenceHash` Construction

`evidenceHash` is constructed using the exact same cryptographic discipline applied to `specHash`:

```text
┌─────────────────────────────────────────────────────────────┐
│ 1. Compute raw Keccak-256 digests for all retained artifacts │
│ 2. Construct in-memory CanonicalEvidenceManifest object    │
│ 3. Sort manifest.criteria by id ascending (UTF-16)          │
│ 4. Apply RFC 8785 JSON Canonicalization Scheme (JCS)        │
│ 5. Encode canonical JSON string to UTF-8 byte array         │
│ 6. Compute Keccak-256 hash over canonical byte array        │
│ 7. Format digest as normalized lowercase "0x" + 64 hex chars│
└─────────────────────────────────────────────────────────────┘
```

### 14.1 Mathematical Definition

$$\text{canonicalJson} = \text{RFC8785}(\text{manifest})$$

$$\text{evidenceHash} = \text{"0x"} + \text{Keccak-256}(\text{canonicalJson})$$

### 14.2 Byte-Level Invariants
- **No Floating Point Numbers**: Exit codes are integers; threshold basis points are integers; timestamps are omitted.
- **Key Sorting**: Keys are ordered lexicographically by Unicode code points at every level of the object hierarchy per RFC 8785 §3.2.3.
- **Whitespace**: No whitespace between tokens (`:`, `,`) outside string literals.
- **Encoding**: Output is strictly encoded in UTF-8 without byte-order marks (BOM).

### 14.3 Semantic Scope: Tamper-Evident Evidence Commitment
The construction of `evidenceHash` guarantees that any post-hoc modification to the recorded criteria, commands, exit codes, output digests, spec hash, commit hashes, or bounty ID invalidates the cryptographic commitment:
$$\text{evidenceHash} = \text{integrity commitment to recorded evidence}$$
It serves strictly as a **tamper-evident evidence commitment** binding the verifier's attested claims. It does **not** serve as cryptographic non-repudiation or mathematical proof of truthful execution.

---

## 15. Operational Metadata Schema (`runtime-metadata.json`)

To preserve debugging and performance observability without polluting `evidenceHash`, operational metadata is written to a parallel, unhashed file `runtime-metadata.json`.

```json
{
  "evidenceHash": "0x1234...abcd",
  "bountyId": "bounty-42",
  "runId": "run-001",
  "verifierId": "primary-verifier-node-1",
  "timestamps": {
    "startedAt": "2026-09-20T00:15:00.000Z",
    "completedAt": "2026-09-20T00:15:45.120Z",
    "totalDurationMs": 45120
  },
  "environment": {
    "dockerEngineVersion": "29.8.0",
    "hostOs": "linux",
    "hostKernel": "6.18.0",
    "cpuCount": 16,
    "totalMemoryBytes": 34359738368
  },
  "criteriaExecution": [
    {
      "id": "build-step",
      "containerId": "a1b2c3d4e5f6...",
      "durationMs": 12450,
      "hostWorkspacePath": "C:\\Users\\...\\ws-1234"
    }
  ]
}
```

---

## 16. Evidence Bundle Layout & Atomic Storage

### 16.1 Deterministic Filesystem Layout
Bundles are stored in content-addressed directories named after their `evidenceHash`:

```text
evidence_bundles/
└── 0x7f83b1657ff1fc53b92dc18148a1d65dfc2d4b1fa3d677284addd200126d9069/
    ├── manifest.json
    ├── runtime-metadata.json
    └── artifacts/
        ├── build-step.stdout.log
        ├── build-step.stderr.log
        ├── test-suite.stdout.log
        └── test-suite.stderr.log
```

### 16.2 Atomic Staging Procedure
To prevent half-written, corrupted, or unparseable evidence bundles from being exposed as valid commitments:

```text
[Transient Staging Directory]
.staging-bounty42-run001/
  ├── artifacts/ (*.stdout.log, *.stderr.log)
  ├── manifest.json
  └── runtime-metadata.json
            │
            ▼
[Cryptographic Validation & Digest Check]
            │
            ▼
[Atomic Directory Move / Rename]
            │
            ▼
evidence_bundles/<evidenceHash>/
```

1. **Allocate Staging Directory**: Create an isolated temporary directory in `.staging-<bountyId>-<runId>`.
2. **Stream Artifacts**: Write retained stdout and stderr buffers to disk.
3. **Compute Hashes**: Compute raw Keccak-256 hashes of disk artifacts and compare against in-memory stream digests.
4. **Serialize Manifest**: Produce `manifest.json` using RFC 8785 JCS; compute `evidenceHash`.
5. **Serialize Metadata**: Produce `runtime-metadata.json`.
6. **Atomic Rename**:
   - On POSIX: Use `fs.renameSync(stagingDir, targetDir)`.
   - On Windows: Use directory move with fallback retry; if target directory already exists with identical content, delete staging directory and accept target.
7. **Post-Commitment Verify**: Read back `manifest.json` from the finalized path, recompute `evidenceHash`, and assert equality before returning.

### 16.3 Failure & Collision Recovery
- **Crash During Staging**: Incomplete `.staging-*` directories are ignored by evidence lookups and cleaned up on verifier startup.
- **Identical `evidenceHash` Collision**: If `evidence_bundles/<evidenceHash>` already exists, the verifier verifies that the existing `manifest.json` matches the new manifest byte-for-byte. If identical, the operation succeeds idempotently; if conflicting, it throws a fatal `EvidenceCollisionError`.
- **Disk Full (ENOSPC)**: Staging is aborted, staging directory purged, and verifier reports `INFRASTRUCTURE_ERROR` without publishing an on-chain `evidenceHash`.

---

## 17. Evidence Commitment vs. Execution Separation

To prevent invalid protocol state transitions, Phase 2B-2 maintains strict architectural separation across three execution phases:

```text
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│ 1. EXECUTION    │ ────► │ 2. EVALUATION   │ ────► │ 3. COMMITMENT   │
│ (Docker Sandbox)│       │ (Verdict Logic) │       │ (Bundle & Hash) │
└─────────────────┘       └─────────────────┘       └─────────────────┘
```

1. **Execution Success with Commitment Failure**: If all criteria pass (`status === 'SUCCESS'`), but bundle creation fails (e.g. disk write failure, permission error, out-of-space):
   - The criterion verdicts remain internally `PASS`.
   - The overall externally reportable protocol result **must become `ERROR`**.
   - The verifier **must never** report `PASS` on-chain without submitting a valid, finalized, content-addressed `evidenceHash`.
   - The verifier **must never** convert a contributor `PASS` into a contributor `FAIL` due to commitment failure.

---

## 18. Threat Model & Security Analysis

### 18.1 Contributor Adversarial Vectors
- **Output Flooding (Zip Bomb / `/dev/urandom` Flood)**: A malicious pull request produces gigabytes of output to exhaust verifier memory or disk.
  - *Mitigation*: Phase 2B-1 caps in-memory retention at 5 MB and actively terminates the container with `SIGKILL` if cumulative output exceeds 20 MB (`OUTPUT_ABUSE`). The manifest sets `stdoutTruncated: true` and logs the abuse termination.
- **Cross-Criterion Contamination**: A test script attempts to write persistent backdoors into `/input` or `/workspace` to manipulate subsequent test steps.
  - *Mitigation*: `/input` is read-only. `/workspace` is an ephemeral tmpfs destroyed after each criterion.
- **Truncation Exploitation**: A contributor attempts to hide compilation errors by emitting megabytes of clean text to push error messages beyond the truncation limit.
  - *Mitigation*: The process exit code is evaluated independently of retained output. Even if stderr is truncated, exit code $\ne 0$ guarantees `FAIL`.

### 18.2 Maintainer Adversarial Vectors
- **Command Injection via Specification**: A maintainer places shell metacharacters or destructive commands in `criterion.command`.
  - *Mitigation*: Commands execute strictly within the unprivileged (`10001:10001`), network-isolated, capability-stripped container sandbox. Host execution is prohibited.
- **Misleading Criterion Definitions**: A maintainer defines an impossible criterion or an excessively strict timeout.
  - *Mitigation*: The specification is committed on-chain as `specHash` before development begins. The contributor inspects the exact immutable criteria before submitting work.

### 18.3 Verifier Adversarial Vectors & Limits of On-Chain Enforcement
- **Evidence Substitution**: A rogue verifier attempts to report `FAIL` while linking an evidence hash from an unrelated bounty.
  - *Mitigation*: The canonical manifest cryptographically binds `bountyId`, `specHash`, `baseCommit`, and `submittedCommit`. When the evidence bundle is audited in a dispute, any mismatch between the manifest and on-chain parameters immediately proves oracle fraud.
- **Limits of Cryptographic Commitments (Integrity Commitment vs. Truthful Execution)**:
  - An `evidenceHash` is an **integrity commitment to recorded evidence**; it is **NOT** proof of truthful execution.
  - `evidenceHash` provides **cryptographically bound evidence** and a **tamper-evident evidence commitment** that prevents post-hoc log alteration, but it does **not** provide cryptographic non-repudiation or prove verifier honesty.
  - The EVM smart contract cannot verify whether the verifier honestly ran the Docker container or fabricated the recorded logs.
  - Truthful execution and honesty guarantees are achieved structurally through dual-oracle arbitration (V1 vs. V2) and symmetric economic bonds, not through cryptography alone.

---

## 19. Dispute Arbitration (V2 Alignment)

When a bounty enters `DISPUTED` (via challenge or automatic recovery), the secondary verifier (V2) uses the Phase 2B-2 evidence bundle to conduct dispute resolution:

1. **Inspection of V1 Claim**: V2 retrieves `evidence_bundles/<evidenceHash>/manifest.json` and parses:
   - What exact `specHash` was evaluated.
   - What exact `submittedCommit` was evaluated.
   - What image digest and platform were used.
   - What exact commands were executed and what exit codes were claimed.
   - What artifact digests were produced.
2. **Independent Re-Execution**: V2 independently executes the criteria in its own isolated sandbox.
3. **Equivocation Detection**: If V1 claimed exit code `42` with an empty stdout, but V2 observes clean exit code `0` with matching artifact digests, V2 detects verifier divergence and reports the authoritative verdict on-chain.

---

## 20. Versioning Discipline

Phase 2B-2 strictly isolates three independent version identifiers:

1. **`specVersion: "1.1"`**: Governs the schema of `AcceptanceSpecification` (from `specification/src/types.ts`).
2. **`evidenceSchemaVersion: "1.0"`**: Governs the schema of `CanonicalEvidenceManifest` (`manifest.json`).
3. **`verifierVersion: string`**: The SemVer release string of the verifier codebase (e.g. `"0.1.0"`), included in `manifest.json` to identify the implementation version that produced the evidence.

---

## 21. Rigorous Testing Gate for Phase 2B-2 Implementation

Future implementation of Phase 2B-2 must satisfy the following comprehensive test suite:

### 21.1 Unit Test Suite
1. **Schema Fidelity**: Confirms that input `AcceptanceSpecification` is consumed without mutation or property injection.
2. **Criterion Mapping**: Validates all mappings from `ExecutionResult.status` to `CriterionVerdict`.
3. **Aggregation Precedence**: Exhaustively tests the truth table for `ERROR > INCONCLUSIVE > FAIL > PASS`.
4. **Sorting Determinism**: Asserts that criteria array in `manifest.json` is sorted by `id` ascending regardless of input permutation.
5. **Artifact Hashing**: Validates Keccak-256 digests against known test vectors for empty, small, large, and truncated buffers.
6. **JCS Canonicalization**: Asserts that object key ordering in memory does not affect the output byte stream.
7. **evidenceHash Format**: Asserts output is lowercase `0x` + 64 hex characters.

### 21.2 Integration Test Suite (Real Sandbox Execution)
1. **Fresh Sandbox per Criterion**: Validates that files created in `/workspace` during Criterion 1 are absent during Criterion 2.
2. **Read-Only `/input` Enforcement**: Asserts that criteria cannot write to `/input`.
3. **Exit Code Propagation**: Asserts that `exit 0` $\rightarrow$ `PASS`, `exit 1` $\rightarrow$ `FAIL`.
4. **Timeout Escalation**: Asserts that an in-container `sleep 30` with a 5s timeout yields criterion verdict `ERROR`.
5. **OOM Escalation**: Asserts that memory exhaustion yields criterion verdict `ERROR`.
6. **Full Multi-Criterion Run**: Executes a complete specification (`BUILD` + `TEST`), generates evidence bundle, and asserts bundle integrity.

### 21.3 Adversarial Evidence Verification Suite
1. **Byte Mutation Detection**: Modifying a single byte in `artifacts/test-suite.stdout.log` causes manifest digest verification to fail.
2. **Command Mutation Detection**: Altering the executed command string in `manifest.json` changes `evidenceHash`.
3. **Commit Mutation Detection**: Altering `submittedCommit` in `manifest.json` changes `evidenceHash`.
4. **SpecHash Mutation Detection**: Altering `specHash` in `manifest.json` changes `evidenceHash`.
5. **Order Invariance**: Two runs with identical criteria declared in opposite order produce identical `evidenceHash`.
6. **Atomic Cleanup on Interruption**: Simulating an abort or disk error during staging leaves no corrupted bundle in `evidence_bundles/`.

---

## 22. Implementation Roadmap (Phase 2B-2 Execution Plan)

When implementation begins, development must proceed in this exact sequence:

1. **`verifier/src/evidence-types.ts`**: Define TypeScript interfaces for `ManifestVerdict`, `CriterionEvidenceRecord`, `CanonicalEvidenceManifest`, and `OperationalMetadata`.
2. **`verifier/src/evaluator.ts`**: Implement `evaluateCriterion()` wrapping Phase 2B-1 `executeInSandbox()`, verdict mapping, and aggregation logic.
3. **`verifier/src/manifest.ts`**: Implement artifact hashing, manifest construction, criteria sorting, JCS canonicalization, and `evidenceHash` generation.
4. **`verifier/src/bundle.ts`**: Implement atomic staging directory lifecycle, artifact persistence, and finalization to `evidence_bundles/<evidenceHash>/`.
5. **`verifier/src/index.ts`**: Export public evaluators and manifest utilities.
6. **`verifier/test/evaluator.test.ts` & `verifier/test/evidence.test.ts`**: Implement unit, integration, and adversarial test suites.

---

## 23. Summary & Normative Approval Baseline

This design document provides the complete, unambiguous, mathematically rigorous specification required to implement Phase 2B-2. It preserves all frozen on-chain guarantees (`7822265`), adheres to Phase 2A workspace safety (`71f237a`), utilizes Phase 2B-1 execution boundaries (`bc256bd`), and resolves all criterion evaluation and evidence commitment semantics without unverified external dependencies.
