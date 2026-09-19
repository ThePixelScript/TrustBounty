import type { GitCommandResult } from './types.ts';

/**
 * Sanitizes potentially sensitive secrets (e.g. basic auth tokens in URLs) from strings.
 */
export function sanitizeSecret(input: string): string {
  if (typeof input !== 'string') return '';
  return input.replace(/:\/\/([^@\s]+)@/g, '://***@');
}

/**
 * Base error class for all Git workspace operations.
 */
export class GitWorkspaceError extends Error {
  public readonly commandResult?: GitCommandResult;

  constructor(message: string, commandResult?: GitCommandResult, cause?: unknown) {
    super(sanitizeSecret(message));
    this.name = 'GitWorkspaceError';
    this.commandResult = commandResult;
    if (cause !== undefined) {
      this.cause = cause;
    }
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/**
 * Thrown when the target commit identifier is not a valid 40-character hexadecimal SHA-1.
 */
export class InvalidCommitError extends GitWorkspaceError {
  public readonly targetCommit: string;

  constructor(targetCommit: string, reason?: string) {
    const sanitized = sanitizeSecret(String(targetCommit));
    super(
      `Invalid commit SHA-1 '${sanitized}': ${reason || 'must be exactly 40 hexadecimal characters'}`
    );
    this.name = 'InvalidCommitError';
    this.targetCommit = sanitized;
  }
}

/**
 * Thrown when creating or initializing the workspace directory fails.
 */
export class WorkspaceCreationError extends GitWorkspaceError {
  constructor(message: string, commandResult?: GitCommandResult, cause?: unknown) {
    super(`Workspace creation failed: ${message}`, commandResult, cause);
    this.name = 'WorkspaceCreationError';
  }
}

/**
 * Thrown when a path traversal attempt or unsafe filesystem path is detected.
 */
export class PathTraversalError extends GitWorkspaceError {
  constructor(message: string) {
    super(`Path safety violation: ${message}`);
    this.name = 'PathTraversalError';
  }
}

/**
 * Thrown when the specified remote repository is unreachable or does not exist.
 */
export class RepositoryUnavailableError extends GitWorkspaceError {
  public readonly repoLocation: string;

  constructor(repoLocation: string, message: string, commandResult?: GitCommandResult, cause?: unknown) {
    const sanitizedLocation = sanitizeSecret(repoLocation);
    super(
      `Repository unavailable at '${sanitizedLocation}': ${message}`,
      commandResult,
      cause
    );
    this.name = 'RepositoryUnavailableError';
    this.repoLocation = sanitizedLocation;
  }
}

/**
 * Thrown when the requested commit does not exist in the remote or local repository.
 */
export class CommitUnavailableError extends GitWorkspaceError {
  public readonly targetCommit: string;

  constructor(targetCommit: string, message: string, commandResult?: GitCommandResult, cause?: unknown) {
    const sanitizedCommit = sanitizeSecret(targetCommit);
    super(
      `Commit '${sanitizedCommit}' is unavailable in repository: ${message}`,
      commandResult,
      cause
    );
    this.name = 'CommitUnavailableError';
    this.targetCommit = sanitizedCommit;
  }
}

/**
 * Thrown when git clone or fetch fails.
 */
export class CloneFetchError extends GitWorkspaceError {
  constructor(message: string, commandResult?: GitCommandResult, cause?: unknown) {
    super(`Git fetch failed: ${message}`, commandResult, cause);
    this.name = 'CloneFetchError';
  }
}

/**
 * Thrown when git checkout fails.
 */
export class CheckoutError extends GitWorkspaceError {
  public readonly targetCommit: string;

  constructor(targetCommit: string, message: string, commandResult?: GitCommandResult, cause?: unknown) {
    const sanitizedCommit = sanitizeSecret(targetCommit);
    super(
      `Git checkout failed for commit '${sanitizedCommit}': ${message}`,
      commandResult,
      cause
    );
    this.name = 'CheckoutError';
    this.targetCommit = sanitizedCommit;
  }
}

/**
 * Thrown when resolved HEAD does not match the requested commit.
 */
export class UnexpectedHeadError extends GitWorkspaceError {
  public readonly expectedCommit: string;
  public readonly actualCommit: string;

  constructor(expectedCommit: string, actualCommit: string, commandResult?: GitCommandResult) {
    const sanitizedExpected = sanitizeSecret(expectedCommit);
    const sanitizedActual = sanitizeSecret(actualCommit);
    super(
      `Resolved HEAD mismatch: expected commit '${sanitizedExpected}', but resolved to '${sanitizedActual}'`,
      commandResult
    );
    this.name = 'UnexpectedHeadError';
    this.expectedCommit = sanitizedExpected;
    this.actualCommit = sanitizedActual;
  }
}

/**
 * Thrown when HEAD is not in a detached state (e.g. attached to a branch or tag).
 */
export class DetachedHeadError extends GitWorkspaceError {
  constructor(message: string, commandResult?: GitCommandResult) {
    super(`Detached HEAD requirement failed: ${message}`, commandResult);
    this.name = 'DetachedHeadError';
  }
}

/**
 * Thrown when cleaning up a workspace directory fails.
 */
export class CleanupError extends GitWorkspaceError {
  public readonly workspacePath: string;

  constructor(workspacePath: string, message: string, cause?: unknown) {
    const sanitizedPath = sanitizeSecret(workspacePath);
    super(`Failed to clean up workspace '${sanitizedPath}': ${message}`, undefined, cause);
    this.name = 'CleanupError';
    this.workspacePath = sanitizedPath;
  }
}

/**
 * Thrown when the supplied repository location contradicts the specification's repository identity.
 */
export class RepositoryIdentityMismatchError extends GitWorkspaceError {
  constructor(message: string) {
    super(`Repository identity mismatch: ${message}`);
    this.name = 'RepositoryIdentityMismatchError';
  }
}

/**
 * Thrown when workspace preparation exceeds the total timeout deadline.
 */
export class WorkspaceTimeoutError extends GitWorkspaceError {
  public readonly totalTimeoutMs: number;

  constructor(totalTimeoutMs: number, commandResult?: GitCommandResult) {
    super(`Workspace preparation exceeded total deadline of ${totalTimeoutMs}ms`, commandResult);
    this.name = 'WorkspaceTimeoutError';
    this.totalTimeoutMs = totalTimeoutMs;
  }
}
