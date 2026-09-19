/**
 * TrustBounty Phase 2B-2: Criterion Evaluation & Evidence Commitment Tests.
 *
 * Exhaustively tests:
 * 1. mapExecutionResultToVerdict (PASS, FAIL, ERROR mappings).
 * 2. evaluateCoverageCriterion (v0.1 deterministic INCONCLUSIVE, no fake command/artifacts).
 * 3. aggregateVerdicts (Zero-Required rule, lattice precedence ERROR > INCONCLUSIVE > FAIL > PASS, optional criterion isolation).
 * 4. Evidence builder (Keccak-256 digests, empty stream hash, canonical decimal bountyId, manifest building & sorting).
 * 5. RFC 8785 JCS & evidenceHash determinism & sensitivity (tamper tests).
 * 6. Atomic evidence bundle store & verification (staging, idempotent storage, collision detection, tamper detection).
 * 7. Multi-criterion sequential execution & isolation.
 * 8. Commitment failure semantics (never converts PASS to contributor FAIL).
 * 9. Real Docker integration with multi-criterion spec & workspace isolation.
 */

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import type {
  AcceptanceSpecification,
  CoverageCriterion,
} from '../../specification/src/types.ts';
import { hashSpecification } from '../../specification/src/hash.ts';

import {
  mapExecutionResultToVerdict,
  evaluateCoverageCriterion,
  aggregateVerdicts,
  computeKeccak256Digest,
  canonicalizeManifest,
  computeEvidenceHash,
  validateCanonicalDecimalBountyId,
  buildCanonicalManifest,
  EMPTY_BYTES_KECCAK256,
  storeEvidenceBundle,
  verifyEvidenceBundle,
  validateCriterionIdForPath,
  assertPathWithinDirectory,
  executeCriteria,
  runAndCommitVerification,
  EvidenceCollisionError,
  EvidenceCommitmentError,
  EvidenceVerificationError,
  InvalidManifestError,
  type BuildTestCriterionEvidenceRecord,
  type CriterionEvidenceRecord,
  type CanonicalEvidenceManifest,
  type CriterionEvaluationResult,
  type ExecutionResult,
  type SandboxConfig,
} from '../src/index.ts';

describe('Phase 2B-2: Criterion Evaluation & Evidence Commitment', () => {
  let tempTestDir: string;

  before(() => {
    tempTestDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tb-p2b2-test-'));
  });

  after(() => {
    try {
      if (fs.existsSync(tempTestDir)) {
        fs.rmSync(tempTestDir, { recursive: true, force: true });
      }
    } catch {
      // Ignore cleanup error
    }
  });

  // =========================================================================
  // 1. Result Mapping Tests
  // =========================================================================
  describe('Criterion Result Mapping', () => {
    it('maps SUCCESS to PASS with errorCategory NONE', () => {
      const execResult: ExecutionResult = {
        status: 'SUCCESS',
        exitCode: 0,
        durationMs: 120,
        image: 'alpine@sha256:baedd902640d281db2b29da49e0b8e97f5a2b3896fa3528b9b6be4bf679e0066',
        platform: 'linux/amd64',
        workspaceCommit: '1111111111111111111111111111111111111111',
        stdout: 'build ok\n',
        stderr: '',
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'NONE',
      };

      const mapped = mapExecutionResultToVerdict(execResult);
      assert.equal(mapped.verdict, 'PASS');
      assert.equal(mapped.errorCategory, 'NONE');
      assert.equal(mapped.verdictReason, undefined);
    });

    it('maps EXECUTION_FAILED to FAIL with non-zero exit code', () => {
      const execResult: ExecutionResult = {
        status: 'EXECUTION_FAILED',
        exitCode: 1,
        durationMs: 150,
        image: 'alpine@sha256:baedd902640d281db2b29da49e0b8e97f5a2b3896fa3528b9b6be4bf679e0066',
        platform: 'linux/amd64',
        workspaceCommit: '1111111111111111111111111111111111111111',
        stdout: '',
        stderr: 'compilation error\n',
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'NONE',
      };

      const mapped = mapExecutionResultToVerdict(execResult);
      assert.equal(mapped.verdict, 'FAIL');
      assert.equal(mapped.errorCategory, 'NONE');
      assert.equal(mapped.verdictReason, 'PROCESS_EXITED_WITH_CODE_1');
    });

    it('maps TIMEOUT to ERROR (never contributor FAIL)', () => {
      const execResult: ExecutionResult = {
        status: 'TIMEOUT',
        exitCode: null,
        durationMs: 30000,
        image: 'alpine@sha256:baedd902640d281db2b29da49e0b8e97f5a2b3896fa3528b9b6be4bf679e0066',
        platform: 'linux/amd64',
        workspaceCommit: '1111111111111111111111111111111111111111',
        stdout: '',
        stderr: '',
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'TIMEOUT',
      };

      const mapped = mapExecutionResultToVerdict(execResult);
      assert.equal(mapped.verdict, 'ERROR');
      assert.equal(mapped.errorCategory, 'TIMEOUT');
      assert.equal(mapped.verdictReason, 'EXECUTION_TIMEOUT_EXCEEDED');
    });

    it('maps OOM to ERROR (never contributor FAIL)', () => {
      const execResult: ExecutionResult = {
        status: 'OOM',
        exitCode: null,
        durationMs: 2500,
        image: 'alpine@sha256:baedd902640d281db2b29da49e0b8e97f5a2b3896fa3528b9b6be4bf679e0066',
        platform: 'linux/amd64',
        workspaceCommit: '1111111111111111111111111111111111111111',
        stdout: '',
        stderr: 'killed\n',
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'OOM',
      };

      const mapped = mapExecutionResultToVerdict(execResult);
      assert.equal(mapped.verdict, 'ERROR');
      assert.equal(mapped.errorCategory, 'OOM');
      assert.equal(mapped.verdictReason, 'CONTAINER_KILLED_BY_OOM');
    });

    it('maps INFRASTRUCTURE_ERROR to ERROR with category preserved', () => {
      const execResult: ExecutionResult = {
        status: 'INFRASTRUCTURE_ERROR',
        exitCode: null,
        durationMs: 50,
        image: 'alpine@sha256:baedd902640d281db2b29da49e0b8e97f5a2b3896fa3528b9b6be4bf679e0066',
        platform: 'linux/amd64',
        workspaceCommit: '1111111111111111111111111111111111111111',
        stdout: '',
        stderr: '',
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'DOCKER_DAEMON_ERROR',
      };

      const mapped = mapExecutionResultToVerdict(execResult);
      assert.equal(mapped.verdict, 'ERROR');
      assert.equal(mapped.errorCategory, 'DOCKER_DAEMON_ERROR');
      assert.equal(mapped.verdictReason, 'INFRASTRUCTURE_FAILURE_DOCKER_DAEMON_ERROR');
    });
  });

  // =========================================================================
  // 2. Coverage v0.1 Evaluation
  // =========================================================================
  describe('Coverage v0.1 Evaluation', () => {
    it('evaluates COVERAGE criterion to INCONCLUSIVE without command or fake artifacts', () => {
      const coverageCriterion: CoverageCriterion = {
        id: 'cov-check',
        type: 'COVERAGE',
        required: true,
        operator: '>=',
        thresholdBps: 8000,
      };

      const record = evaluateCoverageCriterion(coverageCriterion);
      assert.equal(record.id, 'cov-check');
      assert.equal(record.type, 'COVERAGE');
      assert.equal(record.required, true);
      assert.equal(record.operator, '>=');
      assert.equal(record.thresholdBps, 8000);
      assert.equal(record.verdict, 'INCONCLUSIVE');
      assert.equal(record.verdictReason, 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1');
      assert.equal(record.exitCode, null);
      // Command and output digests are strictly absent (not null)
      assert.equal('command' in record, false);
      assert.equal('stdoutDigest' in record, false);
      assert.equal('stderrDigest' in record, false);
    });
  });

  // =========================================================================
  // 3. Required-Aware Aggregation Tests
  // =========================================================================
  describe('Required-Aware Verdict Aggregation', () => {
    it('enforces Zero-Required Rule: zero required criteria returns ERROR', () => {
      const criteria: BuildTestCriterionEvidenceRecord[] = [
        {
          id: 'step-1',
          type: 'BUILD',
          required: false,
          command: 'make',
          verdict: 'PASS',
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
        {
          id: 'step-2',
          type: 'TEST',
          required: false,
          command: 'make test',
          verdict: 'PASS',
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
      ];

      const res = aggregateVerdicts(criteria);
      assert.equal(res.overallVerdict, 'ERROR');
      assert.equal(res.overallVerdictReason, 'INVALID_SPECIFICATION_NO_REQUIRED_CRITERIA');
    });

    it('Scenario 1: required PASS + optional FAIL -> overall PASS', () => {
      const criteria: BuildTestCriterionEvidenceRecord[] = [
        {
          id: 'build-step',
          type: 'BUILD',
          required: true,
          command: 'npm run build',
          verdict: 'PASS',
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
        {
          id: 'lint-step',
          type: 'TEST',
          required: false,
          command: 'npm run lint',
          verdict: 'FAIL',
          exitCode: 1,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
      ];

      const res = aggregateVerdicts(criteria);
      assert.equal(res.overallVerdict, 'PASS');
    });

    it('Scenario 2: required PASS + optional ERROR -> overall PASS', () => {
      const criteria: BuildTestCriterionEvidenceRecord[] = [
        {
          id: 'build-step',
          type: 'BUILD',
          required: true,
          command: 'npm run build',
          verdict: 'PASS',
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
        {
          id: 'optional-timeout',
          type: 'TEST',
          required: false,
          command: 'sleep 100',
          verdict: 'ERROR',
          verdictReason: 'EXECUTION_TIMEOUT_EXCEEDED',
          exitCode: null,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'TIMEOUT',
        },
      ];

      const res = aggregateVerdicts(criteria);
      assert.equal(res.overallVerdict, 'PASS');
    });

    it('Scenario 3: required FAIL + optional PASS -> overall FAIL', () => {
      const criteria: BuildTestCriterionEvidenceRecord[] = [
        {
          id: 'build-step',
          type: 'BUILD',
          required: true,
          command: 'npm run build',
          verdict: 'FAIL',
          exitCode: 1,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
        {
          id: 'optional-pass',
          type: 'TEST',
          required: false,
          command: 'echo ok',
          verdict: 'PASS',
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
      ];

      const res = aggregateVerdicts(criteria);
      assert.equal(res.overallVerdict, 'FAIL');
    });

    it('Scenario 4: required PASS + required INCONCLUSIVE -> overall INCONCLUSIVE', () => {
      const criteria = [
        {
          id: 'build-step',
          type: 'BUILD' as const,
          required: true,
          command: 'npm run build',
          verdict: 'PASS' as const,
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
        {
          id: 'cov-step',
          type: 'COVERAGE' as const,
          required: true,
          operator: '>=' as const,
          thresholdBps: 8000,
          verdict: 'INCONCLUSIVE' as const,
          verdictReason: 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1' as const,
          exitCode: null,
        },
      ];

      const res = aggregateVerdicts(criteria);
      assert.equal(res.overallVerdict, 'INCONCLUSIVE');
      assert.equal(res.overallVerdictReason, 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1');
    });

    it('Scenario 5: required PASS + required ERROR -> overall ERROR', () => {
      const criteria: BuildTestCriterionEvidenceRecord[] = [
        {
          id: 'build-step',
          type: 'BUILD',
          required: true,
          command: 'npm run build',
          verdict: 'PASS',
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
        {
          id: 'test-step',
          type: 'TEST',
          required: true,
          command: 'npm test',
          verdict: 'ERROR',
          verdictReason: 'CONTAINER_KILLED_BY_OOM',
          exitCode: null,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'OOM',
        },
      ];

      const res = aggregateVerdicts(criteria);
      assert.equal(res.overallVerdict, 'ERROR');
      assert.equal(res.overallVerdictReason, 'CONTAINER_KILLED_BY_OOM');
    });

    it('enforces lattice precedence ERROR > INCONCLUSIVE > FAIL > PASS among required', () => {
      const allRequired: CriterionEvidenceRecord[] = [
        {
          id: '1-pass',
          type: 'BUILD',
          required: true,
          command: 'echo 1',
          verdict: 'PASS',
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
        {
          id: '2-fail',
          type: 'TEST',
          required: true,
          command: 'exit 1',
          verdict: 'FAIL',
          exitCode: 1,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
        {
          id: '3-inconclusive',
          type: 'COVERAGE',
          required: true,
          operator: '>=',
          thresholdBps: 8000,
          verdict: 'INCONCLUSIVE',
          verdictReason: 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1',
          exitCode: null,
        },
        {
          id: '4-error',
          type: 'TEST',
          required: true,
          command: 'sleep 100',
          verdict: 'ERROR',
          verdictReason: 'EXECUTION_TIMEOUT_EXCEEDED',
          exitCode: null,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'TIMEOUT',
        },
      ];

      // With ERROR present, overall is ERROR
      assert.equal(aggregateVerdicts(allRequired).overallVerdict, 'ERROR');

      // Without ERROR, but with INCONCLUSIVE, overall is INCONCLUSIVE
      assert.equal(aggregateVerdicts(allRequired.slice(0, 3)).overallVerdict, 'INCONCLUSIVE');

      // Without INCONCLUSIVE, but with FAIL, overall is FAIL
      assert.equal(aggregateVerdicts(allRequired.slice(0, 2)).overallVerdict, 'FAIL');

      // Only PASS, overall is PASS
      assert.equal(aggregateVerdicts(allRequired.slice(0, 1)).overallVerdict, 'PASS');
    });
  });

  // =========================================================================
  // 4. Evidence Builder & Determinism Tests
  // =========================================================================
  describe('Evidence Builder & Hashing', () => {
    it('computes expected Keccak-256 for empty bytes and known strings', () => {
      assert.equal(computeKeccak256Digest(Buffer.alloc(0)), EMPTY_BYTES_KECCAK256);
      assert.equal(computeKeccak256Digest(''), EMPTY_BYTES_KECCAK256);

      const helloDigest = computeKeccak256Digest(Buffer.from('hello', 'utf-8'));
      assert.equal(helloDigest, '0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8');
    });

    it('validates canonical decimal bountyId strictly', () => {
      assert.equal(validateCanonicalDecimalBountyId('0'), '0');
      assert.equal(validateCanonicalDecimalBountyId('42'), '42');
      assert.equal(validateCanonicalDecimalBountyId('12345678901234567890'), '12345678901234567890');
      // Full 256-bit uint256 max value supported without precision loss
      assert.equal(
        validateCanonicalDecimalBountyId('115792089237316195423570985008687907853269984665640564039457584007913129639935'),
        '115792089237316195423570985008687907853269984665640564039457584007913129639935'
      );

      assert.throws(() => validateCanonicalDecimalBountyId('01'), /canonical decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId('00'), /canonical decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId('+1'), /canonical decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId('-1'), /canonical decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId(' 42 '), /canonical decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId('1.0'), /canonical decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId('0x2a'), /canonical decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId('1e5'), /canonical decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId(''), /canonical decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId(42 as unknown), /must be a decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId(null as unknown), /must be a decimal string/);
      assert.throws(() => validateCanonicalDecimalBountyId(undefined as unknown), /must be a decimal string/);
    });

    it('builds canonical manifest and sorts criteria by id ascending without mutating input', () => {
      const criteria: BuildTestCriterionEvidenceRecord[] = [
        {
          id: 'z-step',
          type: 'BUILD',
          required: true,
          command: 'echo z',
          verdict: 'PASS',
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
        {
          id: 'a-step',
          type: 'TEST',
          required: true,
          command: 'echo a',
          verdict: 'PASS',
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
        {
          id: 'm-step',
          type: 'TEST',
          required: false,
          command: 'echo m',
          verdict: 'PASS',
          exitCode: 0,
          stdoutDigest: EMPTY_BYTES_KECCAK256,
          stderrDigest: EMPTY_BYTES_KECCAK256,
          stdoutTruncated: false,
          stderrTruncated: false,
          errorCategory: 'NONE',
        },
      ];

      const manifest = buildCanonicalManifest({
        specHash: '0x' + '1'.repeat(64),
        bountyId: '42',
        repository: { owner: 'alice', name: 'repo' },
        baseCommit: '2'.repeat(40),
        submittedCommit: '3'.repeat(40),
        environment: {
          image: 'alpine@sha256:' + '4'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria,
        overallVerdict: 'PASS',
      });

      // Manifest criteria is sorted: a-step, m-step, z-step
      assert.deepEqual(
        manifest.criteria.map((c) => c.id),
        ['a-step', 'm-step', 'z-step']
      );

      // Input criteria array remains unmutated
      assert.deepEqual(
        criteria.map((c) => c.id),
        ['z-step', 'a-step', 'm-step']
      );
    });

    it('sorts criteria strictly by UTF-16 code units (e.g. TEST-1, TEST1, TEST_1, test-1)', () => {
      const criteria: BuildTestCriterionEvidenceRecord[] = [
        {
          id: 'TEST_1',
          type: 'BUILD',
          required: true,
          command: 'echo 1',
          verdict: 'PASS',
          exitCode: 0,
          errorCategory: 'NONE',
        },
        {
          id: 'TEST-1',
          type: 'BUILD',
          required: true,
          command: 'echo 2',
          verdict: 'PASS',
          exitCode: 0,
          errorCategory: 'NONE',
        },
        {
          id: 'test-1',
          type: 'BUILD',
          required: true,
          command: 'echo 3',
          verdict: 'PASS',
          exitCode: 0,
          errorCategory: 'NONE',
        },
        {
          id: 'TEST1',
          type: 'BUILD',
          required: true,
          command: 'echo 4',
          verdict: 'PASS',
          exitCode: 0,
          errorCategory: 'NONE',
        },
      ];

      const manifest = buildCanonicalManifest({
        specHash: '0x' + '1'.repeat(64),
        bountyId: '42',
        repository: { owner: 'alice', name: 'repo' },
        baseCommit: '2'.repeat(40),
        submittedCommit: '3'.repeat(40),
        environment: {
          image: 'alpine@sha256:' + '4'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria,
        overallVerdict: 'PASS',
      });

      // UTF-16 / ASCII code units:
      // '-' is 45, '1' is 49, '_' is 95, 't' is 116.
      // 'TEST-1' (45) < 'TEST1' (49) < 'TEST_1' (95) < 'test-1' (116)
      assert.deepEqual(
        manifest.criteria.map((c) => c.id),
        ['TEST-1', 'TEST1', 'TEST_1', 'test-1']
      );

      // Input array must not be mutated
      assert.deepEqual(
        criteria.map((c) => c.id),
        ['TEST_1', 'TEST-1', 'test-1', 'TEST1']
      );
    });

    it('enforces deterministic RFC 8785 JCS canonicalization and evidenceHash', () => {
      const manifest1: CanonicalEvidenceManifest = {
        schemaVersion: '1.0',
        specHash: '0x' + 'a'.repeat(64),
        bountyId: '100',
        repository: { owner: 'alice', name: 'proj' },
        baseCommit: 'b'.repeat(40),
        submittedCommit: 'c'.repeat(40),
        environment: {
          image: 'repo@sha256:' + 'd'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria: [
          {
            id: 'c1',
            type: 'BUILD',
            required: true,
            command: 'make',
            verdict: 'PASS',
            exitCode: 0,
            stdoutDigest: EMPTY_BYTES_KECCAK256,
            stderrDigest: EMPTY_BYTES_KECCAK256,
            stdoutTruncated: false,
            stderrTruncated: false,
            errorCategory: 'NONE',
          },
        ],
        overallVerdict: 'PASS',
        verifierVersion: '0.1.0',
      };

      // Manifest with keys inserted in different order
      const manifest2: CanonicalEvidenceManifest = {
        verifierVersion: '0.1.0',
        overallVerdict: 'PASS',
        submittedCommit: 'c'.repeat(40),
        baseCommit: 'b'.repeat(40),
        environment: {
          platform: 'linux/amd64',
          image: 'repo@sha256:' + 'd'.repeat(64),
        },
        criteria: [
          {
            errorCategory: 'NONE',
            stderrTruncated: false,
            stdoutTruncated: false,
            stderrDigest: EMPTY_BYTES_KECCAK256,
            stdoutDigest: EMPTY_BYTES_KECCAK256,
            exitCode: 0,
            verdict: 'PASS',
            command: 'make',
            required: true,
            type: 'BUILD',
            id: 'c1',
          },
        ],
        repository: { name: 'proj', owner: 'alice' },
        bountyId: '100',
        specHash: '0x' + 'a'.repeat(64),
        schemaVersion: '1.0',
      };

      const jcs1 = canonicalizeManifest(manifest1);
      const jcs2 = canonicalizeManifest(manifest2);
      assert.equal(jcs1, jcs2);

      const hash1 = computeEvidenceHash(manifest1);
      const hash2 = computeEvidenceHash(manifest2);
      assert.equal(hash1, hash2);
      assert.match(hash1, /^0x[0-9a-f]{64}$/);
    });
  });

  // =========================================================================
  // 5. Tamper Sensitivity Tests
  // =========================================================================
  describe('Tamper Sensitivity Tests', () => {
    function createBaseManifest(): CanonicalEvidenceManifest {
      return {
        schemaVersion: '1.0',
        specHash: '0x' + '1'.repeat(64),
        bountyId: '55',
        repository: { owner: 'trustbounty', name: 'core' },
        baseCommit: 'a'.repeat(40),
        submittedCommit: 'b'.repeat(40),
        environment: {
          image: 'toolchain@sha256:' + 'e'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria: [
          {
            id: 'build-step',
            type: 'BUILD',
            required: true,
            command: 'npm run build',
            verdict: 'PASS',
            exitCode: 0,
            stdoutDigest: '0x' + '2'.repeat(64),
            stderrDigest: EMPTY_BYTES_KECCAK256,
            stdoutTruncated: false,
            stderrTruncated: false,
            errorCategory: 'NONE',
          },
        ],
        overallVerdict: 'PASS',
        verifierVersion: '0.1.0',
      };
    }

    it('detects command string modification', () => {
      const original = createBaseManifest();
      const tampered = createBaseManifest();
      (tampered.criteria[0] as BuildTestCriterionEvidenceRecord).command = 'npm run build --fast';

      assert.notEqual(computeEvidenceHash(original), computeEvidenceHash(tampered));
    });

    it('detects stdout artifact digest modification', () => {
      const original = createBaseManifest();
      const tampered = createBaseManifest();
      (tampered.criteria[0] as BuildTestCriterionEvidenceRecord).stdoutDigest = '0x' + '9'.repeat(64);

      assert.notEqual(computeEvidenceHash(original), computeEvidenceHash(tampered));
    });

    it('detects stderr artifact digest modification', () => {
      const original = createBaseManifest();
      const tampered = createBaseManifest();
      (tampered.criteria[0] as BuildTestCriterionEvidenceRecord).stderrDigest = '0x' + '9'.repeat(64);

      assert.notEqual(computeEvidenceHash(original), computeEvidenceHash(tampered));
    });

    it('detects submittedCommit modification', () => {
      const original = createBaseManifest();
      const tampered = createBaseManifest();
      tampered.submittedCommit = 'f'.repeat(40);

      assert.notEqual(computeEvidenceHash(original), computeEvidenceHash(tampered));
    });

    it('detects specHash modification', () => {
      const original = createBaseManifest();
      const tampered = createBaseManifest();
      tampered.specHash = '0x' + '0'.repeat(64);

      assert.notEqual(computeEvidenceHash(original), computeEvidenceHash(tampered));
    });

    it('detects environment image modification', () => {
      const original = createBaseManifest();
      const tampered = createBaseManifest();
      tampered.environment.image = 'toolchain@sha256:' + '0'.repeat(64);

      assert.notEqual(computeEvidenceHash(original), computeEvidenceHash(tampered));
    });

    it('detects verdict modification', () => {
      const original = createBaseManifest();
      const tampered = createBaseManifest();
      tampered.overallVerdict = 'FAIL';

      assert.notEqual(computeEvidenceHash(original), computeEvidenceHash(tampered));
    });

    it('detects required flag modification', () => {
      const original = createBaseManifest();
      const tampered = createBaseManifest();
      tampered.criteria[0].required = false;

      assert.notEqual(computeEvidenceHash(original), computeEvidenceHash(tampered));
    });
  });

  // =========================================================================
  // 6. Atomic Evidence Store & Verification Tests
  // =========================================================================
  describe('Atomic Evidence Store & Bundle Auditing', () => {
    it('asserts path within directory prevents directory traversal', () => {
      const baseDir = path.resolve(tempTestDir, 'base');
      assert.doesNotThrow(() => assertPathWithinDirectory(baseDir, path.join(baseDir, 'file.bin')));
      assert.doesNotThrow(() => assertPathWithinDirectory(baseDir, path.join(baseDir, 'sub', 'file.bin')));
      assert.throws(() => assertPathWithinDirectory(baseDir, path.join(baseDir, '..', 'evil.bin')), EvidenceVerificationError);
      assert.throws(() => assertPathWithinDirectory(baseDir, path.resolve(baseDir, '../../secret')), EvidenceVerificationError);
    });

    it('validates criterion ID path safety against path traversal attempts', () => {
      assert.doesNotThrow(() => validateCriterionIdForPath('valid_step-1'));
      assert.doesNotThrow(() => validateCriterionIdForPath('BUILD-01'));
      assert.doesNotThrow(() => validateCriterionIdForPath('test_criterion_42'));
      assert.throws(() => validateCriterionIdForPath('../evil'), InvalidManifestError);
      assert.throws(() => validateCriterionIdForPath('../../secret'), InvalidManifestError);
      assert.throws(() => validateCriterionIdForPath('..\\secret'), InvalidManifestError);
      assert.throws(() => validateCriterionIdForPath('step/sub'), InvalidManifestError);
      assert.throws(() => validateCriterionIdForPath('step\\sub'), InvalidManifestError);
      assert.throws(() => validateCriterionIdForPath(':colon'), InvalidManifestError);
      assert.throws(() => validateCriterionIdForPath('step with spaces'), InvalidManifestError);
      assert.throws(() => validateCriterionIdForPath('/etc/passwd'), InvalidManifestError);
      assert.throws(() => validateCriterionIdForPath('C:\\Windows'), InvalidManifestError);
      assert.throws(() => validateCriterionIdForPath(''), InvalidManifestError);
      assert.throws(() => validateCriterionIdForPath('a'.repeat(65)), InvalidManifestError);
    });

    it('stores bundle atomically, writes artifacts, and passes verification', async () => {
      const bundlesRoot = path.join(tempTestDir, 'store-test-1');
      const stdoutBuf = Buffer.from('build output lines\n', 'utf-8');
      const stderrBuf = Buffer.from('warnings only\n', 'utf-8');

      const stdoutDigest = computeKeccak256Digest(stdoutBuf);
      const stderrDigest = computeKeccak256Digest(stderrBuf);

      const criteriaRecord: BuildTestCriterionEvidenceRecord = {
        id: 'build-step',
        type: 'BUILD',
        required: true,
        command: 'make',
        verdict: 'PASS',
        exitCode: 0,
        stdoutDigest,
        stderrDigest,
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'NONE',
      };

      const manifest = buildCanonicalManifest({
        specHash: '0x' + '3'.repeat(64),
        bountyId: '777',
        repository: { owner: 'repo-owner', name: 'repo-name' },
        baseCommit: 'a'.repeat(40),
        submittedCommit: 'b'.repeat(40),
        environment: {
          image: 'img@sha256:' + 'c'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria: [criteriaRecord],
        overallVerdict: 'PASS',
      });

      const criteriaResults: CriterionEvaluationResult[] = [
        {
          record: criteriaRecord,
          stdoutBytes: stdoutBuf,
          stderrBytes: stderrBuf,
          durationMs: 450,
          containerId: 'd'.repeat(64),
        },
      ];

      const runtimeMetadata = {
        evidenceHash: computeEvidenceHash(manifest),
        bountyId: '777',
        runId: 'run-01',
        timestamps: {
          startedAt: new Date().toISOString(),
          completedAt: new Date().toISOString(),
          totalDurationMs: 500,
        },
        environment: { hostOs: 'linux' },
        criteriaExecution: [
          {
            id: 'build-step',
            durationMs: 450,
            containerId: 'd'.repeat(64),
          },
        ],
      };

      const bundle = await storeEvidenceBundle({
        bundlesRoot,
        manifest,
        runtimeMetadata,
        criteriaResults,
      });

      assert.ok(fs.existsSync(bundle.bundleDir));
      assert.ok(fs.existsSync(bundle.manifestPath));
      assert.ok(fs.existsSync(bundle.metadataPath));
      assert.ok(fs.existsSync(path.join(bundle.artifactsDir, 'build-step.stdout.bin')));
      assert.ok(fs.existsSync(path.join(bundle.artifactsDir, 'build-step.stderr.bin')));

      // Auditing verification
      const audit = await verifyEvidenceBundle(bundle.bundleDir);
      assert.equal(audit.valid, true);
      assert.equal(audit.evidenceHash, bundle.evidenceHash);

      // Idempotent re-store of identical bundle
      const bundleSecond = await storeEvidenceBundle({
        bundlesRoot,
        manifest,
        runtimeMetadata,
        criteriaResults,
      });
      assert.equal(bundleSecond.evidenceHash, bundle.evidenceHash);
    });

    it('detects collision when existing bundle has non-identical manifest', async () => {
      const bundlesRoot = path.join(tempTestDir, 'store-collision-test');

      const manifest1 = buildCanonicalManifest({
        specHash: '0x' + '4'.repeat(64),
        bountyId: '888',
        repository: { owner: 'own', name: 'repo' },
        baseCommit: 'a'.repeat(40),
        submittedCommit: 'b'.repeat(40),
        environment: {
          image: 'img@sha256:' + 'e'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria: [
          {
            id: 'step-1',
            type: 'BUILD',
            required: true,
            command: 'echo 1',
            verdict: 'PASS',
            exitCode: 0,
            stdoutDigest: EMPTY_BYTES_KECCAK256,
            stderrDigest: EMPTY_BYTES_KECCAK256,
            stdoutTruncated: false,
            stderrTruncated: false,
            errorCategory: 'NONE',
          },
        ],
        overallVerdict: 'PASS',
      });

      const evidenceHash = computeEvidenceHash(manifest1);

      // Pre-create conflicting bundle at target dir
      const conflictDir = path.join(bundlesRoot, evidenceHash);
      fs.mkdirSync(conflictDir, { recursive: true });
      fs.writeFileSync(
        path.join(conflictDir, 'manifest.json'),
        JSON.stringify({ schemaVersion: '1.0', conflicting: true }),
        'utf-8'
      );

      await assert.rejects(
        async () => {
          await storeEvidenceBundle({
            bundlesRoot,
            manifest: manifest1,
            runtimeMetadata: {
              evidenceHash,
              bountyId: '888',
              runId: 'run-conflict',
              timestamps: { startedAt: '', completedAt: '', totalDurationMs: 0 },
              environment: {},
              criteriaExecution: [],
            },
            criteriaResults: [
              {
                record: manifest1.criteria[0],
                stdoutBytes: Buffer.alloc(0),
                stderrBytes: Buffer.alloc(0),
                durationMs: 10,
              },
            ],
          });
        },
        EvidenceCollisionError
      );
    });

    it('rejects tampered bundle during verifyEvidenceBundle', async () => {
      const bundlesRoot = path.join(tempTestDir, 'tamper-bundle-test');
      const stdoutBuf = Buffer.from('original output\n', 'utf-8');

      const record: BuildTestCriterionEvidenceRecord = {
        id: 't-step',
        type: 'BUILD',
        required: true,
        command: 'make',
        verdict: 'PASS',
        exitCode: 0,
        stdoutDigest: computeKeccak256Digest(stdoutBuf),
        stderrDigest: EMPTY_BYTES_KECCAK256,
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'NONE',
      };

      const manifest = buildCanonicalManifest({
        specHash: '0x' + '5'.repeat(64),
        bountyId: '999',
        repository: { owner: 'alice', name: 'lib' },
        baseCommit: 'a'.repeat(40),
        submittedCommit: 'b'.repeat(40),
        environment: {
          image: 'env@sha256:' + 'f'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria: [record],
        overallVerdict: 'PASS',
      });

      const bundle = await storeEvidenceBundle({
        bundlesRoot,
        manifest,
        runtimeMetadata: {
          evidenceHash: computeEvidenceHash(manifest),
          bountyId: '999',
          runId: 'run-t',
          timestamps: { startedAt: '', completedAt: '', totalDurationMs: 0 },
          environment: {},
          criteriaExecution: [],
        },
        criteriaResults: [
          {
            record,
            stdoutBytes: stdoutBuf,
            stderrBytes: Buffer.alloc(0),
            durationMs: 100,
          },
        ],
      });

      // Tamper with the stdout artifact on disk
      const stdoutPath = path.join(bundle.artifactsDir, 't-step.stdout.bin');
      fs.writeFileSync(stdoutPath, Buffer.from('malicious injected logs\n', 'utf-8'));

      await assert.rejects(
        async () => {
          await verifyEvidenceBundle(bundle.bundleDir);
        },
        EvidenceVerificationError
      );
    });

    it('detects and rejects orphan or unexpected files in artifacts directory', async () => {
      const bundlesRoot = path.join(tempTestDir, 'orphan-artifact-test');
      const stdoutBuf = Buffer.from('output\n', 'utf-8');
      const record: BuildTestCriterionEvidenceRecord = {
        id: 'valid-step',
        type: 'BUILD',
        required: true,
        command: 'make',
        verdict: 'PASS',
        exitCode: 0,
        stdoutDigest: computeKeccak256Digest(stdoutBuf),
        stderrDigest: EMPTY_BYTES_KECCAK256,
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'NONE',
      };

      const manifest = buildCanonicalManifest({
        specHash: '0x' + '6'.repeat(64),
        bountyId: '123',
        repository: { owner: 'alice', name: 'repo' },
        baseCommit: 'a'.repeat(40),
        submittedCommit: 'b'.repeat(40),
        environment: {
          image: 'img@sha256:' + '7'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria: [record],
        overallVerdict: 'PASS',
      });

      const bundle = await storeEvidenceBundle({
        bundlesRoot,
        manifest,
        runtimeMetadata: {
          evidenceHash: computeEvidenceHash(manifest),
          bountyId: '123',
          runId: 'run-orphan',
          timestamps: { startedAt: '', completedAt: '', totalDurationMs: 0 },
          environment: {},
          criteriaExecution: [],
        },
        criteriaResults: [
          {
            record,
            stdoutBytes: stdoutBuf,
            stderrBytes: Buffer.alloc(0),
            durationMs: 50,
          },
        ],
      });

      // Inject orphan file in artifacts/
      const orphanFile = path.join(bundle.artifactsDir, 'malicious.bin');
      fs.writeFileSync(orphanFile, Buffer.from('evil payload'));

      await assert.rejects(
        async () => {
          await verifyEvidenceBundle(bundle.bundleDir);
        },
        (err: unknown) => {
          assert.ok(err instanceof EvidenceVerificationError);
          assert.match(err.message, /Unexpected orphan file in artifacts directory: "malicious\.bin"/);
          return true;
        }
      );

      // Clean up orphan file
      fs.unlinkSync(orphanFile);
      const cleanAudit = await verifyEvidenceBundle(bundle.bundleDir);
      assert.equal(cleanAudit.valid, true);
    });

    it('rejects unexpected artifact files present for unexecuted or COVERAGE criteria', async () => {
      const bundlesRoot = path.join(tempTestDir, 'unexpected-cov-artifact-test');
      const manifest = buildCanonicalManifest({
        specHash: '0x' + '7'.repeat(64),
        bountyId: '124',
        repository: { owner: 'alice', name: 'repo' },
        baseCommit: 'a'.repeat(40),
        submittedCommit: 'b'.repeat(40),
        environment: {
          image: 'img@sha256:' + '8'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria: [
          {
            id: 'cov-check',
            type: 'COVERAGE',
            required: false,
            operator: '>=',
            thresholdBps: 8000,
            verdict: 'INCONCLUSIVE',
            verdictReason: 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1',
            exitCode: null,
          },
        ],
        overallVerdict: 'PASS',
      });

      const bundle = await storeEvidenceBundle({
        bundlesRoot,
        manifest,
        runtimeMetadata: {
          evidenceHash: computeEvidenceHash(manifest),
          bountyId: '124',
          runId: 'run-cov-unexpected',
          timestamps: { startedAt: '', completedAt: '', totalDurationMs: 0 },
          environment: {},
          criteriaExecution: [],
        },
        criteriaResults: [],
      });

      // Inject unexpected artifact for COVERAGE criterion
      const unexpectedArtifact = path.join(bundle.artifactsDir, 'cov-check.stdout.bin');
      fs.writeFileSync(unexpectedArtifact, Buffer.from('fake coverage log'));

      await assert.rejects(
        async () => {
          await verifyEvidenceBundle(bundle.bundleDir);
        },
        (err: unknown) => {
          assert.ok(err instanceof EvidenceVerificationError);
          assert.match(err.message, /Unexpected artifact file found for unexecuted criterion: "cov-check"/);
          return true;
        }
      );
    });

    it('rejects symbolic links in artifacts directory during verification', async () => {
      const bundlesRoot = path.join(tempTestDir, 'symlink-rejection-test');
      const stdoutBuf = Buffer.from('symlink test output\n', 'utf-8');
      const record: BuildTestCriterionEvidenceRecord = {
        id: 'sym-step',
        type: 'BUILD',
        required: true,
        command: 'make',
        verdict: 'PASS',
        exitCode: 0,
        stdoutDigest: computeKeccak256Digest(stdoutBuf),
        stderrDigest: EMPTY_BYTES_KECCAK256,
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'NONE',
      };

      const manifest = buildCanonicalManifest({
        specHash: '0x' + '8'.repeat(64),
        bountyId: '125',
        repository: { owner: 'alice', name: 'repo' },
        baseCommit: 'a'.repeat(40),
        submittedCommit: 'b'.repeat(40),
        environment: {
          image: 'img@sha256:' + '9'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria: [record],
        overallVerdict: 'PASS',
      });

      const bundle = await storeEvidenceBundle({
        bundlesRoot,
        manifest,
        runtimeMetadata: {
          evidenceHash: computeEvidenceHash(manifest),
          bountyId: '125',
          runId: 'run-sym',
          timestamps: { startedAt: '', completedAt: '', totalDurationMs: 0 },
          environment: {},
          criteriaExecution: [],
        },
        criteriaResults: [
          {
            record,
            stdoutBytes: stdoutBuf,
            stderrBytes: Buffer.alloc(0),
            durationMs: 30,
          },
        ],
      });

      const stdoutFile = path.join(bundle.artifactsDir, 'sym-step.stdout.bin');
      assert.ok(fs.existsSync(stdoutFile));

      // Attempt to test real symlink if platform allows, else test via mock lstatSync
      let symlinkCreated = false;
      const originalFile = path.join(tempTestDir, 'real-target.bin');
      fs.writeFileSync(originalFile, stdoutBuf);

      try {
        fs.unlinkSync(stdoutFile);
        fs.symlinkSync(originalFile, stdoutFile);
        symlinkCreated = true;
      } catch {
        // Platform denied symlink creation; restore genuine file
        fs.writeFileSync(stdoutFile, stdoutBuf);
      }

      if (symlinkCreated) {
        await assert.rejects(
          async () => {
            await verifyEvidenceBundle(bundle.bundleDir);
          },
          (err: unknown) => {
            assert.ok(err instanceof EvidenceVerificationError);
            assert.match(err.message, /Symbolic link rejected for artifact/);
            return true;
          }
        );
      } else {
        // Test symlink detection via lstatSync mocking
        const originalLstat = fs.lstatSync;
        try {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          (fs as any).lstatSync = (p: string, opts?: any) => {
            const stats = originalLstat(p, opts);
            if (path.resolve(p) === path.resolve(stdoutFile)) {
              return Object.assign(Object.create(Object.getPrototypeOf(stats)), stats, {
                isSymbolicLink: () => true,
              });
            }
            return stats;
          };

          await assert.rejects(
            async () => {
              await verifyEvidenceBundle(bundle.bundleDir);
            },
            (err: unknown) => {
              assert.ok(err instanceof EvidenceVerificationError);
              assert.match(err.message, /Symbolic link rejected for artifact/);
              return true;
            }
          );
        } finally {
          (fs as any).lstatSync = originalLstat;
        }
      }
    });

    it('handles concurrent atomic promotion race cleanly when target directory exists', async () => {
      const bundlesRoot = path.join(tempTestDir, 'atomic-race-test');
      const stdoutBuf = Buffer.from('output\n', 'utf-8');
      const record: BuildTestCriterionEvidenceRecord = {
        id: 'step-race',
        type: 'BUILD',
        required: true,
        command: 'make',
        verdict: 'PASS',
        exitCode: 0,
        stdoutDigest: computeKeccak256Digest(stdoutBuf),
        stderrDigest: EMPTY_BYTES_KECCAK256,
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'NONE',
      };

      const manifest = buildCanonicalManifest({
        specHash: '0x' + '9'.repeat(64),
        bountyId: '900',
        repository: { owner: 'alice', name: 'repo' },
        baseCommit: 'a'.repeat(40),
        submittedCommit: 'b'.repeat(40),
        environment: {
          image: 'img@sha256:' + '1'.repeat(64),
          platform: 'linux/amd64',
        },
        criteria: [record],
        overallVerdict: 'PASS',
      });

      // First store creates the directory
      const bundle1 = await storeEvidenceBundle({
        bundlesRoot,
        manifest,
        runtimeMetadata: {
          evidenceHash: computeEvidenceHash(manifest),
          bountyId: '900',
          runId: 'run-race-1',
          timestamps: { startedAt: '', completedAt: '', totalDurationMs: 0 },
          environment: {},
          criteriaExecution: [],
        },
        criteriaResults: [
          {
            record,
            stdoutBytes: stdoutBuf,
            stderrBytes: Buffer.alloc(0),
            durationMs: 20,
          },
        ],
      });

      // Second store of identical bundle resolves idempotently without error
      const bundle2 = await storeEvidenceBundle({
        bundlesRoot,
        manifest,
        runtimeMetadata: {
          evidenceHash: computeEvidenceHash(manifest),
          bountyId: '900',
          runId: 'run-race-2',
          timestamps: { startedAt: '', completedAt: '', totalDurationMs: 0 },
          environment: {},
          criteriaExecution: [],
        },
        criteriaResults: [
          {
            record,
            stdoutBytes: stdoutBuf,
            stderrBytes: Buffer.alloc(0),
            durationMs: 25,
          },
        ],
      });

      assert.equal(bundle1.evidenceHash, bundle2.evidenceHash);
      assert.equal(bundle1.bundleDir, bundle2.bundleDir);
    });
  });

  // =========================================================================
  // 7. Multi-Criterion Execution Orchestration Tests
  // =========================================================================
  describe('Multi-Criterion Execution & Failure Separation', () => {
    it('executes criteria sequentially and skips remaining on fatal infrastructure error', async () => {
      const spec: AcceptanceSpecification = {
        version: '1.1',
        repository: { owner: 'org', name: 'app' },
        baseCommit: '1'.repeat(40),
        environment: {
          image: 'alpine@sha256:' + 'a'.repeat(64),
        },
        criteria: [
          {
            id: 'step-1-pass',
            type: 'BUILD',
            required: true,
            command: 'echo step 1',
          },
          {
            id: 'step-2-crash',
            type: 'TEST',
            required: true,
            command: 'trigger-crash',
          },
          {
            id: 'step-3-skipped',
            type: 'TEST',
            required: true,
            command: 'echo step 3',
          },
        ],
      };

      // Mock sandbox runner
      const mockRunner = async (cfg: SandboxConfig): Promise<ExecutionResult> => {
        if (cfg.command === 'echo step 1') {
          return {
            status: 'SUCCESS',
            exitCode: 0,
            durationMs: 10,
            image: cfg.image,
            platform: 'linux/amd64',
            workspaceCommit: cfg.workspaceCommit,
            stdout: 'step 1 done\n',
            stderr: '',
            stdoutTruncated: false,
            stderrTruncated: false,
            errorCategory: 'NONE',
          };
        }
        if (cfg.command === 'trigger-crash') {
          return {
            status: 'INFRASTRUCTURE_ERROR',
            exitCode: null,
            durationMs: 5,
            image: cfg.image,
            platform: 'linux/amd64',
            workspaceCommit: cfg.workspaceCommit,
            stdout: '',
            stderr: 'daemon disconnected\n',
            stdoutTruncated: false,
            stderrTruncated: false,
            errorCategory: 'DOCKER_DAEMON_ERROR',
          };
        }
        throw new Error('Should not be executed');
      };

      const result = await executeCriteria({
        spec,
        bountyId: '101',
        workspacePath: '/fake/ws',
        submittedCommit: '2'.repeat(40),
        sandboxRunner: mockRunner,
      });

      assert.equal(result.criteriaResults.length, 3);
      assert.equal(result.criteriaResults[0].record.verdict, 'PASS');
      assert.equal(result.criteriaResults[1].record.verdict, 'ERROR');
      assert.equal(result.criteriaResults[2].record.verdict, 'ERROR');
      assert.equal(
        result.criteriaResults[2].record.verdictReason,
        'EXECUTION_SKIPPED_DUE_TO_PRIOR_INFRASTRUCTURE_ERROR'
      );
      assert.equal(result.overallVerdict, 'ERROR');
    });

    it('commitment failure semantics: never converts contributor PASS into FAIL', async () => {
      const spec: AcceptanceSpecification = {
        version: '1.1',
        repository: { owner: 'org', name: 'app' },
        baseCommit: '1'.repeat(40),
        environment: {
          image: 'alpine@sha256:' + 'a'.repeat(64),
        },
        criteria: [
          {
            id: 'build-pass',
            type: 'BUILD',
            required: true,
            command: 'echo ok',
          },
        ],
      };

      const mockRunner = async (cfg: SandboxConfig): Promise<ExecutionResult> => ({
        status: 'SUCCESS',
        exitCode: 0,
        durationMs: 10,
        image: cfg.image,
        platform: 'linux/amd64',
        workspaceCommit: cfg.workspaceCommit,
        stdout: 'all green\n',
        stderr: '',
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'NONE',
      });

      // Point bundlesRoot to an invalid path that cannot be written to
      const invalidBundlesRoot = path.join(tempTestDir, 'not-a-directory-file');
      fs.writeFileSync(invalidBundlesRoot, 'blocking file');

      const outcome = await runAndCommitVerification({
        spec,
        bountyId: '500',
        workspacePath: '/fake/ws',
        submittedCommit: '2'.repeat(40),
        bundlesRoot: path.join(invalidBundlesRoot, 'sub'), // Will fail ENOTDIR
        sandboxRunner: mockRunner,
      });

      // Criteria internally evaluated to PASS
      assert.equal(outcome.executionResult.overallVerdict, 'PASS');
      // But overall reportable outcome MUST become ERROR due to commitment failure
      assert.equal(outcome.overallVerdict, 'ERROR');
      assert.match(outcome.overallVerdictReason ?? '', /EVIDENCE_COMMITMENT_FAILED/);
      assert.equal(outcome.evidenceHash, null);
      assert.equal(outcome.bundle, null);
    });

    it('short-circuits on TIMEOUT: halts subsequent execution and omits artifact digests on skipped criteria', async () => {
      const spec: AcceptanceSpecification = {
        version: '1.1',
        repository: { owner: 'org', name: 'app' },
        baseCommit: '1'.repeat(40),
        environment: {
          image: 'alpine@sha256:' + 'a'.repeat(64),
        },
        criteria: [
          {
            id: 'criterion-1-timeout',
            type: 'BUILD',
            required: true,
            command: 'sleep 999',
          },
          {
            id: 'criterion-2-skipped',
            type: 'TEST',
            required: true,
            command: 'echo should not run',
          },
        ],
      };

      const mockRunner = async (cfg: SandboxConfig): Promise<ExecutionResult> => {
        if (cfg.command === 'sleep 999') {
          return {
            status: 'TIMEOUT',
            exitCode: null,
            durationMs: 60000,
            image: cfg.image,
            platform: 'linux/amd64',
            workspaceCommit: cfg.workspaceCommit,
            stdout: 'partial stdout\n',
            stderr: 'timed out\n',
            stdoutTruncated: false,
            stderrTruncated: false,
            errorCategory: 'TIMEOUT',
          };
        }
        throw new Error(`Runner called unexpectedly for ${cfg.command}`);
      };

      const result = await executeCriteria({
        spec,
        bountyId: '102',
        workspacePath: '/ws',
        submittedCommit: '2'.repeat(40),
        sandboxRunner: mockRunner,
      });

      assert.equal(result.criteriaResults.length, 2);
      assert.equal(result.criteriaResults[0].record.verdict, 'ERROR');
      assert.equal(result.criteriaResults[0].record.errorCategory, 'TIMEOUT');
      assert.equal(result.criteriaResults[0].record.stdoutDigest !== undefined, true);

      // Criterion 2 was short-circuited
      const skipped = result.criteriaResults[1].record as BuildTestCriterionEvidenceRecord;
      assert.equal(skipped.id, 'criterion-2-skipped');
      assert.equal(skipped.verdict, 'ERROR');
      assert.equal(skipped.verdictReason, 'EXECUTION_SKIPPED_DUE_TO_PRIOR_TIMEOUT');
      assert.equal(skipped.exitCode, null);
      // stdoutDigest, stderrDigest, and truncation flags must be omitted (undefined), not fake empty digests
      assert.equal(skipped.stdoutDigest, undefined);
      assert.equal(skipped.stderrDigest, undefined);
      assert.equal(skipped.stdoutTruncated, undefined);
      assert.equal(skipped.stderrTruncated, undefined);
      assert.equal('stdoutDigest' in skipped, false);
      assert.equal('stderrDigest' in skipped, false);

      assert.equal(result.overallVerdict, 'ERROR');
    });

    it('short-circuits on OOM: halts subsequent execution and omits artifact digests on skipped criteria', async () => {
      const spec: AcceptanceSpecification = {
        version: '1.1',
        repository: { owner: 'org', name: 'app' },
        baseCommit: '1'.repeat(40),
        environment: {
          image: 'alpine@sha256:' + 'a'.repeat(64),
        },
        criteria: [
          {
            id: 'criterion-1-oom',
            type: 'BUILD',
            required: true,
            command: 'alloc-infinite-memory',
          },
          {
            id: 'criterion-2-skipped',
            type: 'TEST',
            required: true,
            command: 'echo should not run',
          },
        ],
      };

      const mockRunner = async (cfg: SandboxConfig): Promise<ExecutionResult> => {
        if (cfg.command === 'alloc-infinite-memory') {
          return {
            status: 'OOM',
            exitCode: null,
            durationMs: 1200,
            image: cfg.image,
            platform: 'linux/amd64',
            workspaceCommit: cfg.workspaceCommit,
            stdout: '',
            stderr: 'Killed process (OOM)\n',
            stdoutTruncated: false,
            stderrTruncated: false,
            errorCategory: 'OOM',
          };
        }
        throw new Error(`Runner called unexpectedly for ${cfg.command}`);
      };

      const result = await executeCriteria({
        spec,
        bountyId: '103',
        workspacePath: '/ws',
        submittedCommit: '2'.repeat(40),
        sandboxRunner: mockRunner,
      });

      assert.equal(result.criteriaResults.length, 2);
      assert.equal(result.criteriaResults[0].record.verdict, 'ERROR');
      assert.equal(result.criteriaResults[0].record.errorCategory, 'OOM');

      const skipped = result.criteriaResults[1].record as BuildTestCriterionEvidenceRecord;
      assert.equal(skipped.id, 'criterion-2-skipped');
      assert.equal(skipped.verdict, 'ERROR');
      assert.equal(skipped.verdictReason, 'EXECUTION_SKIPPED_DUE_TO_PRIOR_OOM');
      assert.equal(skipped.stdoutDigest, undefined);
      assert.equal(skipped.stderrDigest, undefined);
      assert.equal('stdoutDigest' in skipped, false);

      assert.equal(result.overallVerdict, 'ERROR');
    });

    it('validates specHash and image consistency in runAndCommitVerification', async () => {
      const spec: AcceptanceSpecification = {
        version: '1.1',
        repository: { owner: 'org', name: 'app' },
        baseCommit: '1'.repeat(40),
        environment: {
          image: 'alpine@sha256:' + 'a'.repeat(64),
        },
        criteria: [
          {
            id: 'build-pass',
            type: 'BUILD',
            required: true,
            command: 'echo ok',
          },
        ],
      };

      const mockRunner = async (cfg: SandboxConfig): Promise<ExecutionResult> => ({
        status: 'SUCCESS',
        exitCode: 0,
        durationMs: 10,
        image: cfg.image,
        platform: 'linux/amd64',
        workspaceCommit: cfg.workspaceCommit,
        stdout: 'ok\n',
        stderr: '',
        stdoutTruncated: false,
        stderrTruncated: false,
        errorCategory: 'NONE',
      });

      const bundlesRoot = path.join(tempTestDir, 'spec-consistency-bundles');

      const outcome = await runAndCommitVerification({
        spec,
        bountyId: '42',
        workspacePath: '/fake/ws',
        submittedCommit: '2'.repeat(40),
        bundlesRoot,
        sandboxRunner: mockRunner,
      });

      assert.equal(outcome.overallVerdict, 'PASS');
      assert.ok(outcome.manifest);
      assert.equal(outcome.manifest.specHash, hashSpecification(spec));
      assert.equal(outcome.manifest.environment.image, spec.environment.image);
    });
  });

  // =========================================================================
  // 8. Real Docker Sandbox Multi-Criterion Integration Test
  // =========================================================================
  describe('Phase 2B-2 Real Docker Sandbox Integration', () => {
    const pinnedImage =
      'ubuntu@sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d';
    let realWorkspace: string;

    before(() => {
      realWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), 'tb-docker-ws-'));
      fs.writeFileSync(path.join(realWorkspace, 'hello.txt'), 'hello from workspace\n');
    });

    after(() => {
      try {
        if (fs.existsSync(realWorkspace)) {
          fs.rmSync(realWorkspace, { recursive: true, force: true });
        }
      } catch {
        // Ignore
      }
    });

    it('executes multi-criterion workflow (BUILD PASS + TEST PASS + COVERAGE INCONCLUSIVE) with real Docker', async () => {
      const bundlesRoot = path.join(tempTestDir, 'real-docker-bundles');
      const submittedCommit = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

      const spec: AcceptanceSpecification = {
        version: '1.1',
        repository: { owner: 'alice', name: 'app' },
        baseCommit: submittedCommit,
        environment: {
          image: pinnedImage,
        },
        criteria: [
          {
            id: '01-build',
            type: 'BUILD',
            required: true,
            command: 'cat hello.txt && echo "build success"',
          },
          {
            id: '02-test',
            type: 'TEST',
            required: true,
            command: 'test -f hello.txt && echo "test success"',
          },
          {
            id: '03-coverage',
            type: 'COVERAGE',
            required: false, // optional coverage criterion
            operator: '>=',
            thresholdBps: 8000,
          },
        ],
      };

      const outcome = await runAndCommitVerification({
        spec,
        bountyId: '42',
        workspacePath: realWorkspace,
        submittedCommit,
        bundlesRoot,
      });

      assert.equal(outcome.overallVerdict, 'PASS');
      assert.ok(outcome.evidenceHash);
      assert.ok(outcome.bundle);

      // Verify audit passes
      const audit = await verifyEvidenceBundle(outcome.bundle.bundleDir);
      assert.equal(audit.valid, true);
      assert.equal(audit.evidenceHash, outcome.evidenceHash);

      // Verify manifest contents
      assert.equal(outcome.manifest?.criteria.length, 3);
      assert.equal(outcome.manifest?.criteria[0].id, '01-build');
      assert.equal(outcome.manifest?.criteria[0].verdict, 'PASS');
      assert.equal(outcome.manifest?.criteria[1].id, '02-test');
      assert.equal(outcome.manifest?.criteria[1].verdict, 'PASS');
      assert.equal(outcome.manifest?.criteria[2].id, '03-coverage');
      assert.equal(outcome.manifest?.criteria[2].verdict, 'INCONCLUSIVE');
    });

    it('enforces fresh workspace isolation: file created in BUILD is absent in TEST', async () => {
      const submittedCommit = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

      const spec: AcceptanceSpecification = {
        version: '1.1',
        repository: { owner: 'alice', name: 'app' },
        baseCommit: submittedCommit,
        environment: {
          image: pinnedImage,
        },
        criteria: [
          {
            id: 'step-1-create-file',
            type: 'BUILD',
            required: true,
            command: 'touch /workspace/step1_artifact.txt && test -f /workspace/step1_artifact.txt',
          },
          {
            id: 'step-2-assert-file-absent',
            type: 'TEST',
            required: true,
            // step1_artifact.txt must NOT exist in the fresh /workspace tmpfs of step 2
            command: 'test ! -f /workspace/step1_artifact.txt',
          },
        ],
      };

      const result = await executeCriteria({
        spec,
        bountyId: '99',
        workspacePath: realWorkspace,
        submittedCommit,
      });

      assert.equal(result.overallVerdict, 'PASS');
      assert.equal(result.criteriaResults[0].record.verdict, 'PASS');
      assert.equal(result.criteriaResults[1].record.verdict, 'PASS');
    });
  });
});
