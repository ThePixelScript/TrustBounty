/**
 * TrustBounty Phase 2B-2: Criterion Evidence & Manifest Types.
 *
 * Strictly adheres to the frozen normative design in docs/PHASE2B2_CRITERIA_EVIDENCE_DESIGN.md.
 */

export type ManifestVerdict = 'PASS' | 'FAIL' | 'ERROR' | 'INCONCLUSIVE';

/**
 * Criterion evidence record for executable criteria (BUILD and TEST).
 */
export interface BuildTestCriterionEvidenceRecord {
  /** Criterion ID matching the specification */
  id: string;
  /** Criterion type */
  type: 'BUILD' | 'TEST';
  /** Mandatory settlement-authoritative flag */
  required: boolean;
  /** Exact executed command string */
  command: string;
  /** Evaluated verdict */
  verdict: ManifestVerdict;
  /** Diagnostic verdict reason if failed or errored */
  verdictReason?: string;
  /** Process exit code (null if terminated by signal, timeout, OOM, or skipped) */
  exitCode: number | null;
  /** Keccak-256 hash of retained stdout raw bytes (omitted if execution did not occur) */
  stdoutDigest?: string;
  /** Keccak-256 hash of retained stderr raw bytes (omitted if execution did not occur) */
  stderrDigest?: string;
  /** True if stdout exceeded verifier retention cap (omitted if execution did not occur) */
  stdoutTruncated?: boolean;
  /** True if stderr exceeded verifier retention cap (omitted if execution did not occur) */
  stderrTruncated?: boolean;
  /** High-level error classification */
  errorCategory: string;
}

/**
 * Criterion evidence record for Schema v1.1 COVERAGE criteria (unsupported for execution in v0.1).
 * Notice: command, stdoutDigest, stderrDigest, and truncation flags are strictly absent
 * because no container execution occurred.
 */
export interface CoverageCriterionEvidenceRecord {
  /** Criterion ID matching the specification */
  id: string;
  /** Criterion type */
  type: 'COVERAGE';
  /** Mandatory settlement-authoritative flag */
  required: boolean;
  /** Coverage comparison operator from specification */
  operator: '>=';
  /** Coverage threshold in basis points from specification */
  thresholdBps: number;
  /** Evaluated verdict (strictly INCONCLUSIVE in v0.1) */
  verdict: 'INCONCLUSIVE';
  /** Normative reason indicating lack of command in v1.1 */
  verdictReason: 'COVERAGE_EXECUTION_UNSUPPORTED_IN_V0_1';
  /** Process exit code (always null as no execution occurred) */
  exitCode: null;
}

/**
 * Closed union of all valid criterion evidence records in Phase 2B-2.
 */
export type CriterionEvidenceRecord =
  | BuildTestCriterionEvidenceRecord
  | CoverageCriterionEvidenceRecord;

/**
 * Canonical evidence manifest committed on-chain via evidenceHash.
 */
export interface CanonicalEvidenceManifest {
  /** Evidence specification version (strictly "1.0") */
  schemaVersion: '1.0';
  /** Cryptographic hash of the input AcceptanceSpecification (0x-prefixed 64 hex chars) */
  specHash: string;
  /**
   * Target bounty identifier as a canonical decimal string representation of the on-chain uint256.
   * Decimal string representation prevents JavaScript integer precision loss for values > 2^53 - 1.
   * Example: "42"
   */
  bountyId: string;
  /** Target repository coordinates */
  repository: {
    owner: string;
    name: string;
  };
  /** Base commit from specification */
  baseCommit: string;
  /** Evaluated submitted Git commit hash (40 hex characters) */
  submittedCommit: string;
  /** Environment image reference pinned by digest and verified platform */
  environment: {
    image: string;
    platform: 'linux/amd64';
  };
  /** Criteria results sorted ascending by criterion id */
  criteria: CriterionEvidenceRecord[];
  /** Overall aggregated settlement verdict derived from C_required */
  overallVerdict: ManifestVerdict;
  /** Diagnostic reason if overallVerdict is ERROR or INCONCLUSIVE */
  overallVerdictReason?: string;
  /** SemVer release of the verifier engine (e.g. "0.1.0") */
  verifierVersion: string;
}

/**
 * Unhashed operational telemetry written to runtime-metadata.json.
 */
export interface RuntimeMetadata {
  evidenceHash: string;
  bountyId: string;
  runId: string;
  verifierId?: string;
  timestamps: {
    startedAt: string;
    completedAt: string;
    totalDurationMs: number;
  };
  environment: {
    dockerEngineVersion?: string;
    hostOs?: string;
    hostKernel?: string;
    cpuCount?: number;
    totalMemoryBytes?: number;
  };
  criteriaExecution: Array<{
    id: string;
    containerId?: string;
    durationMs: number;
    hostWorkspacePath?: string;
  }>;
}

/**
 * In-memory evaluated result of a single criterion.
 */
export interface CriterionEvaluationResult {
  record: CriterionEvidenceRecord;
  stdoutBytes?: Buffer;
  stderrBytes?: Buffer;
  durationMs: number;
  containerId?: string;
}

/**
 * Complete in-memory execution result across all criteria in a specification.
 */
export interface MultiCriterionExecutionResult {
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
  criteriaResults: CriterionEvaluationResult[];
  overallVerdict: ManifestVerdict;
  overallVerdictReason?: string;
  startedAt: string;
  completedAt: string;
  totalDurationMs: number;
}

/**
 * Persisted evidence bundle information.
 */
export interface EvidenceBundle {
  evidenceHash: string;
  bundleDir: string;
  manifestPath: string;
  metadataPath: string;
  artifactsDir: string;
  manifest: CanonicalEvidenceManifest;
  runtimeMetadata: RuntimeMetadata;
}
