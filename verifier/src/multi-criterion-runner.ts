/**
 * TrustBounty Phase 2B-2: Multi-Criterion Sequential Runner & Verifier Orchestrator.
 *
 * Implements:
 * 1. Sequential execution of criteria in exact specification array order.
 * 2. Fresh sandbox isolation per executable criterion via executeInSandbox().
 * 3. Deterministic v0.1 COVERAGE handling (no Docker execution).
 * 4. Required-aware multi-criterion verdict aggregation.
 * 5. Architectural separation between Execution, Evaluation, and Commitment.
 * 6. Commitment failure semantics: failure to commit evidence results in ERROR,
 *    never contributor FAIL.
 */

import type {
  AcceptanceSpecification,
  AcceptanceCriterion,
} from '../../specification/src/types.ts';
import { validateSpecification } from '../../specification/src/validate.ts';
import { hashSpecification } from '../../specification/src/hash.ts';

import type { ExecutionResult, SandboxConfig } from './docker-types.ts';
import { executeInSandbox } from './docker.ts';
import type {
  CanonicalEvidenceManifest,
  CriterionEvaluationResult,
  CriterionEvidenceRecord,
  EvidenceBundle,
  ManifestVerdict,
  MultiCriterionExecutionResult,
  RuntimeMetadata,
} from './evidence-types.ts';
import {
  aggregateVerdicts,
  evaluateCoverageCriterion,
  mapExecutionResultToVerdict,
} from './criterion-evaluator.ts';
import {
  buildCanonicalManifest,
  computeEvidenceHash,
  computeKeccak256Digest,
  EMPTY_BYTES_KECCAK256,
  validateCanonicalDecimalBountyId,
} from './evidence-builder.ts';
import { storeEvidenceBundle } from './evidence-store.ts';

export type SandboxRunnerFn = (config: SandboxConfig) => Promise<ExecutionResult>;

export interface ExecuteCriteriaParams {
  spec: AcceptanceSpecification;
  bountyId: string;
  workspacePath: string;
  submittedCommit: string;
  runId?: string;
  sandboxRunner?: SandboxRunnerFn;
}

/**
 * Sequentially executes all criteria in an acceptance specification.
 */
export async function executeCriteria(
  params: ExecuteCriteriaParams
): Promise<MultiCriterionExecutionResult> {
  const {
    spec,
    bountyId,
    workspacePath,
    submittedCommit,
    runId = `run-${Date.now()}`,
    sandboxRunner = executeInSandbox,
  } = params;

  // 1. Validate input specification
  const validation = validateSpecification(spec);
  if (!validation.valid) {
    const errorMsg = validation.errors.map((e) => `${e.path}: ${e.message}`).join('; ');
    throw new TypeError(`Invalid acceptance specification: ${errorMsg}`);
  }

  // 2. Compute specHash
  const specHash = hashSpecification(spec);

  // 3. Validate canonical decimal bountyId
  const validBountyId = validateCanonicalDecimalBountyId(bountyId);

  const startTime = Date.now();
  const startedAt = new Date(startTime).toISOString();

  // 4. Zero-Required Rule Check
  const requiredCriteria = spec.criteria.filter((c) => c.required === true);
  if (requiredCriteria.length === 0) {
    const completedTime = Date.now();
    return {
      specHash,
      bountyId: validBountyId,
      repository: { ...spec.repository },
      baseCommit: spec.baseCommit.toLowerCase(),
      submittedCommit: submittedCommit.toLowerCase(),
      environment: {
        image: spec.environment.image,
        platform: 'linux/amd64',
      },
      criteriaResults: [],
      overallVerdict: 'ERROR',
      overallVerdictReason: 'INVALID_SPECIFICATION_NO_REQUIRED_CRITERIA',
      startedAt,
      completedAt: new Date(completedTime).toISOString(),
      totalDurationMs: completedTime - startTime,
    };
  }

  const criteriaResults: CriterionEvaluationResult[] = [];
  let priorFatalError = false;
  let priorFatalReason = '';
  let priorFatalCategory = '';

  // 5. Sequential Execution in exact spec array order
  for (const criterion of spec.criteria) {
    if (criterion.type === 'COVERAGE') {
      // Schema v1.1 COVERAGE has no command: deterministically evaluated to INCONCLUSIVE
      const coverageRecord = evaluateCoverageCriterion(criterion);
      criteriaResults.push({
        record: coverageRecord,
        durationMs: 0,
      });
      continue;
    }

    // BUILD or TEST criterion
    if (priorFatalError) {
      // Prior fatal infrastructure, timeout, or OOM failure stops execution.
      // Skipped criteria omit artifact digests and truncation flags rather than generating synthetic empty stream digests.
      const skippedRecord: CriterionEvidenceRecord = {
        id: criterion.id,
        type: criterion.type,
        required: criterion.required,
        command: criterion.command,
        verdict: 'ERROR',
        verdictReason: priorFatalReason,
        exitCode: null,
        errorCategory: priorFatalCategory,
      };
      criteriaResults.push({
        record: skippedRecord,
        durationMs: 0,
      });
      continue;
    }

    // Execute criterion in Phase 2B-1 Docker Sandbox
    const criterionStart = Date.now();
    let execResult: ExecutionResult;

    try {
      execResult = await sandboxRunner({
        image: spec.environment.image,
        workspaceCommit: submittedCommit,
        workspacePath,
        command: criterion.command,
        bountyId,
        runId,
      });
    } catch (unexpectedError) {
      execResult = {
        status: 'INFRASTRUCTURE_ERROR',
        exitCode: null,
        errorCategory: 'DOCKER_DAEMON_ERROR',
        durationMs: Date.now() - criterionStart,
        image: spec.environment.image,
        platform: 'linux/amd64',
        workspaceCommit: submittedCommit,
        stdout: '',
        stderr: '',
        stdoutTruncated: false,
        stderrTruncated: false,
      };
    }

    const criterionDuration = Date.now() - criterionStart;

    // Check if fatal infrastructure error, timeout, or OOM occurred
    if (
      execResult.status === 'INFRASTRUCTURE_ERROR' ||
      execResult.status === 'TIMEOUT' ||
      execResult.status === 'OOM'
    ) {
      priorFatalError = true;
      priorFatalCategory = execResult.errorCategory;
      priorFatalReason =
        execResult.status === 'TIMEOUT'
          ? 'EXECUTION_SKIPPED_DUE_TO_PRIOR_TIMEOUT'
          : execResult.status === 'OOM'
            ? 'EXECUTION_SKIPPED_DUE_TO_PRIOR_OOM'
            : 'EXECUTION_SKIPPED_DUE_TO_PRIOR_INFRASTRUCTURE_ERROR';
    }

    // Hash raw retained stream bytes
    const stdoutBytes = Buffer.from(execResult.stdout, 'utf-8');
    const stderrBytes = Buffer.from(execResult.stderr, 'utf-8');

    const stdoutDigest = computeKeccak256Digest(stdoutBytes);
    const stderrDigest = computeKeccak256Digest(stderrBytes);

    // Map ExecutionResult to ManifestVerdict
    const mapped = mapExecutionResultToVerdict(execResult);

    const buildTestRecord: CriterionEvidenceRecord = {
      id: criterion.id,
      type: criterion.type,
      required: criterion.required,
      command: criterion.command,
      verdict: mapped.verdict,
      exitCode: execResult.exitCode,
      stdoutDigest,
      stderrDigest,
      stdoutTruncated: execResult.stdoutTruncated,
      stderrTruncated: execResult.stderrTruncated,
      errorCategory: mapped.errorCategory,
    };

    if (mapped.verdictReason !== undefined) {
      buildTestRecord.verdictReason = mapped.verdictReason;
    }

    criteriaResults.push({
      record: buildTestRecord,
      stdoutBytes,
      stderrBytes,
      durationMs: criterionDuration,
      containerId: execResult.containerId,
    });
  }

  // 6. Aggregate verdicts across all criteria
  const manifestCriteria = criteriaResults.map((cr) => cr.record);
  const aggregated = aggregateVerdicts(manifestCriteria);

  const completedTime = Date.now();
  const completedAt = new Date(completedTime).toISOString();

  return {
    specHash,
    bountyId: validBountyId,
    repository: { ...spec.repository },
    baseCommit: spec.baseCommit.toLowerCase(),
    submittedCommit: submittedCommit.toLowerCase(),
    environment: {
      image: spec.environment.image,
      platform: 'linux/amd64',
    },
    criteriaResults,
    overallVerdict: aggregated.overallVerdict,
    overallVerdictReason: aggregated.overallVerdictReason,
    startedAt,
    completedAt,
    totalDurationMs: completedTime - startTime,
  };
}

export interface RunAndCommitVerificationParams extends ExecuteCriteriaParams {
  bundlesRoot: string;
  verifierVersion?: string;
  verifierId?: string;
}

export interface VerificationOutcome {
  overallVerdict: ManifestVerdict;
  overallVerdictReason?: string;
  evidenceHash: string | null;
  manifest: CanonicalEvidenceManifest | null;
  bundle: EvidenceBundle | null;
  executionResult: MultiCriterionExecutionResult;
}

/**
 * Orchestrates multi-criterion execution, canonical manifest creation, and atomic evidence bundle commitment.
 *
 * Implements strict separation:
 * If criteria execution succeeds (PASS/FAIL), but evidence commitment fails:
 * - overallVerdict becomes ERROR
 * - evidenceHash is null
 * - contributor PASS is NEVER converted to FAIL
 */
export async function runAndCommitVerification(
  params: RunAndCommitVerificationParams
): Promise<VerificationOutcome> {
  const { bundlesRoot, verifierVersion = '0.1.0', verifierId, runId = `run-${Date.now()}` } = params;

  // 1. Execute criteria
  const executionResult = await executeCriteria(params);

  // If zero-required rule hit, no criteria executed
  if (executionResult.overallVerdictReason === 'INVALID_SPECIFICATION_NO_REQUIRED_CRITERIA') {
    return {
      overallVerdict: 'ERROR',
      overallVerdictReason: 'INVALID_SPECIFICATION_NO_REQUIRED_CRITERIA',
      evidenceHash: null,
      manifest: null,
      bundle: null,
      executionResult,
    };
  }

  // Validate manifest/spec consistency
  const expectedSpecHash = hashSpecification(params.spec);
  if (executionResult.specHash !== expectedSpecHash) {
    throw new Error(
      `specHash mismatch: execution result has ${executionResult.specHash}, expected ${expectedSpecHash}`
    );
  }
  if (executionResult.environment.image !== params.spec.environment.image) {
    throw new Error(
      `environment image mismatch: execution result has ${executionResult.environment.image}, expected ${params.spec.environment.image}`
    );
  }

  // 2. Build Canonical Evidence Manifest (with criteria sorted ascending by id)
  const rawCriteria = executionResult.criteriaResults.map((cr) => cr.record);
  const manifest = buildCanonicalManifest({
    specHash: executionResult.specHash,
    bountyId: executionResult.bountyId,
    repository: executionResult.repository,
    baseCommit: executionResult.baseCommit,
    submittedCommit: executionResult.submittedCommit,
    environment: executionResult.environment,
    criteria: rawCriteria,
    overallVerdict: executionResult.overallVerdict,
    overallVerdictReason: executionResult.overallVerdictReason,
    verifierVersion,
  });

  const evidenceHash = computeEvidenceHash(manifest);

  // 3. Construct unhashed RuntimeMetadata
  const runtimeMetadata: RuntimeMetadata = {
    evidenceHash,
    bountyId: executionResult.bountyId,
    runId,
    verifierId,
    timestamps: {
      startedAt: executionResult.startedAt,
      completedAt: executionResult.completedAt,
      totalDurationMs: executionResult.totalDurationMs,
    },
    environment: {
      hostOs: process.platform,
    },
    criteriaExecution: executionResult.criteriaResults.map((cr) => ({
      id: cr.record.id,
      containerId: cr.containerId,
      durationMs: cr.durationMs,
      hostWorkspacePath: params.workspacePath,
    })),
  };

  // 4. Atomically commit evidence bundle
  try {
    const bundle = await storeEvidenceBundle({
      bundlesRoot,
      manifest,
      runtimeMetadata,
      criteriaResults: executionResult.criteriaResults,
    });

    return {
      overallVerdict: manifest.overallVerdict,
      overallVerdictReason: manifest.overallVerdictReason,
      evidenceHash,
      manifest,
      bundle,
      executionResult,
    };
  } catch (commitmentError) {
    // Commitment failure semantics:
    // If evidence cannot be committed, externally reported verdict MUST be ERROR.
    // Never report contributor FAIL for commitment failures.
    return {
      overallVerdict: 'ERROR',
      overallVerdictReason: `EVIDENCE_COMMITMENT_FAILED: ${commitmentError instanceof Error ? commitmentError.message : String(commitmentError)}`,
      evidenceHash: null,
      manifest: null,
      bundle: null,
      executionResult,
    };
  }
}
