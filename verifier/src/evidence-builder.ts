/**
 * TrustBounty Phase 2B-2: Evidence Builder & Cryptographic Commitment.
 *
 * Implements:
 * 1. Keccak-256 stream & artifact hashing with empty-stream support.
 * 2. Canonical decimal bountyId validation.
 * 3. Sorting invariant for manifest criteria (UTF-16 ascending by id).
 * 4. RFC 8785 JSON Canonicalization Scheme (JCS).
 * 5. evidenceHash computation: Keccak-256(RFC8785(CanonicalEvidenceManifest)).
 */

import { createRequire } from 'node:module';
import type {
  CanonicalEvidenceManifest,
  CriterionEvidenceRecord,
  ManifestVerdict,
} from './evidence-types.ts';

const require = createRequire(import.meta.url);

// Reuse the existing canonicalization and keccak256 stack from specification
const rawCanonicalize = require('../../specification/node_modules/canonicalize');
const canonicalizeFn: (obj: unknown) => string | undefined =
  typeof rawCanonicalize === 'function' ? rawCanonicalize : rawCanonicalize.default;

const { keccak256 }: { keccak256: (data: string | Buffer | Uint8Array) => string } =
  require('../../specification/node_modules/js-sha3');

/**
 * Standard Keccak-256 digest of an empty byte array (0 bytes).
 */
export const EMPTY_BYTES_KECCAK256 =
  '0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470';

/**
 * Validates that a string is a canonical decimal representation of an on-chain uint256.
 *
 * Rules:
 * - Must be a string.
 * - Must contain only decimal digits.
 * - "0" is valid, but leading zeros on non-zero numbers are invalid (e.g. "01" is invalid).
 * - Floating point, signs, hex prefix ("0x"), or exponent notation are forbidden.
 */
export function validateCanonicalDecimalBountyId(bountyId: unknown): string {
  if (typeof bountyId !== 'string') {
    throw new TypeError(
      `bountyId must be a decimal string, received ${typeof bountyId}: ${String(bountyId)}`
    );
  }

  if (!/^(0|[1-9][0-9]*)$/.test(bountyId)) {
    throw new TypeError(
      `bountyId must be a canonical decimal string without leading zeros or signs, received: "${bountyId}"`
    );
  }

  return bountyId;
}

/**
 * Computes the normalized lowercase Keccak-256 digest for raw binary data or string.
 *
 * Output: "0x" + 64 lowercase hexadecimal characters.
 */
export function computeKeccak256Digest(data: Buffer | Uint8Array | string): string {
  if (typeof data === 'string') {
    if (data.length === 0) {
      return EMPTY_BYTES_KECCAK256;
    }
    return `0x${keccak256(data).toLowerCase()}`;
  }

  if (data.length === 0) {
    return EMPTY_BYTES_KECCAK256;
  }

  return `0x${keccak256(data).toLowerCase()}`;
}

/**
 * Produces an RFC 8785 JSON Canonicalization Scheme (JCS) string representation
 * of the CanonicalEvidenceManifest.
 */
export function canonicalizeManifest(manifest: CanonicalEvidenceManifest): string {
  const result = canonicalizeFn(manifest);
  if (result === undefined) {
    throw new Error('Canonicalization produced undefined output');
  }
  return result;
}

/**
 * Computes the cryptographic commitment (evidenceHash) of a CanonicalEvidenceManifest.
 *
 * Formula:
 *   evidenceHash = "0x" + Keccak-256(RFC8785(CanonicalEvidenceManifest))
 *
 * Output: normalized lowercase "0x" + 64 hex characters.
 */
export function computeEvidenceHash(manifest: CanonicalEvidenceManifest): string {
  const canonicalJson = canonicalizeManifest(manifest);
  const digest = keccak256(Buffer.from(canonicalJson, 'utf-8')).toLowerCase();
  return `0x${digest}`;
}

export interface BuildCanonicalManifestParams {
  specHash: string;
  bountyId: string;
  repository: {
    owner: string;
    name: string;
  };
  baseCommit: string;
  submittedCommit: string;
  environment: {
    image: string;
    platform: 'linux/amd64';
  };
  criteria: CriterionEvidenceRecord[];
  overallVerdict: ManifestVerdict;
  overallVerdictReason?: string;
  verifierVersion?: string;
}

/**
 * Constructs a CanonicalEvidenceManifest from verified components.
 *
 * Invariants enforced:
 * 1. schemaVersion is strictly "1.0".
 * 2. bountyId is verified as canonical decimal string.
 * 3. criteria are sorted ascending by criterion id using UTF-16 code units.
 *    Input criteria array is never mutated (creates a new sorted array).
 * 4. verifierVersion defaults to "0.1.0".
 */
export function buildCanonicalManifest(
  params: BuildCanonicalManifestParams
): CanonicalEvidenceManifest {
  const bountyId = validateCanonicalDecimalBountyId(params.bountyId);

  // Validate specHash format
  if (!/^0x[0-9a-f]{64}$/.test(params.specHash)) {
    throw new TypeError(`Invalid specHash format: "${params.specHash}"`);
  }

  // Validate commit hashes
  if (!/^[0-9a-f]{40}$/i.test(params.baseCommit)) {
    throw new TypeError(`Invalid baseCommit hash: "${params.baseCommit}"`);
  }
  if (!/^[0-9a-f]{40}$/i.test(params.submittedCommit)) {
    throw new TypeError(`Invalid submittedCommit hash: "${params.submittedCommit}"`);
  }

  // Create a sorted copy of criteria by id (UTF-16 code units ascending)
  const sortedCriteria: CriterionEvidenceRecord[] = [...params.criteria].sort((a, b) =>
    a.id < b.id ? -1 : a.id > b.id ? 1 : 0
  );

  const manifest: CanonicalEvidenceManifest = {
    schemaVersion: '1.0',
    specHash: params.specHash,
    bountyId,
    repository: {
      owner: params.repository.owner,
      name: params.repository.name,
    },
    baseCommit: params.baseCommit.toLowerCase(),
    submittedCommit: params.submittedCommit.toLowerCase(),
    environment: {
      image: params.environment.image,
      platform: params.environment.platform,
    },
    criteria: sortedCriteria,
    overallVerdict: params.overallVerdict,
    verifierVersion: params.verifierVersion ?? '0.1.0',
  };

  if (params.overallVerdictReason !== undefined) {
    manifest.overallVerdictReason = params.overallVerdictReason;
  }

  return manifest;
}
