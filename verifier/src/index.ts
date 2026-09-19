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
