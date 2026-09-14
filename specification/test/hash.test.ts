import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { keccak256 } from 'js-sha3';
import { hashSpecification } from '../src/hash.ts';
import { canonicalizeSpecification } from '../src/canonicalize.ts';
import type { AcceptanceSpecification } from '../src/types.ts';

function createValidSpec(): AcceptanceSpecification {
  return {
    version: '1.1',
    repository: {
      owner: 'example',
      name: 'project',
    },
    baseCommit: 'abc123',
    environment: {
      image: 'docker.io/library/node@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    },
    criteria: [
      {
        id: 'BUILD-001',
        type: 'BUILD',
        command: 'npm run build',
        required: true,
      },
    ],
  };
}

test('hashSpecification: format is 0x-prefixed 64 lowercase hex characters', () => {
  const spec = createValidSpec();
  const hash = hashSpecification(spec);

  assert.ok(hash.startsWith('0x'), 'Hash must start with 0x');
  assert.strictEqual(hash.length, 66, 'Hash must be 66 characters long (0x + 64 hex chars)');
  assert.match(hash, /^0x[0-9a-f]{64}$/, 'Hash must contain exactly 64 lowercase hexadecimal characters');
});

test('hashSpecification: deterministic result for same specification', () => {
  const specA = createValidSpec();
  const specB = createValidSpec();

  const hashA = hashSpecification(specA);
  const hashB = hashSpecification(specB);

  assert.strictEqual(hashA, hashB);
});

test('hashSpecification: different specification produces different hash (sensitivity)', () => {
  const specA = createValidSpec();
  const specB: AcceptanceSpecification = {
    ...createValidSpec(),
    baseCommit: 'def456',
  };

  const hashA = hashSpecification(specA);
  const hashB = hashSpecification(specB);

  assert.notStrictEqual(hashA, hashB);
});

test('hashSpecification: different environment image produces different hash (environment sensitivity)', () => {
  const specA = createValidSpec();
  const specB: AcceptanceSpecification = {
    ...createValidSpec(),
    environment: {
      image: 'docker.io/library/node@sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
    },
  };

  const hashA = hashSpecification(specA);
  const hashB = hashSpecification(specB);

  assert.notStrictEqual(hashA, hashB);
});

test('hashSpecification: uses Ethereum Keccak-256, NOT NIST SHA3-256', () => {
  const spec = createValidSpec();
  const canonicalJson = canonicalizeSpecification(spec);
  const specHash = hashSpecification(spec);

  // Compute NIST SHA3-256 using Node's standard crypto library
  const nistSha3Hash = `0x${crypto.createHash('sha3-256').update(canonicalJson, 'utf8').digest('hex')}`;

  // Ethereum Keccak-256 and NIST SHA3-256 MUST differ
  assert.notStrictEqual(
    specHash,
    nistSha3Hash,
    'Ethereum Keccak-256 must not match NIST SHA3-256'
  );
});

test('hashSpecification: produces same hash regardless of key order', () => {
  const specA = {
    version: '1.1',
    repository: {
      owner: 'example',
      name: 'project',
    },
    baseCommit: 'abc123',
    environment: {
      image: 'docker.io/library/node@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    },
    criteria: [
      {
        id: 'BUILD-001',
        type: 'BUILD',
        command: 'npm run build',
        required: true,
      },
    ],
  };

  const specB = {
    criteria: [
      {
        command: 'npm run build',
        required: true,
        type: 'BUILD',
        id: 'BUILD-001',
      },
    ],
    environment: {
      image: 'docker.io/library/node@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    },
    baseCommit: 'abc123',
    version: '1.1',
    repository: {
      name: 'project',
      owner: 'example',
    },
  };

  const hashA = hashSpecification(specA);
  const hashB = hashSpecification(specB);

  assert.strictEqual(hashA, hashB);
});

test('keccak256: matches independent known test vector for empty string', () => {
  assert.strictEqual(
    keccak256(''),
    'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470'
  );
});

