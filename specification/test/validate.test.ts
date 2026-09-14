import test from 'node:test';
import assert from 'node:assert/strict';
import { validateSpecification } from '../src/validate.ts';
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
      {
        id: 'TEST-001',
        type: 'TEST',
        command: 'npm test',
        required: true,
      },
      {
        id: 'COVERAGE-001',
        type: 'COVERAGE',
        operator: '>=',
        thresholdBps: 8000,
        required: true,
      },
    ],
  };
}

test('validateSpecification: accepts valid specification', () => {
  const spec = createValidSpec();
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, true);
  if (result.valid) {
    assert.deepStrictEqual(result.specification, spec);
  }
});

test('validateSpecification: rejects non-object input', () => {
  assert.strictEqual(validateSpecification(null).valid, false);
  assert.strictEqual(validateSpecification('invalid').valid, false);
  assert.strictEqual(validateSpecification(123).valid, false);
  assert.strictEqual(validateSpecification([]).valid, false);
});

test('validateSpecification: rejects invalid version (including v1.0)', () => {
  const spec2 = { ...createValidSpec(), version: '2.0' };
  const result2 = validateSpecification(spec2);
  assert.strictEqual(result2.valid, false);
  if (!result2.valid) {
    assert.ok(result2.errors.some((e) => e.path === 'version'));
  }

  const spec1 = { ...createValidSpec(), version: '1.0' };
  const result1 = validateSpecification(spec1);
  assert.strictEqual(result1.valid, false);
  if (!result1.valid) {
    assert.ok(result1.errors.some((e) => e.path === 'version'));
  }
});

test('validateSpecification: rejects empty owner', () => {
  const spec = createValidSpec();
  spec.repository.owner = '';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'repository.owner'));
  }
});

test('validateSpecification: rejects empty repository name', () => {
  const spec = createValidSpec();
  spec.repository.name = '   ';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'repository.name'));
  }
});

test('validateSpecification: rejects missing baseCommit', () => {
  const spec = createValidSpec();
  // @ts-expect-error testing missing field
  delete spec.baseCommit;
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'baseCommit'));
  }
});

test('validateSpecification: rejects empty criteria array', () => {
  const spec = createValidSpec();
  spec.criteria = [];
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'criteria'));
  }
});

test('validateSpecification: rejects duplicate criterion IDs', () => {
  const spec = createValidSpec();
  spec.criteria.push({
    id: 'BUILD-001',
    type: 'BUILD',
    command: 'npm run build:prod',
    required: false,
  });
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path.includes('id') && e.message.includes('Duplicate')));
  }
});

test('validateSpecification: rejects unknown criterion type', () => {
  const spec = createValidSpec();
  // @ts-expect-error testing unknown type
  spec.criteria[0].type = 'SECURITY_AUDIT';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'criteria[0].type'));
  }
});

test('validateSpecification: rejects missing command for BUILD/TEST', () => {
  const spec = createValidSpec();
  // @ts-expect-error testing empty command
  spec.criteria[0].command = '';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'criteria[0].command'));
  }
});

test('validateSpecification: rejects invalid coverage operator', () => {
  const spec = createValidSpec();
  // @ts-expect-error testing invalid operator
  spec.criteria[2].operator = '>';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'criteria[2].operator'));
  }
});

test('validateSpecification: rejects negative coverage threshold', () => {
  const spec = createValidSpec();
  // @ts-expect-error testing negative threshold
  spec.criteria[2].thresholdBps = -1;
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'criteria[2].thresholdBps'));
  }
});

test('validateSpecification: rejects threshold > 10000', () => {
  const spec = createValidSpec();
  // @ts-expect-error testing threshold > 10000
  spec.criteria[2].thresholdBps = 10001;
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'criteria[2].thresholdBps'));
  }
});

test('validateSpecification: rejects non-integer threshold', () => {
  const spec = createValidSpec();
  // @ts-expect-error testing float threshold
  spec.criteria[2].thresholdBps = 8000.5;
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'criteria[2].thresholdBps'));
  }
});

test('validateSpecification: does not mutate input object', () => {
  const spec = createValidSpec();
  const frozen = JSON.parse(JSON.stringify(spec));
  validateSpecification(spec);
  assert.deepStrictEqual(spec, frozen);
});

test('validateSpecification: rejects unknown field at top level', () => {
  const spec = {
    ...createValidSpec(),
    extraField: 'unexpected',
  };
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'extraField'));
  }
});

test('validateSpecification: rejects unknown field in repository', () => {
  const spec = createValidSpec();
  (spec.repository as unknown as Record<string, unknown>).extraField = 'unexpected';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'repository.extraField'));
  }
});

test('validateSpecification: rejects unknown field in BUILD criterion', () => {
  const spec = createValidSpec();
  (spec.criteria[0] as unknown as Record<string, unknown>).extraField = 'unexpected';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'criteria[0].extraField'));
  }
});

test('validateSpecification: rejects unknown field in TEST criterion', () => {
  const spec = createValidSpec();
  (spec.criteria[1] as unknown as Record<string, unknown>).extraField = 'unexpected';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'criteria[1].extraField'));
  }
});

test('validateSpecification: rejects unknown field in COVERAGE criterion', () => {
  const spec = createValidSpec();
  (spec.criteria[2] as unknown as Record<string, unknown>).extraField = 'unexpected';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'criteria[2].extraField'));
  }
});

test('validateSpecification: rejects missing environment', () => {
  const spec = createValidSpec();
  // @ts-expect-error testing missing environment
  delete spec.environment;
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'environment'));
  }
});

test('validateSpecification: rejects non-object environment', () => {
  const specNull = { ...createValidSpec(), environment: null };
  const resultNull = validateSpecification(specNull);
  assert.strictEqual(resultNull.valid, false);
  if (!resultNull.valid) {
    assert.ok(resultNull.errors.some((e) => e.path === 'environment'));
  }

  const specArray = { ...createValidSpec(), environment: [] };
  const resultArray = validateSpecification(specArray);
  assert.strictEqual(resultArray.valid, false);
  if (!resultArray.valid) {
    assert.ok(resultArray.errors.some((e) => e.path === 'environment'));
  }
});

test('validateSpecification: rejects empty environment image', () => {
  const spec = createValidSpec();
  spec.environment.image = '   ';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'environment.image'));
  }
});

test('validateSpecification: rejects image without immutable digest', () => {
  const spec1 = createValidSpec();
  spec1.environment.image = 'node:22';
  assert.strictEqual(validateSpecification(spec1).valid, false);

  const spec2 = createValidSpec();
  spec2.environment.image = 'docker.io/library/node:22';
  assert.strictEqual(validateSpecification(spec2).valid, false);
});

test('validateSpecification: rejects image with truncated digest', () => {
  const spec = createValidSpec();
  spec.environment.image = 'docker.io/library/node@sha256:abc';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'environment.image'));
  }
});

test('validateSpecification: rejects image with uppercase hex digest', () => {
  const spec = createValidSpec();
  spec.environment.image = 'docker.io/library/node@sha256:0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'environment.image'));
  }
});

test('validateSpecification: rejects unknown field in environment', () => {
  const spec = createValidSpec();
  (spec.environment as unknown as Record<string, unknown>).extraField = 'unexpected';
  const result = validateSpecification(spec);
  assert.strictEqual(result.valid, false);
  if (!result.valid) {
    assert.ok(result.errors.some((e) => e.path === 'environment.extraField'));
  }
});
