# TrustBounty Acceptance Specification

## Purpose

The TrustBounty Acceptance Specification defines the machine-readable requirements that a pull request or contribution must satisfy to qualify for bounty payout. By formalizing acceptance criteria into an unambiguous, verifiable data structure, TrustBounty ensures objective evaluation of submitted work.

## Specification Lifecycle

1. **Authoring**: The bounty sponsor defines the repository context, target base commit, and verification criteria.
2. **Validation**: The specification is validated against protocol rules, ensuring schema conformity, unambiguous criteria IDs, and valid thresholds.
3. **Canonicalization**: The validated specification is serialized using RFC 8785 JSON Canonicalization Scheme (JCS) to eliminate formatting ambiguity.
4. **Commitment**: The canonical representation is hashed using Ethereum-compatible Keccak-256 (`specHash`).
5. **On-Chain Commitment**: The resulting `specHash` is submitted during bounty initialization on-chain prior to bounty activation.
6. **Verification (Future)**: Evaluation environments execute the committed criteria against submitted pull requests.

## Schema

Acceptance specifications conform to the v1.0 schema:

```json
{
  "version": "1.0",
  "repository": {
    "owner": "string",
    "name": "string"
  },
  "baseCommit": "string",
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

export interface AcceptanceSpecification {
  version: '1.0';
  repository: RepositoryRef;
  baseCommit: string;
  criteria: AcceptanceCriterion[];
}
```

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
  - `operator`: The comparison operator. Only `>=` is supported in v1.0.
  - `thresholdBps`: Non-negative integer representing basis points where 100 bps = 1.00% (e.g., `8000` = 80.00%, maximum `10000` = 100.00%). Floating-point numbers and negative values are strictly prohibited.
  - `required`: Boolean flag indicating if passing this criterion is mandatory.

## Canonicalization

Canonicalization uses RFC 8785 (JSON Canonicalization Scheme - JCS). 

- Object keys are sorted lexicographically by their UTF-16 code units.
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
- **Integrity**: The hash is an integrity and commitment mechanism. It guarantees that the specification cannot be altered without changing the hash; it is not proof that the specification is fair, correct, or achievable.

## Immutability Requirement

The acceptance specification must be committed before bounty activation. Once a bounty is activated, the acceptance criteria are fixed. Any modification to acceptance criteria requires the cancellation or expiration of the existing bounty and the creation of a new bounty with a new specification commitment.

*Note*: Cryptographic enforcement of bounty immutability is handled by the TrustBounty smart contract protocol in a later milestone, not by this TypeScript foundation module.

## Validation Rules

Validators strictly enforce the following constraints:
1. **Root**: Must be a non-null, non-array object.
2. **Version**: Must equal `"1.0"` exactly.
3. **Repository**: Must be a non-null object with non-empty string fields `owner` and `name`.
4. **Base Commit**: Must be a non-empty string identifying the target Git commit.
5. **Criteria**: Must be an array containing at least one criterion.
6. **Criterion ID**: Must be a non-empty string and unique across all criteria in the specification.
7. **Criterion Type**: Must be one of `BUILD`, `TEST`, or `COVERAGE`.
8. **Commands**: For `BUILD` and `TEST`, `command` must be a non-empty string.
9. **Coverage Operator**: For `COVERAGE`, `operator` must be `>=`.
10. **Coverage Threshold**: For `COVERAGE`, `thresholdBps` must be an integer between 0 and 10000.
11. **Required Flag**: Each criterion must explicitly set `required` as a boolean.

Validation errors clearly identify the invalid field path and error rationale. Validation is pure, performing no silent mutations or repairs.

## Current Limitations

- Only three criterion types are supported: `BUILD`, `TEST`, and `COVERAGE`.
- Coverage comparisons only support the `>=` operator.
- Execution environment constraints, container images, resource limits, and timeouts are out of scope for v1.0 specification models.
- Cryptographic on-chain binding is not enforced in this module and will be handled by the smart contract milestone.

## Future Extensions

- Additional criterion types (e.g., LINT, BENCHMARK, STATIC_ANALYSIS, CUSTOM_SCRIPT).
- Multi-metric coverage thresholds (e.g., branch, line, and function coverage specifications).
- Environment and toolchain specification hashes (e.g., container image digest, runtime versions).
- Dynamic parameter matrices for multi-platform test suites.
