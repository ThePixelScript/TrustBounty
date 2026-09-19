import path from 'node:path';
import { PathTraversalError } from './errors.ts';

/**
 * Validates and resolves a workspace root directory path.
 * Rejects path traversal attempts, null bytes, and filesystem root targets.
 */
export function validateAndResolveWorkspaceRoot(rootPath: string): string {
  if (typeof rootPath !== 'string' || !rootPath.trim()) {
    throw new PathTraversalError('Workspace root path must be a non-empty string');
  }

  if (rootPath.includes('\0')) {
    throw new PathTraversalError('Path contains invalid null byte');
  }

  const resolved = path.resolve(rootPath);
  const parsed = path.parse(resolved);

  // Disallow targeting filesystem root directly
  if (parsed.root === resolved) {
    throw new PathTraversalError(`Refusing to use filesystem root '${resolved}' as workspace root`);
  }

  return resolved;
}

/**
 * Ensures a candidate workspace path is strictly located within the expected root directory.
 */
export function assertWorkspaceWithinRoot(workspacePath: string, rootPath: string): void {
  const resolvedRoot = validateAndResolveWorkspaceRoot(rootPath);

  if (typeof workspacePath !== 'string' || !workspacePath.trim()) {
    throw new PathTraversalError('Workspace path must be a non-empty string');
  }

  if (workspacePath.includes('\0')) {
    throw new PathTraversalError('Workspace path contains invalid null byte');
  }

  const resolvedWorkspace = path.resolve(workspacePath);
  const relative = path.relative(resolvedRoot, resolvedWorkspace);

  if (relative === '' || relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new PathTraversalError(
      `Workspace path '${resolvedWorkspace}' is outside allowed root '${resolvedRoot}'`
    );
  }
}
