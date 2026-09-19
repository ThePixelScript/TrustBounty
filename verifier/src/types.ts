import type { RepositoryRef } from '../../specification/src/types.ts';

export type { RepositoryRef };

/**
 * Result of executing a single Git command via child_process.execFile.
 */
export interface GitCommandResult {
  /** The command binary ('git') */
  command: string;
  /** The sanitized command arguments */
  args: string[];
  /** Process exit code (0 indicates success) */
  exitCode: number;
  /** Captured standard output */
  stdout: string;
  /** Captured standard error */
  stderr: string;
  /** Execution duration in milliseconds */
  durationMs: number;
}

/**
 * Options for preparing an isolated workspace.
 */
export interface PrepareWorkspaceOptions {
  /** Repository location (e.g. local directory path, file://, https://, or git@) */
  repoLocation: string;
  /** Authoritative specification repository identity (owner and name) */
  repository: RepositoryRef;
  /** Exact 40-character hexadecimal Git SHA-1 commit identifier */
  targetCommit: string;
  /** Optional temporary workspace root directory (defaults to OS temp / trustbounty-workspaces) */
  workspaceRoot?: string;
  /** Total overall deadline in milliseconds for workspace preparation (defaults to 60000) */
  totalTimeoutMs?: number;
  /** Legacy alias for totalTimeoutMs (defaults to 60000) */
  timeoutMs?: number;
  /** Test-only flag to allow local file: transport. Disabled by default in production. */
  allowFileProtocol?: boolean;
}

/**
 * Verified result of a successfully prepared isolated workspace.
 */
export interface PreparedWorkspace {
  /** Absolute path to the isolated temporary workspace directory */
  workspacePath: string;
  /** Requested 40-character commit (lowercase) */
  targetCommit: string;
  /** Verified resolved HEAD commit at the workspace */
  resolvedHead: string;
  /** Confirms workspace is in detached HEAD state (always true on preparation success) */
  isDetachedHead: boolean;
  /** Specification repository identity */
  repository: RepositoryRef;
  /** Audit log of all executed Git commands during workspace preparation */
  commandLog: GitCommandResult[];
}

/**
 * Result of verifying HEAD state against an expected commit.
 */
export interface HeadVerificationResult {
  /** True if resolved HEAD matches expected commit and HEAD is detached */
  verified: boolean;
  /** Resolved 40-character commit at HEAD */
  resolvedHead: string;
  /** Expected 40-character commit (lowercase) */
  expectedCommit: string;
  /** Whether HEAD is in a detached state */
  isDetached: boolean;
}

/**
 * Options for cleaning up an isolated workspace.
 */
export interface CleanupOptions {
  /** Optional expected workspace root directory to ensure deletion containment */
  workspaceRoot?: string;
}

/**
 * Result of checking repository identity against the supplied repository location.
 */
export interface RepositoryIdentityCheck {
  /** True if location matches specified owner and repository name */
  matches: boolean;
  /** True if owner segment was identified and matched */
  ownerMatches: boolean;
  /** True if repository name segment matched */
  nameMatches: boolean;
  /** Optional explanation if identity could not be fully verified or was mismatched */
  reason?: string;
}
