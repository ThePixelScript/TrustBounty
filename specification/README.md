# Acceptance Specification

## Purpose

This module represents machine-readable bounty acceptance requirements within the TrustBounty protocol. It provides strict validation, deterministic RFC 8785 canonicalization, and cryptographic commitment generation for acceptance specifications.

## Supported Version

v1.1

## Supported Criteria

- BUILD
- TEST
- COVERAGE

## Validation

Input specifications undergo strict structural and semantic validation:
- Root must be a non-null object with version `"1.1"`.
- `repository` must specify non-empty `owner` and `name` strings.
- `baseCommit` must be a non-empty string.
- `environment` must be a non-null object containing an immutable `image` reference digest (`<image-reference>@sha256:<64 lowercase hex characters>`).
- `criteria` must be a non-empty array with unique criterion identifiers.
- `BUILD` and `TEST` criteria require a non-empty `command` string.
- `COVERAGE` criteria require the `>=` operator and an integer `thresholdBps` between 0 and 10000 basis points (rejecting floating-point and negative values).
- All criteria require a boolean `required` flag.
- Closed schema: any unknown field at top level, repository, environment, or criterion level is strictly rejected.
- Any malformed structure, unknown criterion type, missing field, empty string, or duplicate ID is rejected without silent repair or input mutation.

## Canonicalization

RFC 8785 JSON Canonicalization Scheme (JCS) is used to produce a deterministic UTF-8 JSON representation. Semantically identical specifications with differing key orders or whitespace yield identical canonical outputs.

## Commitment

```text
specHash = Keccak-256(RFC8785(specification))
```

The specification commitment is computed as an Ethereum-compatible Keccak-256 hash over the RFC 8785 canonical JSON bytes, formatted as a lowercase `0x`-prefixed 32-byte hexadecimal string.

The hash is a commitment/integrity mechanism, NOT proof that the specification is correct or fair.

## Example

```json
{
  "version": "1.1",
  "repository": {
    "owner": "example",
    "name": "project"
  },
  "baseCommit": "abc123",
  "environment": {
    "image": "docker.io/library/node@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  },
  "criteria": [
    {
      "id": "BUILD-001",
      "type": "BUILD",
      "command": "npm run build",
      "required": true
    },
    {
      "id": "TEST-001",
      "type": "TEST",
      "command": "npm test",
      "required": true
    },
    {
      "id": "COVERAGE-001",
      "type": "COVERAGE",
      "operator": ">=",
      "thresholdBps": 8000,
      "required": true
    }
  ]
}
```
