# TrustBounty Verification Specification (v0.1)

## 1. Purpose & Scope

This document specifies the off-chain verification contract for TrustBounty Protocol v0.1. It defines the exact input data structures, container execution requirements, acceptance criteria semantics, outcome classification rules, and cryptographic evidence commitments used by verification oracles (`PRIMARY_VERIFIER` and `SECONDARY_VERIFIER`).

---

## 2. Acceptance Specification Format (Schema v1.1)

Acceptance specifications conform to the closed JSON Schema v1.1:

```json
{
  "version": "1.1",
  "repository": {
    "owner": "string",
    "name": "string"
  },
  "baseCommit": "string",
  "environment": {
    "image": "string"
  },
  "criteria": [
    {
      "id": "string",
      "type": "BUILD | TEST | COVERAGE",
      "required": true
    }
  ]
}
```

### 2.1 Specification Fields

1. **`version`** (`string`, mandatory): Must be exactly `"1.1"`.
2. **`repository`** (`object`, mandatory):
   * `owner` (`string`, mandatory): Repository organization or username (non-empty).
   * `name` (`string`, mandatory): Repository name (non-empty).
3. **`baseCommit`** (`string`, mandatory): Target Git commit SHA representing the parent/base state of the codebase.
4. **`environment`** (`object`, mandatory):
   * `image` (`string`, mandatory): The container image reference pinned strictly by SHA-256 digest: `<image-reference>@sha256:<64 lowercase hex characters>` (e.g. `node:20-alpine@sha256:a1b2c3d4...`). Mutable tags (e.g. `:latest`) are prohibited.
5. **`criteria`** (`array`, mandatory): Non-empty array of criteria objects, each with a unique `id` string and boolean `required` flag.

### 2.2 Canonicalization and On-Chain Commitment

Before on-chain bounty creation, the JSON specification is canonicalized using RFC 8785 (JSON Canonicalization Scheme - JCS) to eliminate whitespace and key-order ambiguity:

$$\text{specHash} = \text{Keccak-256}(\text{RFC8785}(\text{specification}))$$

The resulting 32-byte hash (`bytes32`) is committed to the smart contract via `createBounty(specHash, submissionDeadline)`.

---

## 3. Submitted Work Artifact

* **Work Identifier**: A single Git commit SHA-1 (`bytes20 commitHash`).
* **Protocol Handling**: The smart contract stores `commitHash` as an opaque 20-byte value.
* **Repository Checkout**: The verifier pulls the specified repository (`repository.owner/repository.name`) and checks out the exact submitted `commitHash`.

---

## 4. Verification Execution Environment

Verification must execute inside an isolated OCI/Docker container initialized from the pinned `environment.image` digest:

1. **Image Verification**: Verifier must pull and verify the exact SHA-256 image digest.
2. **Process Isolation**: Execution occurs in an isolated sandbox with restricted resources (memory limit, CPU quota, execution timeout).
3. **Network Constraints**: Network access may be restricted to prevent external data leaks or non-deterministic remote calls during test execution.
4. **Deterministic Initialization**: The repository is cloned, and the submitted commit is checked out cleanly without local dirty artifacts.

---

## 5. Standard Verification Criteria

TrustBounty v0.1 defines exactly three criterion types:

### 5.1 BUILD Criterion
* **Schema**:
  ```json
  {
    "id": "build-step",
    "type": "BUILD",
    "command": "npm run build",
    "required": true
  }
  ```
* **Evaluation**: The verifier executes `command` in the container working directory.
* **Pass Condition**: Process terminates with exit code `0`.
* **Fail Condition**: Non-zero exit code or compilation error.

### 5.2 TEST Criterion
* **Schema**:
  ```json
  {
    "id": "test-suite",
    "type": "TEST",
    "command": "npm test",
    "required": true
  }
  ```
* **Evaluation**: The verifier executes `command` in the container working directory.
* **Pass Condition**: Process terminates with exit code `0` (all test cases passing).
* **Fail Condition**: Non-zero exit code, test assertion failure, unhandled exception, or test runner crash.

### 5.3 COVERAGE Criterion
* **Schema**:
  ```json
  {
    "id": "coverage-check",
    "type": "COVERAGE",
    "operator": ">=",
    "thresholdBps": 8500,
    "required": true
  }
  ```
* **Evaluation**: Verifier parses generated coverage reports (e.g. LCOV / Istanbul) and extracts total line/branch coverage percentage.
* **Format**: Basis points integer where $100 \text{ bps} = 1.00\%$ ($8500 = 85.00\%$, range: $0$ to $10000$).
* **Pass Condition**: Measured coverage basis points $\ge \text{thresholdBps}$.
* **Fail Condition**: Measured coverage basis points $< \text{thresholdBps}$ or missing coverage report.

---

## 6. Execution Evidence & `evidenceHash`

### 6.1 Evidence Collection
During execution, the verifier captures a structured execution transcript:
* Runtime metadata (timestamp, container image digest, verifier address, Git commit).
* Per-criterion stdout, stderr, exit codes, and execution duration.
* Extracted coverage summary metrics.
* Off-chain log storage reference (e.g. IPFS URI, Swarm, S3/HTTPS URL).

### 6.2 Evidence Hash Commitment
The canonical JSON transcript is hashed using Keccak-256:

$$\text{evidenceHash} = \text{Keccak-256}(\text{RFC8785}(\text{evidenceTranscript}))$$

This 32-byte `evidenceHash` is submitted on-chain with `reportVerification()` and `reportV2()`.

### 6.3 What `evidenceHash` Proves and Does NOT Prove

* **What it Proves**: Provides a tamper-evident cryptographic trail proving that the off-chain log file made available to counterparties matches the exact transcript generated during the oracle's verification run.
* **What it Does NOT Prove**: It does NOT prove that the oracle executed the container honestly or without tampering. Oracle honesty remains a protocol trust assumption, bounded by symmetric challenge mechanisms and dual-oracle redundancy.

---

## 7. Outcome Classification

Verifiers categorize outcomes into four enumeration values:

| Outcome | Enum ID | Meaning | On-Chain Transition (V1) | On-Chain Transition (V2) |
| :--- | :---: | :--- | :--- | :--- |
| **`NONE`** | 0 | Unreported / Initial state. | N/A (Reverts on report) | N/A (Reverts on report) |
| **`PASS`** | 1 | All required criteria met. | `VERIFYING → REPORTED` | `DISPUTED → SETTLED` |
| **`FAIL`** | 2 | One or more criteria failed legitimately. | `VERIFYING → REPORTED` | `DISPUTED → REFUNDED` |
| **`ERROR`** | 3 | Container runtime crash, infrastructure failure, or timeout. | `VERIFYING → DISPUTED` (0 bond) | N/A (V2 rejects non-binary) |
| **`INCONCLUSIVE`** | 4 | Flaky tests, ambiguous metric parsing, or non-deterministic execution. | `VERIFYING → DISPUTED` (0 bond) | N/A (V2 rejects non-binary) |

---

## 8. Verifier Roles & Execution Workflows

### 8.1 Primary Verifier (V1)
1. **Claiming**: Listens for `WorkSubmitted` event. Invokes `claimVerification(bountyId)` while `block.timestamp < claimDeadline`.
2. **Execution**: Clones repository, checks out `commitHash`, runs criteria in the container, and captures logs.
3. **Reporting**:
   * If `PASS` or `FAIL`: Calls `reportVerification(bountyId, outcome, evidenceHash)` setting `state = REPORTED`.
   * If `ERROR` or `INCONCLUSIVE`: Calls `reportVerification(bountyId, outcome, evidenceHash)` setting `state = DISPUTED` (`origin = V1_ERROR` or `V1_INCONCLUSIVE`).
4. **Timeout**: If V1 fails to claim before `claimDeadline` (`expireClaim()`) or fails to report before `verificationDeadline` (`timeoutV1()`), the bounty escalates directly to `DISPUTED`. V1 permanently loses authority.

### 8.2 Secondary Verifier (V2)
1. **Trigger**: Listens for `DisputeInitiated`, `ClaimExpired`, `VerificationTimeout`, or `VerificationReported` (with `ERROR`/`INCONCLUSIVE`).
2. **Re-Execution**: Performs independent containerized execution against the committed specification.
3. **Binding Determination**: Invokes `reportV2(bountyId, outcome, evidenceHash)` with strictly `Outcome.PASS` or `Outcome.FAIL`.
4. **Timeout Fallback**: If V2 does not report within `T_v2`, `finalizeV2Timeout()` executes deterministic fallback resolution based on `disputeOrigin`.
