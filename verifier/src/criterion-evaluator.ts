/**
 * TrustBounty Phase 2B-2: Criterion Evaluator.
 *
 * Implements:
 * 1. ExecutionResult -> CriterionVerdict mapping.
 * 2. Deterministic v0.1 Coverage evaluation (unsupported for execution).
 * 3. Required-aware multi-criterion verdict aggregation with lattice precedence.
 */

import type { ExecutionResult } from './docker-types.ts';
import type {
  CoverageCriterion,
} from '../../specification/src/types.ts';
import type {
  ManifestVerdict,
  CoverageCriterionEvidenceRecord,
  CriterionEvidenceRecord,
} from './evidence-types.ts';

export interface EvaluatedResultMapping {
  verdict: ManifestVerdict;
  verdictReason?: string;
  errorCategory: string;
}

/**
 * Maps a Phase 2B-1 Docker ExecutionResult to Phase 2B-2 ManifestVerdict.
 *
 * Deterministic mapping rules:
 * - SUCCESS -> PASS
 * - EXECUTION_FAILED -> FAIL
 * - TIMEOUT -> ERROR
 * - OOM -> ERROR
 * - INFRASTRUCTURE_ERROR -> ERROR
 *
 * Resource exhaustion or host failures are never attributed as contributor FAIL.
 */
export function mapExecutionResultToVerdict(result: ExecutionResult): EvaluatedResultMapping {
  switch (result.status) {
    case 'SUCCESS':
      return {
        verdict: 'PASS',
        errorCategory: 'NONE',
      };

    case 'EXECUTION_FAILED':
      return {
        verdict: 'FAIL',
        verdictReason: `PROCESS_EXITED_WITH_CODE_${result.exitCode ?? 'UNKNOWN'}`,
        errorCategory: 'NONE',
      };

    case 'TIMEOUT':
      return {
        verdict: 'ERROR',
        verdictReason: 'EXECUTION_TIMEOUT_EXCEEDED',
        errorCategory: result.errorCategory,
      };

    case 'OOM':
      return {
        verdict: 'ERROR',
        verdictReason: 'CONTAINER_KILLED_BY_OOM',
        errorCategory: result.errorCategory,
      };

    case 'INFRASTRUCTURE_ERROR':
      return {
        verdict: 'ERROR',
        verdictReason: `INFRASTRUCTURE_FAILURE_${result.errorCategory}`,
        errorCategory: result.errorCategory,
      };

    default:
      return {
        verdict: 'ERROR',
        verdictReason: 'UNKNOWN_EXECUTION_STATUS',
        errorCategory: result.errorCategory ?? 'CONFIG_ERROR',
      };
  }
}

/**
 * Produces the deterministic evidence record for a Schema v1.1 COVERAGE criterion.
 *
 * In Schema v1.1, Coverage has no command. The verifier does not invent a command,
 * does not parse host coverage reports, and does not launch a Docker container.
 * It strictly evaluates to INCONCLUSIVE.
 */
export function evaluateCoverageCriterion(
  criterion: CoverageCriterion
): CoverageCriterionEvidenceRecord {
  return {
    id: criterion.id,
    type: 'COVERAGE',
    required: criterion.required,
    operator: criterion.operator,
    thresholdBps: criterion.thresholdBps,
    verdict: 'INCONCLUSIVE',
    verdictReason: 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1',
    exitCode: null,
  };
}

export interface AggregationResult {
  overallVerdict: ManifestVerdict;
  overallVerdictReason?: string;
}

/**
 * Aggregates individual criterion verdicts into an overall settlement verdict.
 *
 * Normative rules:
 * 1. Zero-Required Rule: If zero criteria have `required === true`, overall verdict
 *    is immediately ERROR with reason 'INVALID_SPECIFICATION_NO_REQUIRED_CRITERIA'.
 * 2. Precedence over C_required:
 *    ERROR > INCONCLUSIVE > FAIL > PASS
 * 3. Optional criteria (`required === false`) are evaluated and attested, but never
 *    override or affect the settlement verdict.
 */
export function aggregateVerdicts(criteria: CriterionEvidenceRecord[]): AggregationResult {
  const requiredCriteria = criteria.filter((c) => c.required === true);

  // 1. Zero-Required Rule
  if (requiredCriteria.length === 0) {
    return {
      overallVerdict: 'ERROR',
      overallVerdictReason: 'INVALID_SPECIFICATION_NO_REQUIRED_CRITERIA',
    };
  }

  // 2. ERROR check on required criteria
  const firstError = requiredCriteria.find((c) => c.verdict === 'ERROR');
  if (firstError) {
    return {
      overallVerdict: 'ERROR',
      overallVerdictReason: firstError.verdictReason ?? 'REQUIRED_CRITERION_ERRORED',
    };
  }

  // 3. INCONCLUSIVE check on required criteria
  const firstInconclusive = requiredCriteria.find((c) => c.verdict === 'INCONCLUSIVE');
  if (firstInconclusive) {
    return {
      overallVerdict: 'INCONCLUSIVE',
      overallVerdictReason: firstInconclusive.verdictReason ?? 'REQUIRED_CRITERION_INCONCLUSIVE',
    };
  }

  // 4. FAIL check on required criteria
  const firstFail = requiredCriteria.find((c) => c.verdict === 'FAIL');
  if (firstFail) {
    return {
      overallVerdict: 'FAIL',
      overallVerdictReason: firstFail.verdictReason,
    };
  }

  // 5. All required criteria passed
  return {
    overallVerdict: 'PASS',
  };
}
