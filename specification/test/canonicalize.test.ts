import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalizeSpecification } from '../src/canonicalize.ts';
import type { AcceptanceSpecification } from '../src/types.ts';

test('canonicalizeSpecification: produces identical output for semantically equivalent key ordering', () => {
  // Input A and Input B from RFC requirement adapted with a valid criterion
  const inputA = {
    version: '1.0',
    repository: {
      owner: 'x',
      name: 'y',
    },
    baseCommit: 'abc',
    criteria: [
      {
        id: 'BUILD-001',
        type: 'BUILD',
        command: 'npm run build',
        required: true,
      },
    ],
  };

  const inputB = {
    criteria: [
      {
        required: true,
        command: 'npm run build',
        type: 'BUILD',
        id: 'BUILD-001',
      },
    ],
    baseCommit: 'abc',
    repository: {
      name: 'y',
      owner: 'x',
    },
    version: '1.0',
  };

  const canonicalA = canonicalizeSpecification(inputA);
  const canonicalB = canonicalizeSpecification(inputB);

  assert.strictEqual(canonicalA, canonicalB);

  // Verify exact RFC 8785 lexicographical key ordering (baseCommit < criteria < repository < version)
  const expectedPrefix = '{"baseCommit":"abc","criteria":[{"command":"npm run build","id":"BUILD-001","required":true,"type":"BUILD"}],"repository":{"name":"y","owner":"x"},"version":"1.0"}';
  assert.strictEqual(canonicalA, expectedPrefix);
});

test('canonicalizeSpecification: whitespace invariance across parsed equivalents', () => {
  const jsonStringA = '{"version":"1.0","repository":{"owner":"x","name":"y"},"baseCommit":"abc","criteria":[{"id":"TEST-001","type":"TEST","command":"npm test","required":true}]}';
  const jsonStringB = `{
    "version":  "1.0" ,
    "repository": {
      "owner": "x",
      "name": "y"
    },
    "baseCommit": "abc",
    "criteria": [
      {
        "id": "TEST-001",
        "type": "TEST",
        "command": "npm test",
        "required": true
      }
    ]
  }`;

  const specA = JSON.parse(jsonStringA) as AcceptanceSpecification;
  const specB = JSON.parse(jsonStringB) as AcceptanceSpecification;

  const canonicalA = canonicalizeSpecification(specA);
  const canonicalB = canonicalizeSpecification(specB);

  assert.strictEqual(canonicalA, canonicalB);
});

test('canonicalizeSpecification: deterministic repeated calls', () => {
  const spec: AcceptanceSpecification = {
    version: '1.0',
    repository: { owner: 'org', name: 'repo' },
    baseCommit: 'commit123',
    criteria: [
      {
        id: 'COV-001',
        type: 'COVERAGE',
        operator: '>=',
        thresholdBps: 8500,
        required: true,
      },
    ],
  };

  const first = canonicalizeSpecification(spec);
  const second = canonicalizeSpecification(spec);
  const third = canonicalizeSpecification(spec);

  assert.strictEqual(first, second);
  assert.strictEqual(second, third);
});

test('canonicalizeSpecification: does not mutate input object', () => {
  const spec: AcceptanceSpecification = {
    version: '1.0',
    repository: { owner: 'org', name: 'repo' },
    baseCommit: 'commit123',
    criteria: [
      {
        id: 'BUILD-001',
        type: 'BUILD',
        command: 'make',
        required: true,
      },
    ],
  };

  const copy = JSON.parse(JSON.stringify(spec));
  canonicalizeSpecification(spec);
  assert.deepStrictEqual(spec, copy);
});

test('canonicalizeSpecification: rejects invalid specification', () => {
  const invalidSpec = {
    version: '2.0',
    repository: { owner: '', name: '' },
    baseCommit: '',
    criteria: [],
  };

  assert.throws(() => {
    canonicalizeSpecification(invalidSpec);
  }, TypeError);
});
