/**
 * TrustBounty Off-Chain Verifier
 * Phase 2A: Git Workspace Manager
 *
 * SECURITY BOUNDARY:
 *
 * This module establishes that the prepared local repository's HEAD equals the requested Git SHA-1.
 *
 * It does NOT establish:
 * - GitHub/GitLab ownership
 * - PR authorship
 * - repository legitimacy
 * - semantic correctness
 * - build correctness
 * - test correctness
 * - evidence correctness
 * - verifier honesty
 */

export {
  prepareWorkspace,
  verifyExactHead,
  cleanupWorkspace,
  validateCommitHash,
} from './workspace.ts';

export { checkRepositoryIdentity } from './identity.ts';
export { runGit } from './git.ts';
export {
  validateAndResolveWorkspaceRoot,
  assertWorkspaceWithinRoot,
} from './path-safety.ts';

export type {
  RepositoryRef,
  GitCommandResult,
  PrepareWorkspaceOptions,
  PreparedWorkspace,
  HeadVerificationResult,
  CleanupOptions,
  RepositoryIdentityCheck,
} from './types.ts';

export {
  sanitizeSecret,
  GitWorkspaceError,
  InvalidCommitError,
  WorkspaceCreationError,
  PathTraversalError,
  RepositoryUnavailableError,
  CommitUnavailableError,
  CloneFetchError,
  CheckoutError,
  UnexpectedHeadError,
  DetachedHeadError,
  CleanupError,
  RepositoryIdentityMismatchError,
  WorkspaceTimeoutError,
} from './errors.ts';

// Phase 2B-1: Docker Sandbox Runner
export {
  executeInSandbox,
  reconcileStaleContainers,
  ENVIRONMENT_IMAGE_REGEX,
  RESOURCE_BOUNDS,
  ConcurrencyLimiter,
  defaultConcurrencyLimiter,
} from './docker.ts';

export type {
  ExecutionStatus,
  ErrorCategory,
  SandboxResources,
  ImagePullPolicy,
  SandboxConfig,
  ExecutionResult,
  ReconcileOptions,
} from './docker-types.ts';

// Phase 2B-2: Criterion Evaluation & Evidence Commitment
export {
  mapExecutionResultToVerdict,
  evaluateCoverageCriterion,
  aggregateVerdicts,
} from './criterion-evaluator.ts';

export {
  computeKeccak256Digest,
  canonicalizeManifest,
  computeEvidenceHash,
  validateCanonicalDecimalBountyId,
  buildCanonicalManifest,
  EMPTY_BYTES_KECCAK256,
} from './evidence-builder.ts';

export {
  storeEvidenceBundle,
  verifyEvidenceBundle,
  validateCriterionIdForPath,
  assertPathWithinDirectory,
} from './evidence-store.ts';

export {
  executeCriteria,
  runAndCommitVerification,
} from './multi-criterion-runner.ts';

export type {
  ManifestVerdict,
  BuildTestCriterionEvidenceRecord,
  CoverageCriterionEvidenceRecord,
  CriterionEvidenceRecord,
  CanonicalEvidenceManifest,
  RuntimeMetadata,
  CriterionEvaluationResult,
  MultiCriterionExecutionResult,
  EvidenceBundle,
} from './evidence-types.ts';

export {
  EvidenceCommitmentError,
  EvidenceCollisionError,
  EvidenceVerificationError,
  InvalidManifestError,
} from './errors.ts';
