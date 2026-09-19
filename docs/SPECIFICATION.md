# TrustBounty Acceptance Specification

## Purpose

The TrustBounty Acceptance Specification defines the machine-readable requirements that a pull request or contribution must satisfy to qualify for bounty payout. By formalizing acceptance criteria into an unambiguous, verifiable data structure, TrustBounty ensures objective evaluation of submitted work.

## Specification Lifecycle

1. **Authoring (Off-Chain)**: The bounty sponsor defines the repository context, target base commit, execution environment, and verification criteria.
2. **Validation (Off-Chain Tooling)**: The specification is validated against protocol rules, ensuring schema conformity, immutable environment digest, unambiguous criteria IDs, and valid thresholds.
3. **Canonicalization (Off-Chain Tooling)**: The validated specification is serialized using RFC 8785 JSON Canonicalization Scheme (JCS) to eliminate formatting ambiguity.
4. **Commitment Calculation (Off-Chain Tooling)**: The canonical representation is hashed using Ethereum-compatible Keccak-256 (`specHash`).
5. **On-Chain Commitment (Implemented Now in TrustBounty.sol)**: The resulting 32-byte hash is submitted as `specHash` during `createBounty()` on-chain. The contract stores this hash immutably as an opaque commitment without parsing or validating the underlying JSON specification.
6. **Verification (Planned / Phase 2)**: Evaluation environments execute the committed criteria within the designated immutable container image against submitted pull requests.

## Schema

Acceptance specifications conform to the v1.1 schema:

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

### TypeScript Definition

```typescript
export type CriterionType = 'BUILD' | 'TEST' | 'COVERAGE';

export interface BuildCriterion {
  id: string;
  type: 'BUILD';
  command: string;
  required: boolean;
}

export interface TestCriterion {
  id: string;
  type: 'TEST';
  command: string;
  required: boolean;
}

export interface CoverageCriterion {
  id: string;
  type: 'COVERAGE';
  operator: '>=';
  thresholdBps: number;
  required: boolean;
}

export type AcceptanceCriterion = BuildCriterion | TestCriterion | CoverageCriterion;

export interface RepositoryRef {
  owner: string;
  name: string;
}

export interface ExecutionEnvironment {
  image: string;
}

export interface AcceptanceSpecification {
  version: '1.1';
  repository: RepositoryRef;
  baseCommit: string;
  environment: ExecutionEnvironment;
  criteria: AcceptanceCriterion[];
}
```

## Environment Semantics

The `environment` object specifies the immutable runtime container image in which criteria verification must take place.

- **Field**: `image` (string, required).
- **Format**: Must follow `<image-reference>@sha256:<64 lowercase hexadecimal characters>`.
- **Immutability**: Image references must be pinned to a cryptographic sha256 digest rather than a mutable tag (e.g. `:latest` or `:22`), ensuring immutable image distribution. Note that while digest pinning binds container rootfs and configuration bits, absolute execution reproducibility across distinct hosts also depends on host kernel version, CPU architecture, memory/scheduler constraints, and container runtime flags.
- **Validation Scope**: Validation checks digest syntax purely offline without performing network calls or registry lookups.

## Criterion Semantics

### BUILD
- **Purpose**: Verifies that the codebase builds cleanly from source with the contribution applied.
- **Fields**:
  - `command`: Non-empty execution string (e.g., `npm run build`).
  - `required`: Boolean flag indicating if passing this criterion is mandatory.

### TEST
- **Purpose**: Verifies that test suites pass without regression or failure.
- **Fields**:
  - `command`: Non-empty execution string (e.g., `npm test`).
  - `required`: Boolean flag indicating if passing this criterion is mandatory.

### COVERAGE
- **Purpose**: Verifies that automated code coverage meets or exceeds a target threshold.
- **Fields**:
  - `operator`: The comparison operator. Only `>=` is supported in v1.1.
  - `thresholdBps`: Non-negative integer representing basis points where 100 bps = 1.00% (e.g., `8000` = 80.00%, maximum `10000` = 100.00%). Floating-point numbers and negative values are strictly prohibited.
  - `required`: Boolean flag indicating if passing this criterion is mandatory.

## Canonicalization

Canonicalization uses RFC 8785 (JSON Canonicalization Scheme - JCS). 

- Object keys are sorted lexicographically by their UTF-16 code units (e.g., `baseCommit` < `criteria` < `environment` < `repository` < `version`).
- Insignificant whitespace (spaces, tabs, newlines) outside string literals is omitted.
- Numbers and strings are serialized deterministically per RFC 8785 rules.
- Input data structures are never mutated during canonicalization.

Canonicalization guarantees that any two semantically identical JSON specifications produce identical byte sequences, regardless of original formatting or key order.

## Commitment

The cryptographic commitment is calculated as:

```text
specHash = Keccak-256(RFC8785(specification))
```

- **Algorithm**: Keccak-256 (standard Ethereum cryptographic primitive, distinct from NIST FIPS 202 SHA3-256).
- **Format**: Normalized lowercase `0x`-prefixed 32-byte hexadecimal string (64 hex characters following `0x`).
- **Determinism**: Identical specifications always produce identical hashes.
- **Integrity**: The hash is an integrity and commitment mechanism. It guarantees that the specification (including environment, criteria, and base commit) cannot be altered without changing the hash; it is not proof that the specification is fair, correct, or achievable.

## Immutability Requirement

The acceptance specification must be committed before bounty activation. Once a bounty is created, the acceptance criteria hash and bounty parameters are fixed in contract storage. Any modification to acceptance criteria requires creating a new bounty with a new specification commitment.

*Note*: In TrustBounty v0.1, the smart contract (`TrustBounty.sol`) stores the `specHash` immutably upon `createBounty()`. The contract treats `specHash` as an opaque `bytes32` value and does not inspect, parse, or validate the JSON specification on-chain; validation and JCS canonicalization are performed entirely by off-chain tooling.

## Validation Rules

Validators strictly enforce a closed schema with the following constraints:
1. **Root**: Must be a non-null, non-array object. Only allowed keys: `version`, `repository`, `baseCommit`, `environment`, `criteria`.
2. **Version**: Must equal `"1.1"` exactly.
3. **Repository**: Must be a non-null object. Only allowed keys: `owner`, `name` (both non-empty strings).
4. **Base Commit**: Must be a non-empty string identifying the target Git commit.
5. **Environment**: Must be a non-null object. Only allowed key: `image`. The `image` must be a non-empty string matching `<image-reference>@sha256:<64 lowercase hex characters>`.
6. **Criteria**: Must be an array containing at least one criterion.
7. **Criterion ID**: Must be a non-empty string and unique across all criteria in the specification.
8. **Criterion Type**: Must be one of `BUILD`, `TEST`, or `COVERAGE`.
9. **Commands**: For `BUILD` and `TEST`, `command` must be a non-empty string. Allowed keys: `id`, `type`, `command`, `required`.
10. **Coverage Operator**: For `COVERAGE`, `operator` must be `>=`. Allowed keys: `id`, `type`, `operator`, `thresholdBps`, `required`.
11. **Coverage Threshold**: For `COVERAGE`, `thresholdBps` must be an integer between 0 and 10000.
12. **Required Flag**: Each criterion must explicitly set `required` as a boolean.

Validation errors clearly identify the invalid field path and error rationale. Validation is pure, performing no silent mutations or repairs.

## Current Limitations

- Only three criterion types are supported: `BUILD`, `TEST`, and `COVERAGE`.
- Coverage comparisons only support the `>=` operator.
- Execution environment specifications support a single container image digest; multi-stage environments, resource limits, and timeouts are out of scope for v1.1.
- On-chain contracts bind the specification via opaque `bytes32 specHash` only; semantic verification of criteria against PRs is executed off-chain by verifier daemons (Planned / Phase 2).

## Future Extensions

- Additional criterion types (e.g., LINT, BENCHMARK, STATIC_ANALYSIS, CUSTOM_SCRIPT).
- Multi-metric coverage thresholds (e.g., branch, line, and function coverage specifications).
- Extended environment specifications (resource constraints, CPU/memory limits, timeouts, multi-container setups).
- Dynamic parameter matrices for multi-platform test suites.
