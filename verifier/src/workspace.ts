/**
 * TrustBounty Phase 2A: Git Workspace Manager
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

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type {
  PrepareWorkspaceOptions,
  PreparedWorkspace,
  HeadVerificationResult,
  CleanupOptions,
  GitCommandResult,
} from './types.ts';
import {
  InvalidCommitError,
  WorkspaceCreationError,
  WorkspaceTimeoutError,
  CommitUnavailableError,
  RepositoryUnavailableError,
  CheckoutError,
  UnexpectedHeadError,
  DetachedHeadError,
  CleanupError,
  RepositoryIdentityMismatchError,
} from './errors.ts';
import { runGit } from './git.ts';
import {
  validateAndResolveWorkspaceRoot,
  assertWorkspaceWithinRoot,
} from './path-safety.ts';
import { checkRepositoryIdentity } from './identity.ts';

const COMMIT_SHA1_REGEX = /^[0-9a-fA-F]{40}$/;
const MIN_TIMEOUT_MS = 100;
const MAX_TIMEOUT_MS = 600000;
const DEFAULT_TIMEOUT_MS = 60000;

/**
 * Validates that a string is a well-formed 40-character hexadecimal SHA-1 commit.
 */
export function validateCommitHash(commit: string): string {
  if (typeof commit !== 'string' || !COMMIT_SHA1_REGEX.test(commit.trim())) {
    throw new InvalidCommitError(
      commit,
      'commit hash must be exactly 40 hexadecimal characters'
    );
  }
  return commit.trim().toLowerCase();
}

/**
 * Prepares an isolated workspace checked out to the exact requested Git SHA-1 in detached HEAD state.
 * Enforces an absolute end-to-end total preparation deadline.
 */
export async function prepareWorkspace(
  options: PrepareWorkspaceOptions
): Promise<PreparedWorkspace> {
  // 1. Validate total timeout deadline budget
  const totalTimeoutMs = options.totalTimeoutMs ?? options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  if (typeof totalTimeoutMs !== 'number' || totalTimeoutMs < MIN_TIMEOUT_MS || totalTimeoutMs > MAX_TIMEOUT_MS) {
    throw new WorkspaceCreationError(
      `Invalid total timeout ${totalTimeoutMs}ms: must be between ${MIN_TIMEOUT_MS}ms and ${MAX_TIMEOUT_MS}ms`
    );
  }

  const deadline = Date.now() + totalTimeoutMs;
  const abortController = new AbortController();
  const timeoutTimer = setTimeout(() => {
    abortController.abort(new WorkspaceTimeoutError(totalTimeoutMs));
  }, totalTimeoutMs);

  function checkDeadline(): number {
    const remaining = deadline - Date.now();
    if (remaining <= 0 || abortController.signal.aborted) {
      throw new WorkspaceTimeoutError(totalTimeoutMs);
    }
    return remaining;
  }

  // 2. Validate commit identifier before any filesystem or Git operation
  const normalizedCommit = validateCommitHash(options.targetCommit);

  // 3. Validate repository identity and protocol scheme
  const identityCheck = checkRepositoryIdentity(options.repoLocation, options.repository, {
    allowFileProtocol: options.allowFileProtocol,
  });
  if (!identityCheck.matches) {
    clearTimeout(timeoutTimer);
    if (
      identityCheck.reason?.includes('restricted by default in production') ||
      identityCheck.reason?.includes('Protocol') ||
      identityCheck.reason?.includes('transport')
    ) {
      throw new RepositoryUnavailableError(options.repoLocation, identityCheck.reason);
    }
    throw new RepositoryIdentityMismatchError(
      identityCheck.reason || 'Repository location does not match specified repository identity'
    );
  }

  // 4. Resolve and create isolated temporary workspace root
  checkDeadline();
  const root = options.workspaceRoot
    ? validateAndResolveWorkspaceRoot(options.workspaceRoot)
    : path.join(os.tmpdir(), 'trustbounty-workspaces');

  try {
    await fs.promises.mkdir(root, { recursive: true, mode: 0o700 });
  } catch (err) {
    clearTimeout(timeoutTimer);
    throw new WorkspaceCreationError(`Failed to create workspace root directory '${root}'`, undefined, err);
  }

  let workspacePath: string;
  try {
    workspacePath = await fs.promises.mkdtemp(path.join(root, 'tb-ws-'));
  } catch (err) {
    clearTimeout(timeoutTimer);
    throw new WorkspaceCreationError('Failed to allocate temporary workspace directory', undefined, err);
  }

  // Create dedicated empty directory for hook neutralization
  const emptyHooksDir = path.join(workspacePath, '.empty-hooks');
  try {
    await fs.promises.mkdir(emptyHooksDir, { recursive: true, mode: 0o700 });
  } catch (err) {
    clearTimeout(timeoutTimer);
    throw new WorkspaceCreationError('Failed to allocate empty hooks directory', undefined, err);
  }

  const commandLog: GitCommandResult[] = [];

  async function execute(args: string[]): Promise<GitCommandResult> {
    const remainingMs = checkDeadline();
    const result = await runGit(args, {
      cwd: workspacePath,
      timeoutMs: remainingMs,
      signal: abortController.signal,
      hooksPath: emptyHooksDir,
      allowFileProtocol: options.allowFileProtocol,
    });
    commandLog.push(result);

    if (abortController.signal.aborted) {
      throw new WorkspaceTimeoutError(totalTimeoutMs, result);
    }

    return result;
  }

  try {
    // 5. Initialize local git repository
    const initRes = await execute(['init']);
    if (initRes.exitCode !== 0) {
      throw new WorkspaceCreationError('Failed to initialize Git repository', initRes);
    }

    // 6. Neutralize any template hooks generated by git init
    try {
      await fs.promises.rm(path.join(workspacePath, '.git', 'hooks'), { recursive: true, force: true });
    } catch {
      // Best-effort removal of initial template hooks
    }

    // 7. Apply strictly secure configuration:
    // - core.hooksPath -> verified empty directory
    // - core.useReplaceRefs -> false (neutralizes replacement refs)
    // - core.autocrlf -> false (prevents line-ending mutation)
    await execute(['config', 'core.hooksPath', emptyHooksDir]);
    await execute(['config', 'core.useReplaceRefs', 'false']);
    await execute(['config', 'core.autocrlf', 'false']);

    // 8. Configure remote origin using '--' to prevent flag injection
    const remoteRes = await execute(['remote', 'add', 'origin', '--', options.repoLocation]);
    if (remoteRes.exitCode !== 0) {
      throw new WorkspaceCreationError('Failed to configure remote origin', remoteRes);
    }

    // 9. Fetch the specific requested commit
    const fetchArgs: string[] = [];
    if (options.allowFileProtocol) {
      fetchArgs.push('-c', 'protocol.file.allow=always');
    }
    fetchArgs.push(
      'fetch',
      '--depth=1',
      '--no-tags',
      '--no-recurse-submodules',
      'origin',
      normalizedCommit
    );

    const fetchRes = await execute(fetchArgs);

    if (fetchRes.exitCode !== 0) {
      const stderr = fetchRes.stderr.toLowerCase();
      // Distinguish repository unavailability from commit unavailability
      if (
        stderr.includes('does not appear to be a git repository') ||
        stderr.includes('fatal: repository') ||
        stderr.includes('could not resolve host') ||
        stderr.includes('fatal: unable to access') ||
        stderr.includes('connection refused') ||
        stderr.includes('not found') ||
        stderr.includes('transport')
      ) {
        throw new RepositoryUnavailableError(
          options.repoLocation,
          fetchRes.stderr.trim(),
          fetchRes
        );
      }

      // If shallow fetch by SHA-1 was not supported by the remote, attempt standard fetch
      const fallbackFetchArgs: string[] = [];
      if (options.allowFileProtocol) {
        fallbackFetchArgs.push('-c', 'protocol.file.allow=always');
      }
      fallbackFetchArgs.push(
        'fetch',
        '--no-tags',
        '--no-recurse-submodules',
        'origin'
      );

      const fallbackFetch = await execute(fallbackFetchArgs);

      if (fallbackFetch.exitCode !== 0) {
        const fallbackStderr = fallbackFetch.stderr.toLowerCase();
        if (
          fallbackStderr.includes('does not appear to be a git repository') ||
          fallbackStderr.includes('fatal: repository') ||
          fallbackStderr.includes('could not resolve host') ||
          fallbackStderr.includes('fatal: unable to access') ||
          fallbackStderr.includes('connection refused') ||
          fallbackStderr.includes('transport')
        ) {
          throw new RepositoryUnavailableError(
            options.repoLocation,
            fallbackFetch.stderr.trim(),
            fallbackFetch
          );
        }
      }

      // Verify whether the commit object exists locally after fetch
      const catFile = await execute(['cat-file', '-e', `${normalizedCommit}^{commit}`]);
      if (catFile.exitCode !== 0) {
        // Never fall back to branch, tag, or default HEAD
        throw new CommitUnavailableError(
          normalizedCommit,
          `Commit '${normalizedCommit}' does not exist in remote repository`,
          fetchRes
        );
      }
    }

    // 10. Checkout exact commit with detached HEAD and no submodule recursion
    const checkoutRes = await execute([
      'checkout',
      '--detach',
      '--no-recurse-submodules',
      normalizedCommit,
    ]);
    if (checkoutRes.exitCode !== 0) {
      throw new CheckoutError(normalizedCommit, checkoutRes.stderr.trim(), checkoutRes);
    }

    // 11. Resolve full HEAD commit and verify exact match
    const revParseRes = await execute(['rev-parse', 'HEAD']);
    if (revParseRes.exitCode !== 0) {
      throw new CheckoutError(normalizedCommit, 'Failed to resolve HEAD revision', revParseRes);
    }

    const resolvedHead = revParseRes.stdout.trim().toLowerCase();
    if (resolvedHead !== normalizedCommit) {
      throw new UnexpectedHeadError(normalizedCommit, resolvedHead, revParseRes);
    }

    // 12. Verify detached HEAD state
    const symbolicRefRes = await execute(['symbolic-ref', '-q', 'HEAD']);
    if (symbolicRefRes.exitCode === 0) {
      throw new DetachedHeadError(
        `HEAD is attached to ref '${symbolicRefRes.stdout.trim()}', expected detached HEAD`,
        symbolicRefRes
      );
    }

    const abbrevRefRes = await execute(['rev-parse', '--abbrev-ref', 'HEAD']);
    if (abbrevRefRes.stdout.trim() !== 'HEAD') {
      throw new DetachedHeadError(
        `HEAD is not detached: rev-parse --abbrev-ref returned '${abbrevRefRes.stdout.trim()}'`,
        abbrevRefRes
      );
    }

    return {
      workspacePath,
      targetCommit: normalizedCommit,
      resolvedHead,
      isDetachedHead: true,
      repository: options.repository,
      commandLog,
    };
  } catch (error) {
    // Clean up temporary workspace directory on any preparation failure or timeout
    try {
      await cleanupWorkspace(workspacePath, { workspaceRoot: root });
    } catch {
      // Best-effort cleanup on failure; original error is preserved
    }
    throw error;
  } finally {
    clearTimeout(timeoutTimer);
  }
}

/**
 * Verifies that a workspace's HEAD matches the expected commit and is detached.
 */
export async function verifyExactHead(
  workspacePath: string,
  expectedCommit: string
): Promise<HeadVerificationResult> {
  const normalizedExpected = validateCommitHash(expectedCommit);

  const revParseRes = await runGit(['rev-parse', 'HEAD'], { cwd: workspacePath });
  if (revParseRes.exitCode !== 0) {
    return {
      verified: false,
      resolvedHead: '',
      expectedCommit: normalizedExpected,
      isDetached: false,
    };
  }

  const resolvedHead = revParseRes.stdout.trim().toLowerCase();

  const symbolicRefRes = await runGit(['symbolic-ref', '-q', 'HEAD'], { cwd: workspacePath });
  const abbrevRefRes = await runGit(['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: workspacePath });

  const isDetached = symbolicRefRes.exitCode !== 0 && abbrevRefRes.stdout.trim() === 'HEAD';
  const matches = resolvedHead === normalizedExpected;

  return {
    verified: matches && isDetached,
    resolvedHead,
    expectedCommit: normalizedExpected,
    isDetached,
  };
}

/**
 * Safely removes a prepared workspace directory.
 */
export async function cleanupWorkspace(
  workspacePath: string,
  options?: CleanupOptions
): Promise<void> {
  if (typeof workspacePath !== 'string' || !workspacePath.trim()) {
    throw new CleanupError(workspacePath, 'Workspace path must be a non-empty string');
  }

  const resolvedWorkspace = path.resolve(workspacePath);

  if (options?.workspaceRoot) {
    assertWorkspaceWithinRoot(resolvedWorkspace, options.workspaceRoot);
  }

  const parsed = path.parse(resolvedWorkspace);
  if (parsed.root === resolvedWorkspace) {
    throw new CleanupError(workspacePath, 'Refusing to delete filesystem root directory');
  }

  try {
    await fs.promises.rm(resolvedWorkspace, {
      recursive: true,
      force: true,
      maxRetries: 5,
      retryDelay: 50,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    throw new CleanupError(workspacePath, message, err);
  }
}
