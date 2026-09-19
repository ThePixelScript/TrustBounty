# Verifier

## Purpose

Controlled software verification for TrustBounty bounties.

## Current Status

- **Phase 2A: Git Workspace Manager (Hardened)** — Implemented and tested (36/36 unit & adversarial tests passing).
- **Phase 2B: Docker Execution Runner** — Not implemented.
- **BUILD / TEST / COVERAGE Criteria Execution** — Not implemented.
- **Evidence Bundle Generation & Hashing** — Not implemented.
- **Ethereum / RPC Integration** — Not implemented.
- **V1 / V2 Daemons** — Not implemented.

---

## Phase 2A: Git Workspace Manager

The Git Workspace Manager (`@trustbounty/verifier`) fetches the exact contributor commit specified by TrustBounty and prepares an isolated detached-HEAD workspace for future verification stages.

### API

```typescript
import {
  prepareWorkspace,
  verifyExactHead,
  cleanupWorkspace,
  validateCommitHash,
  checkRepositoryIdentity,
} from '@trustbounty/verifier';
```

- **`prepareWorkspace(options: PrepareWorkspaceOptions): Promise<PreparedWorkspace>`**:
  - Validates requested commit format (strictly 40 hexadecimal characters).
  - Validates repository identity against specification and location.
  - Enforces strict protocol whitelist: only `https://` URLs accepted in production.
  - Rejects unsupported protocols (`ssh://`, `git://`, `rsync://`, `http://`), remote helpers (`ext::`, `fd::`), and scp-style syntax (`user@host:path`).
  - Rejects argument injection attempts (hyphens at start of `repoLocation`, `owner`, or `name`).
  - Restricts local `file:` / directory transport by default in production (`allowFileProtocol` must be explicitly set for test fixtures).
  - Enforces an absolute total deadline budget (`totalTimeoutMs`, default: 60,000 ms) covering the entire preparation lifecycle, with process-tree termination on abort.
  - Allocates a fresh isolated temporary workspace.
  - Initializes local git repository with secure flags (`core.autocrlf = false`).
  - Deterministically disables Git hooks using a dedicated empty hooks directory.
  - Deterministically neutralizes replacement objects via `core.useReplaceRefs = false` and `GIT_NO_REPLACE_OBJECTS = 1`.
  - Fetches the target commit without recursion, tags, or branch fallbacks.
  - Checks out the exact requested commit in detached HEAD state.
  - Verifies that resolved HEAD equals the requested commit.
  - Verifies detached HEAD via `git symbolic-ref -q HEAD` and `git rev-parse --abbrev-ref HEAD`.
  - Automatically cleans up the workspace if any preparation step fails or times out.
  - Never falls back to default branch, main branch, or tags.

- **`verifyExactHead(workspacePath: string, expectedCommit: string): Promise<HeadVerificationResult>`**:
  - Verifies that the workspace HEAD matches `expectedCommit` and remains in a detached state.

- **`cleanupWorkspace(workspacePath: string, options?: CleanupOptions): Promise<void>`**:
  - Safely deletes the workspace directory with path-containment validation.

---

### Security Hardening

#### 1. Strict Protocol Whitelist & Scheme Validation
- **Git Protocol Whitelist**: Child processes run with `GIT_ALLOW_PROTOCOL=https` (or `file:https` when `allowFileProtocol: true` in tests). Git transports for `ext`, `fd`, `ssh`, `git`, `rsync`, and arbitrary custom helpers are blocked at Git's transport layer.
- **Syntactic Scheme Validation**: In production, `repoLocation` must begin strictly with `https://`. Unencrypted `http://`, remote helpers containing `::`, and scp-style SSH syntax (`user@host:path`) are rejected prior to invoking Git.
- **File Protocol Scoping**: `protocol.file.allow = always` is completely removed from `.git/config`. Local filesystem and `file:` URLs are rejected by default in production. Only scoped integration tests may explicitly supply `allowFileProtocol: true`, which passes `-c protocol.file.allow=always` solely to the fetch invocation without persisting it in repository configuration.

#### 2. Replacement-Ref Protection
- **Vulnerability**: If a malicious repository contains replacement references (`refs/replace/<targetCommit>`), Git commands like `cat-file` or checkout may transparently resolve a forged object instead of the true requested commit.
- **Hardening**: Replacement objects are neutralized across all three layers:
  1. Environment: `GIT_NO_REPLACE_OBJECTS = 1`
  2. Command prefix: `-c core.useReplaceRefs=false`
  3. Repository config: `core.useReplaceRefs = false`
- Proved with an adversarial fixture containing a forged `refs/replace/` ref: the manager resolves and verifies the true original commit.

#### 3. Filter / Smudge Execution Boundary
- **Threat Model**: A repository `.gitattributes` can define `*.file filter=driver`. However, filter commands (`filter.<driver>.smudge`) must be defined in Git configuration. Remote repositories cannot modify the local repository's `.git/config`.
- **Mitigation**: TrustBounty's host configuration isolation (`GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=emptyConfig`, `GIT_CONFIG_SYSTEM=emptyConfig`) completely prevents inheriting external filter commands from host `~/.gitconfig` or `/etc/gitconfig`.
- **Conclusion**: Uncontrolled filter execution is already fully neutralized by configuration isolation. Risky wildcard configuration (`filter.*.smudge=`) is unnecessary and was avoided.

#### 4. Absolute Workspace Preparation Timeout
- **Total Budget**: A non-resetting total deadline (`totalTimeoutMs`, default 60,000 ms, bounded between 100 ms and 600,000 ms) covers the entire pipeline from directory creation through checkout and verification.
- **Process-Tree Termination**: If the deadline expires, the `AbortController` triggers immediate termination of the running Git child and its descendants (using `taskkill /pid /T /F` on Windows and `SIGKILL` on Unix).
- **Clean Failure**: The temporary workspace directory is immediately purged upon timeout, returning a typed `WorkspaceTimeoutError` without exposing credentials.

#### 5. Deterministic Hook Neutralization
- A dedicated, strictly empty directory (`.empty-hooks`) is created inside the workspace with restricted permissions (`0o700`), and `core.hooksPath` is set directly to this directory both in `.git/config` and via `-c core.hooksPath` on every execution.
- Any default template hooks in `.git/hooks` are purged immediately after `git init`.

#### 6. Host Configuration Isolation
- `runGit` isolates execution from the host environment:
  - `GIT_CONFIG_NOSYSTEM: '1'`
  - `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM` point to an empty configuration file.
  - `GIT_TERMINAL_PROMPT: '0'` and `GIT_ASKPASS: ''`
  - `GIT_ATTR_NOSYSTEM: '1'`
- Standard network transports (DNS, system TLS/CA certificates) remain external and functional for legitimate public HTTPS repositories.

---

### Security Boundary

> [!IMPORTANT]
> This module establishes that the prepared local repository's HEAD equals the requested Git SHA-1.
>
> It does **NOT** establish:
> - GitHub/GitLab ownership
> - PR authorship
> - repository legitimacy
> - semantic correctness
> - build correctness
> - test correctness
> - evidence correctness
> - verifier honesty
>
> Repository identity validation establishes syntactic namespace consistency between the supplied repository location and the specification's owner/name; it does not authenticate the remote hosting origin or prove repository ownership.
