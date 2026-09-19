/**
 * TrustBounty Phase 2B-1: Minimal Secure Docker Sandbox Runner
 *
 * Implements bounded, non-root, capability-stripped, network-isolated
 * container execution with explicit lifecycle state management.
 *
 * LIFECYCLE:
 * docker create -> acquire container ID -> docker inspect (validate security config)
 * -> docker start (continuous output draining) -> docker wait -> inspect final state
 * -> classify result -> docker rm -f -> verify cleanup
 *
 * SECURITY INVARIANTS:
 * - Host shell is NEVER invoked (execFile / spawn with shell: false only).
 * - Untrusted repository code NEVER executes directly on the verifier host.
 * - Source /input is strictly read-only bind mounted.
 * - Untrusted execution occurs in isolated, executable /workspace tmpfs.
 * - Network is completely disabled (--network none).
 * - Non-root user (10001:10001) with zero Linux capabilities (--cap-drop ALL).
 * - No new privileges flag enabled (--security-opt no-new-privileges=true).
 * - Root filesystem is read-only (--read-only).
 * - Pinned digest image reference enforced (--platform linux/amd64).
 */

import { execFile, execFileSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import type {
  SandboxConfig,
  SandboxResources,
  ExecutionResult,
  ExecutionStatus,
  ErrorCategory,
  ImagePullPolicy,
  ReconcileOptions,
} from './docker-types.ts';

/**
 * Strict image reference format requirement: <registry>/<image>@sha256:<64 lowercase hex characters>
 */
export const ENVIRONMENT_IMAGE_REGEX = /^[^\s@]+@sha256:[0-9a-f]{64}$/;

/**
 * Commit SHA-1 format regex (40 hexadecimal characters)
 */
const COMMIT_SHA1_REGEX = /^[0-9a-fA-F]{40}$/;

/**
 * Hard resource bounds to prevent host denial-of-service or misconfiguration.
 */
export const RESOURCE_BOUNDS = {
  cpus: { min: 0.5, max: 8.0, default: 2.0 },
  memoryBytes: {
    min: 512 * 1024 * 1024, // 512 MB
    max: 16 * 1024 * 1024 * 1024, // 16 GB
    default: 4 * 1024 * 1024 * 1024, // 4 GB
  },
  memorySwapBytes: {
    min: 512 * 1024 * 1024,
    max: 16 * 1024 * 1024 * 1024,
    default: 4 * 1024 * 1024 * 1024,
  },
  pidsLimit: { min: 64, max: 1024, default: 256 },
  workspaceTmpfsBytes: {
    min: 512 * 1024 * 1024, // 512 MB
    max: 8 * 1024 * 1024 * 1024, // 8 GB
    default: 2 * 1024 * 1024 * 1024, // 2 GB
  },
  tmpTmpfsBytes: {
    min: 64 * 1024 * 1024, // 64 MB
    max: 2 * 1024 * 1024 * 1024, // 2 GB
    default: 512 * 1024 * 1024, // 512 MB
  },
  shmSizeBytes: {
    min: 64 * 1024 * 1024, // 64 MB
    max: 1024 * 1024 * 1024, // 1 GB
    default: 256 * 1024 * 1024, // 256 MB
  },
  maxStdoutBytes: {
    min: 1024 * 1024, // 1 MB
    max: 20 * 1024 * 1024, // 20 MB
    default: 5 * 1024 * 1024, // 5 MB
  },
  maxStderrBytes: {
    min: 1024 * 1024, // 1 MB
    max: 20 * 1024 * 1024, // 20 MB
    default: 5 * 1024 * 1024, // 5 MB
  },
  activeOutputAbuseBytes: {
    min: 10 * 1024 * 1024, // 10 MB
    max: 50 * 1024 * 1024, // 50 MB
    default: 20 * 1024 * 1024, // 20 MB
  },
  timeoutMs: {
    min: 5_000, // 5 seconds
    max: 600_000, // 10 minutes
    default: 180_000, // 3 minutes
  },
} as const;

/**
 * Validated and normalized resource constraints.
 */
export interface ResolvedResources {
  cpus: number;
  memoryBytes: number;
  memorySwapBytes: number;
  pidsLimit: number;
  workspaceTmpfsBytes: number;
  tmpTmpfsBytes: number;
  shmSizeBytes: number;
  maxStdoutBytes: number;
  maxStderrBytes: number;
  activeOutputAbuseBytes: number;
  timeoutMs: number;
}

/**
 * Concurrency limiter to bound aggregate verifier host load.
 */
export class ConcurrencyLimiter {
  public maxConcurrent: number;
  private active = 0;
  private queue: Array<() => void> = [];

  constructor(maxConcurrent: number = 2) {
    this.maxConcurrent = maxConcurrent;
  }

  async acquire(): Promise<() => void> {
    if (this.active < this.maxConcurrent) {
      this.active++;
      let released = false;
      return () => {
        if (!released) {
          released = true;
          this.release();
        }
      };
    }

    return new Promise((resolve) => {
      this.queue.push(() => {
        this.active++;
        let released = false;
        resolve(() => {
          if (!released) {
            released = true;
            this.release();
          }
        });
      });
    });
  }

  private release(): void {
    this.active--;
    if (this.queue.length > 0) {
      const next = this.queue.shift()!;
      next();
    }
  }

  getActiveCount(): number {
    return this.active;
  }

  getQueueLength(): number {
    return this.queue.length;
  }
}

/**
 * Global default concurrency limiter (default: 2 concurrent container executions).
 */
export const defaultConcurrencyLimiter = new ConcurrencyLimiter(2);

/**
 * Terminates a child process tree reliably across Windows and Unix platforms.
 */
function killChildProcess(childProc: { pid?: number; kill: (signal?: NodeJS.Signals) => boolean }): void {
  if (!childProc.pid) return;
  if (process.platform === 'win32') {
    try {
      execFileSync('taskkill', ['/pid', String(childProc.pid), '/T', '/F'], {
        stdio: 'ignore',
      });
    } catch {
      // Best effort process tree termination
    }
  } else {
    try {
      childProc.kill('SIGKILL');
    } catch {
      // Best effort
    }
  }
}

/**
 * Executes a Docker CLI command using exact argument arrays without host shell invocation.
 */
export async function runDockerCli(
  args: string[],
  options: { timeoutMs?: number; signal?: AbortSignal } = {}
): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    let child: ReturnType<typeof execFile>;

    const abortHandler = () => {
      if (child) {
        killChildProcess(child);
      }
    };

    if (options.signal) {
      if (options.signal.aborted) {
        abortHandler();
      } else {
        options.signal.addEventListener('abort', abortHandler, { once: true });
      }
    }

    child = execFile(
      'docker',
      args,
      {
        timeout: options.timeoutMs ?? 60_000,
        signal: options.signal,
        maxBuffer: 10 * 1024 * 1024,
        windowsHide: true,
        shell: false,
      },
      (error, stdout, stderr) => {
        if (options.signal) {
          options.signal.removeEventListener('abort', abortHandler);
        }

        let exitCode = 0;
        if (error) {
          const status = (error as unknown as { status?: number }).status;
          if (typeof status === 'number') {
            exitCode = status;
          } else if (
            typeof (error as unknown as { code?: number | string }).code === 'number'
          ) {
            exitCode = (error as unknown as { code: number }).code;
          } else {
            exitCode = 1;
          }
        }

        resolve({
          exitCode,
          stdout: (stdout || '').toString(),
          stderr: (stderr || '').toString(),
        });
      }
    );
  });
}

/**
 * Validates and normalizes resource options against hard bounds.
 */
export function validateAndResolveResources(
  input?: SandboxResources
): ResolvedResources {
  const cpus = input?.cpus ?? RESOURCE_BOUNDS.cpus.default;
  if (
    typeof cpus !== 'number' ||
    cpus < RESOURCE_BOUNDS.cpus.min ||
    cpus > RESOURCE_BOUNDS.cpus.max
  ) {
    throw new Error(
      `Invalid cpus limit ${cpus}: must be between ${RESOURCE_BOUNDS.cpus.min} and ${RESOURCE_BOUNDS.cpus.max}`
    );
  }

  const memoryBytes = input?.memoryBytes ?? RESOURCE_BOUNDS.memoryBytes.default;
  if (
    typeof memoryBytes !== 'number' ||
    memoryBytes < RESOURCE_BOUNDS.memoryBytes.min ||
    memoryBytes > RESOURCE_BOUNDS.memoryBytes.max
  ) {
    throw new Error(
      `Invalid memoryBytes limit ${memoryBytes}: must be between ${RESOURCE_BOUNDS.memoryBytes.min} and ${RESOURCE_BOUNDS.memoryBytes.max}`
    );
  }

  const memorySwapBytes =
    input?.memorySwapBytes ?? Math.max(memoryBytes, RESOURCE_BOUNDS.memorySwapBytes.default);
  if (
    typeof memorySwapBytes !== 'number' ||
    memorySwapBytes < memoryBytes ||
    memorySwapBytes > RESOURCE_BOUNDS.memorySwapBytes.max
  ) {
    throw new Error(
      `Invalid memorySwapBytes limit ${memorySwapBytes}: must be between memoryBytes (${memoryBytes}) and ${RESOURCE_BOUNDS.memorySwapBytes.max}`
    );
  }

  const pidsLimit = input?.pidsLimit ?? RESOURCE_BOUNDS.pidsLimit.default;
  if (
    typeof pidsLimit !== 'number' ||
    pidsLimit < RESOURCE_BOUNDS.pidsLimit.min ||
    pidsLimit > RESOURCE_BOUNDS.pidsLimit.max
  ) {
    throw new Error(
      `Invalid pidsLimit ${pidsLimit}: must be between ${RESOURCE_BOUNDS.pidsLimit.min} and ${RESOURCE_BOUNDS.pidsLimit.max}`
    );
  }

  const workspaceTmpfsBytes =
    input?.workspaceTmpfsBytes ?? RESOURCE_BOUNDS.workspaceTmpfsBytes.default;
  if (
    typeof workspaceTmpfsBytes !== 'number' ||
    workspaceTmpfsBytes < RESOURCE_BOUNDS.workspaceTmpfsBytes.min ||
    workspaceTmpfsBytes > RESOURCE_BOUNDS.workspaceTmpfsBytes.max
  ) {
    throw new Error(
      `Invalid workspaceTmpfsBytes ${workspaceTmpfsBytes}: must be between ${RESOURCE_BOUNDS.workspaceTmpfsBytes.min} and ${RESOURCE_BOUNDS.workspaceTmpfsBytes.max}`
    );
  }

  const tmpTmpfsBytes = input?.tmpTmpfsBytes ?? RESOURCE_BOUNDS.tmpTmpfsBytes.default;
  if (
    typeof tmpTmpfsBytes !== 'number' ||
    tmpTmpfsBytes < RESOURCE_BOUNDS.tmpTmpfsBytes.min ||
    tmpTmpfsBytes > RESOURCE_BOUNDS.tmpTmpfsBytes.max
  ) {
    throw new Error(
      `Invalid tmpTmpfsBytes ${tmpTmpfsBytes}: must be between ${RESOURCE_BOUNDS.tmpTmpfsBytes.min} and ${RESOURCE_BOUNDS.tmpTmpfsBytes.max}`
    );
  }

  const shmSizeBytes = input?.shmSizeBytes ?? RESOURCE_BOUNDS.shmSizeBytes.default;
  if (
    typeof shmSizeBytes !== 'number' ||
    shmSizeBytes < RESOURCE_BOUNDS.shmSizeBytes.min ||
    shmSizeBytes > RESOURCE_BOUNDS.shmSizeBytes.max
  ) {
    throw new Error(
      `Invalid shmSizeBytes ${shmSizeBytes}: must be between ${RESOURCE_BOUNDS.shmSizeBytes.min} and ${RESOURCE_BOUNDS.shmSizeBytes.max}`
    );
  }

  const maxStdoutBytes =
    input?.maxStdoutBytes ?? RESOURCE_BOUNDS.maxStdoutBytes.default;
  if (
    typeof maxStdoutBytes !== 'number' ||
    maxStdoutBytes < RESOURCE_BOUNDS.maxStdoutBytes.min ||
    maxStdoutBytes > RESOURCE_BOUNDS.maxStdoutBytes.max
  ) {
    throw new Error(
      `Invalid maxStdoutBytes ${maxStdoutBytes}: must be between ${RESOURCE_BOUNDS.maxStdoutBytes.min} and ${RESOURCE_BOUNDS.maxStdoutBytes.max}`
    );
  }

  const maxStderrBytes =
    input?.maxStderrBytes ?? RESOURCE_BOUNDS.maxStderrBytes.default;
  if (
    typeof maxStderrBytes !== 'number' ||
    maxStderrBytes < RESOURCE_BOUNDS.maxStderrBytes.min ||
    maxStderrBytes > RESOURCE_BOUNDS.maxStderrBytes.max
  ) {
    throw new Error(
      `Invalid maxStderrBytes ${maxStderrBytes}: must be between ${RESOURCE_BOUNDS.maxStderrBytes.min} and ${RESOURCE_BOUNDS.maxStderrBytes.max}`
    );
  }

  const activeOutputAbuseBytes =
    input?.activeOutputAbuseBytes ?? RESOURCE_BOUNDS.activeOutputAbuseBytes.default;
  if (
    typeof activeOutputAbuseBytes !== 'number' ||
    activeOutputAbuseBytes < RESOURCE_BOUNDS.activeOutputAbuseBytes.min ||
    activeOutputAbuseBytes > RESOURCE_BOUNDS.activeOutputAbuseBytes.max
  ) {
    throw new Error(
      `Invalid activeOutputAbuseBytes ${activeOutputAbuseBytes}: must be between ${RESOURCE_BOUNDS.activeOutputAbuseBytes.min} and ${RESOURCE_BOUNDS.activeOutputAbuseBytes.max}`
    );
  }

  const timeoutMs = input?.timeoutMs ?? RESOURCE_BOUNDS.timeoutMs.default;
  if (
    typeof timeoutMs !== 'number' ||
    timeoutMs < RESOURCE_BOUNDS.timeoutMs.min ||
    timeoutMs > RESOURCE_BOUNDS.timeoutMs.max
  ) {
    throw new Error(
      `Invalid timeoutMs ${timeoutMs}: must be between ${RESOURCE_BOUNDS.timeoutMs.min} and ${RESOURCE_BOUNDS.timeoutMs.max}`
    );
  }

  return {
    cpus,
    memoryBytes,
    memorySwapBytes,
    pidsLimit,
    workspaceTmpfsBytes,
    tmpTmpfsBytes,
    shmSizeBytes,
    maxStdoutBytes,
    maxStderrBytes,
    activeOutputAbuseBytes,
    timeoutMs,
  };
}

/**
 * Validates that workspace path is a non-empty, absolute, existing directory.
 */
export function validateWorkspacePath(workspacePath: string): string {
  if (typeof workspacePath !== 'string' || !workspacePath.trim()) {
    throw new Error('Workspace path must be a non-empty string');
  }

  if (workspacePath.includes('\0')) {
    throw new Error('Workspace path contains invalid null byte');
  }

  const resolved = path.resolve(workspacePath);
  const parsed = path.parse(resolved);

  if (parsed.root === resolved) {
    throw new Error(`Refusing to use filesystem root '${resolved}' as workspace`);
  }

  if (!fs.existsSync(resolved)) {
    throw new Error(`Workspace path does not exist: '${resolved}'`);
  }

  const stat = fs.statSync(resolved);
  if (!stat.isDirectory()) {
    throw new Error(`Workspace path is not a directory: '${resolved}'`);
  }

  return resolved;
}

/**
 * Validates image reference against exact SHA-256 digest regex.
 */
export function validateImageReference(image: string): void {
  if (typeof image !== 'string' || !ENVIRONMENT_IMAGE_REGEX.test(image.trim())) {
    throw new Error(
      `Invalid container image reference '${image}': must match <image-ref>@sha256:<64 lowercase hex characters>`
    );
  }
}

/**
 * Validates commit SHA-1 format.
 */
export function validateCommit(commit: string): string {
  if (typeof commit !== 'string' || !COMMIT_SHA1_REGEX.test(commit.trim())) {
    throw new Error(
      `Invalid commit hash '${commit}': must be exactly 40 hexadecimal characters`
    );
  }
  return commit.trim().toLowerCase();
}

/**
 * Resolves, pulls if permitted, and inspects the execution container image.
 */
export async function ensureAndInspectImage(
  image: string,
  pullPolicy: ImagePullPolicy = 'if-missing'
): Promise<{ imageId: string; architecture: string; os: string }> {
  validateImageReference(image);

  // Check if image exists locally
  const inspectRes = await runDockerCli(['image', 'inspect', image]);

  if (inspectRes.exitCode !== 0) {
    if (pullPolicy === 'never') {
      throw new Error(
        `Container image '${image}' is not available locally and pull policy is 'never'`
      );
    }

    // Pull strictly by digest with explicit platform
    const pullRes = await runDockerCli(
      ['pull', '--platform', 'linux/amd64', image],
      { timeoutMs: 300_000 }
    );

    if (pullRes.exitCode !== 0) {
      throw new Error(
        `Failed to pull container image '${image}': ${pullRes.stderr.trim() || pullRes.stdout.trim()}`
      );
    }
  }

  // Inspect resolved image
  const verifyInspect = await runDockerCli(['image', 'inspect', image]);
  if (verifyInspect.exitCode !== 0) {
    throw new Error(
      `Failed to inspect container image '${image}': ${verifyInspect.stderr.trim()}`
    );
  }

  let parsed: Array<{
    Id: string;
    Architecture: string;
    Os: string;
  }>;

  try {
    parsed = JSON.parse(verifyInspect.stdout);
  } catch (err) {
    throw new Error(
      `Failed to parse Docker inspect output for '${image}': ${err instanceof Error ? err.message : String(err)}`
    );
  }

  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new Error(`Empty image inspect metadata for '${image}'`);
  }

  const imgInfo = parsed[0];
  const architecture = (imgInfo.Architecture || '').toLowerCase();
  const os = (imgInfo.Os || '').toLowerCase();

  if (architecture !== 'amd64' || os !== 'linux') {
    throw new Error(
      `Incompatible image platform: expected linux/amd64, but resolved image has ${os}/${architecture}`
    );
  }

  return {
    imageId: imgInfo.Id,
    architecture,
    os,
  };
}

/**
 * Validates the applied container security configuration via docker inspect.
 */
export function validateContainerSecurityInspection(
  inspectOutput: string
): { readonlyRootfs: boolean; networkMode: string } {
  let parsed: Array<{
    Id: string;
    HostConfig?: {
      NetworkMode?: string;
      CapDrop?: string[];
      SecurityOpt?: string[];
      ReadonlyRootfs?: boolean;
      Privileged?: boolean;
      Init?: boolean;
      RestartPolicy?: { Name?: string };
    };
    Config?: {
      User?: string;
    };
    Mounts?: Array<{
      Destination?: string;
      RW?: boolean;
      Type?: string;
    }>;
  }>;

  try {
    parsed = JSON.parse(inspectOutput);
  } catch (err) {
    throw new Error(
      `Failed to parse container inspect output: ${err instanceof Error ? err.message : String(err)}`
    );
  }

  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new Error('Empty container inspect metadata');
  }

  const info = parsed[0];
  const hostConfig = info.HostConfig || {};
  const config = info.Config || {};

  if (hostConfig.NetworkMode !== 'none') {
    throw new Error(
      `Security violation: expected NetworkMode 'none', got '${hostConfig.NetworkMode}'`
    );
  }

  const capDrop = hostConfig.CapDrop || [];
  if (!capDrop.includes('ALL')) {
    throw new Error('Security violation: CapDrop does not contain ALL');
  }

  if (config.User !== '10001:10001') {
    throw new Error(
      `Security violation: expected User '10001:10001', got '${config.User}'`
    );
  }

  if (hostConfig.ReadonlyRootfs !== true) {
    throw new Error('Security violation: ReadonlyRootfs is not enabled');
  }

  if (hostConfig.Privileged === true) {
    throw new Error('Security violation: Privileged mode must be false');
  }

  if (hostConfig.Init !== true) {
    throw new Error('Security violation: Init daemon flag must be true');
  }

  const secOpts = hostConfig.SecurityOpt || [];
  const hasNoNewPrivs = secOpts.some((opt) => opt.includes('no-new-privileges'));
  if (!hasNoNewPrivs) {
    throw new Error(
      'Security violation: no-new-privileges security option not verified'
    );
  }

  if (hostConfig.RestartPolicy?.Name && hostConfig.RestartPolicy.Name !== 'no') {
    throw new Error(
      `Security violation: unexpected restart policy '${hostConfig.RestartPolicy.Name}'`
    );
  }

  const mounts = info.Mounts || [];
  const inputMount = mounts.find((m) => m.Destination === '/input');
  if (!inputMount) {
    throw new Error("Security violation: /input mount missing from container");
  }
  if (inputMount.RW !== false) {
    throw new Error("Security violation: /input mount is not read-only");
  }

  return {
    readonlyRootfs: hostConfig.ReadonlyRootfs,
    networkMode: hostConfig.NetworkMode,
  };
}

/**
 * Reconciles and purges orphaned or stale containers managed by TrustBounty.
 */
export async function reconcileStaleContainers(
  options: ReconcileOptions = {}
): Promise<string[]> {
  const filterArgs = ['ps', '-a', '--no-trunc', '--filter', 'label=trustbounty.managed=true'];
  if (options.verifierId) {
    filterArgs.push('--filter', `label=trustbounty.verifierId=${options.verifierId}`);
  }
  filterArgs.push('--format', '{{.ID}}\t{{.CreatedAt}}\t{{.Names}}');

  const psRes = await runDockerCli(filterArgs);
  if (psRes.exitCode !== 0) {
    return [];
  }

  const maxAgeMs = options.maxAgeMs ?? 360_000; // default 6 minutes
  const now = Date.now();
  const purged: string[] = [];

  const lines = psRes.stdout.trim().split(/\r?\n/).filter((l) => l.trim().length > 0);
  for (const line of lines) {
    const [id, createdAtStr] = line.split('\t');
    if (!id) continue;

    let isStale = false;
    if (maxAgeMs === 0) {
      isStale = true;
    } else if (createdAtStr) {
      const cleaned = createdAtStr.trim().replace(/\s+[A-Za-z0-9_()]+$/, '');
      let createdTime = new Date(cleaned).getTime();
      if (isNaN(createdTime)) {
        createdTime = new Date(createdAtStr).getTime();
      }
      if (!isNaN(createdTime) && now - createdTime >= maxAgeMs) {
        isStale = true;
      }
    } else {
      isStale = true;
    }

    if (isStale) {
      await runDockerCli(['rm', '-f', id]);
      purged.push(id);
    }
  }

  return purged;
}

/**
 * Executes an acceptance criterion command inside an isolated Docker sandbox.
 *
 * This is the ONLY public execution API for Phase 2B-1.
 * All Docker lifecycle operations (create, inspect, start, wait, teardown) are managed internally.
 */
export async function executeInSandbox(
  config: SandboxConfig
): Promise<ExecutionResult> {
  const startHr = process.hrtime.bigint();
  const releaseSlot = await defaultConcurrencyLimiter.acquire();

  let containerId: string | undefined;
  let resolvedWorkspace = '';
  let normalizedCommit = '';
  let resources: ResolvedResources;

  const errorResult = (
    category: ErrorCategory,
    err: unknown,
    cId?: string
  ): ExecutionResult => {
    const durationMs = Number((process.hrtime.bigint() - startHr) / 1_000_000n);
    return {
      status: 'INFRASTRUCTURE_ERROR',
      exitCode: null,
      durationMs,
      image: config.image || '',
      platform: 'linux/amd64',
      workspaceCommit: normalizedCommit || config.workspaceCommit || '',
      stdout: '',
      stderr: '',
      stdoutTruncated: false,
      stderrTruncated: false,
      errorCategory: category,
      containerId: cId,
      errorMessage: err instanceof Error ? err.message : String(err),
    };
  };

  try {
    // 1. Validate inputs before invoking Docker
    try {
      resolvedWorkspace = validateWorkspacePath(config.workspacePath);
    } catch (err) {
      return errorResult('WORKSPACE_ERROR', err);
    }

    try {
      normalizedCommit = validateCommit(config.workspaceCommit);
    } catch (err) {
      return errorResult('CONFIG_ERROR', err);
    }

    try {
      validateImageReference(config.image);
    } catch (err) {
      return errorResult('IMAGE_ERROR', err);
    }

    if (typeof config.command !== 'string' || !config.command.trim()) {
      return errorResult('CONFIG_ERROR', new Error('Command must be a non-empty string'));
    }

    try {
      resources = validateAndResolveResources(config.resources);
    } catch (err) {
      return errorResult('CONFIG_ERROR', err);
    }

    // 2. Preflight image availability and platform compatibility
    try {
      await ensureAndInspectImage(config.image, config.imagePullPolicy);
    } catch (imageErr) {
      return errorResult('IMAGE_ERROR', imageErr);
    }

    // 3. Construct deterministic container identifiers
    const bountyId = (config.bountyId || 'default').replace(/[^a-zA-Z0-9_-]/g, '_');
    const runId = (
      config.runId || crypto.randomBytes(8).toString('hex')
    ).replace(/[^a-zA-Z0-9_-]/g, '_');
    const verifierId = (config.verifierId || 'primary').replace(/[^a-zA-Z0-9_-]/g, '_');
    const containerName = `tb-verify-${bountyId}-${runId}`;

    // 4. Construct container creation argument vector
    // In-container bootstrap copy: controlled non-dereferencing recursive copy
    const bootstrapCommand =
      'if ! cp -P -R /input/. /workspace; then echo "TRUSTBOUNTY_BOOTSTRAP_ERROR: Failed to populate workspace from /input" >&2; exit 125; fi; cd /workspace && exec /bin/sh -c "$1"';

    const createArgs = [
      'create',
      '--name',
      containerName,
      '--label',
      'trustbounty.managed=true',
      '--label',
      `trustbounty.bountyId=${bountyId}`,
      '--label',
      `trustbounty.runId=${runId}`,
      '--label',
      `trustbounty.verifierId=${verifierId}`,
      '--label',
      `trustbounty.createdAt=${new Date().toISOString()}`,
      '--platform',
      'linux/amd64',
      '--network',
      'none',
      '--read-only',
      '--user',
      '10001:10001',
      '--cap-drop',
      'ALL',
      '--security-opt',
      'no-new-privileges=true',
      '--init',
      '--no-healthcheck',
      '--memory',
      String(resources.memoryBytes),
      '--memory-swap',
      String(resources.memorySwapBytes),
      '--cpus',
      String(resources.cpus),
      '--pids-limit',
      String(resources.pidsLimit),
      '--shm-size',
      String(resources.shmSizeBytes),
      '--log-driver',
      'local',
      '--log-opt',
      'max-size=10m',
      '--log-opt',
      'max-file=1',
      '--log-opt',
      'compress=false',
      '--mount',
      `type=bind,source=${resolvedWorkspace},target=/input,readonly`,
      '--tmpfs',
      `/workspace:rw,exec,nosuid,size=${resources.workspaceTmpfsBytes},uid=10001,gid=10001,mode=0700`,
      '--tmpfs',
      `/tmp:rw,noexec,nosuid,size=${resources.tmpTmpfsBytes},uid=10001,gid=10001,mode=1777`,
      '--workdir',
      '/workspace',
      '--entrypoint',
      '/bin/sh',
      '-e',
      'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      '-e',
      'HOME=/workspace',
      '-e',
      'LANG=C.UTF-8',
      '-e',
      'LC_ALL=C.UTF-8',
      '-e',
      'CI=true',
      '-e',
      'TRUSTBOUNTY_VERIFIER=1',
      config.image,
      '-c',
      bootstrapCommand,
      '--',
      config.command,
    ];

    // 5. Execute docker create and acquire container ID
    const createRes = await runDockerCli(createArgs);
    if (createRes.exitCode !== 0) {
      return errorResult(
        'DOCKER_DAEMON_ERROR',
        new Error(`docker create failed: ${createRes.stderr.trim() || createRes.stdout.trim()}`)
      );
    }

    containerId = createRes.stdout.trim().split(/\r?\n/)[0].trim();
    if (!containerId || containerId.length < 12) {
      return errorResult(
        'DOCKER_DAEMON_ERROR',
        new Error(`docker create returned invalid container ID: '${createRes.stdout.trim()}'`)
      );
    }

    // 6. Preflight inspect to validate security configuration
    try {
      const inspectRes = await runDockerCli(['inspect', containerId]);
      if (inspectRes.exitCode !== 0) {
        throw new Error(`Failed to inspect created container: ${inspectRes.stderr}`);
      }
      validateContainerSecurityInspection(inspectRes.stdout);
    } catch (inspectErr) {
      return errorResult('CONFIG_ERROR', inspectErr, containerId);
    }

    // 7. Execute container via docker start -a with stream monitoring
    const execResult = await executeAndMonitorContainer({
      containerId,
      resources,
      image: config.image,
      workspaceCommit: normalizedCommit,
      startHr,
    });

    return execResult;
  } finally {
    // 8. Deterministic cleanup: ensure container is removed and slot released
    if (containerId) {
      try {
        await runDockerCli(['rm', '-f', containerId]);
      } catch {
        // Best effort cleanup
      }
    }
    releaseSlot();
  }
}

/**
 * Starts container, continuously drains streams, monitors watchdog, and classifies result.
 */
async function executeAndMonitorContainer(options: {
  containerId: string;
  resources: ResolvedResources;
  image: string;
  workspaceCommit: string;
  startHr: bigint;
}): Promise<ExecutionResult> {
  const { containerId, resources, image, workspaceCommit, startHr } = options;

  let terminationLatch: 'TIMEOUT' | 'OUTPUT_ABUSE' | null = null;
  let stdoutTotalBytes = 0;
  let stderrTotalBytes = 0;
  let stdoutTruncated = false;
  let stderrTruncated = false;
  const stdoutChunks: Buffer[] = [];
  const stderrChunks: Buffer[] = [];

  let watchdogTimer: NodeJS.Timeout | undefined;
  let forceKillTimer: NodeJS.Timeout | undefined;

  const child = spawn('docker', ['start', '-a', containerId], {
    shell: false,
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  const checkOutputAbuse = () => {
    if (stdoutTotalBytes + stderrTotalBytes > resources.activeOutputAbuseBytes) {
      if (!terminationLatch) {
        terminationLatch = 'OUTPUT_ABUSE';
        try {
          runDockerCli(['kill', containerId]);
        } catch {
          // Best effort
        }
        killChildProcess(child);
      }
    }
  };

  // Continuous stream draining without pipe backpressure
  child.stdout?.on('data', (chunk: Buffer) => {
    const prevTotal = stdoutTotalBytes;
    stdoutTotalBytes += chunk.length;
    if (prevTotal < resources.maxStdoutBytes) {
      const allowed = Math.min(chunk.length, resources.maxStdoutBytes - prevTotal);
      if (allowed > 0) {
        stdoutChunks.push(chunk.subarray(0, allowed));
      }
    }
    if (stdoutTotalBytes > resources.maxStdoutBytes) {
      stdoutTruncated = true;
    }
    checkOutputAbuse();
  });

  child.stderr?.on('data', (chunk: Buffer) => {
    const prevTotal = stderrTotalBytes;
    stderrTotalBytes += chunk.length;
    if (prevTotal < resources.maxStderrBytes) {
      const allowed = Math.min(chunk.length, resources.maxStderrBytes - prevTotal);
      if (allowed > 0) {
        stderrChunks.push(chunk.subarray(0, allowed));
      }
    }
    if (stderrTotalBytes > resources.maxStderrBytes) {
      stderrTruncated = true;
    }
    checkOutputAbuse();
  });

  // Watchdog timer for timeout lifecycle
  watchdogTimer = setTimeout(() => {
    if (!terminationLatch) {
      terminationLatch = 'TIMEOUT';
      // Step 1: docker stop -t 10
      runDockerCli(['stop', '-t', '10', containerId]);

      // Step 2: if still running after grace period, docker kill
      forceKillTimer = setTimeout(() => {
        runDockerCli(['kill', containerId]);
        killChildProcess(child);
      }, 12_000);
    }
  }, resources.timeoutMs);

  // Await process exit
  const exitCode: number | null = await new Promise((resolve) => {
    child.on('close', (code) => resolve(code));
    child.on('error', () => resolve(null));
  });

  clearTimeout(watchdogTimer);
  if (forceKillTimer) clearTimeout(forceKillTimer);

  const durationMs = Number((process.hrtime.bigint() - startHr) / 1_000_000n);
  const stdoutStr = Buffer.concat(stdoutChunks).toString('utf8');
  const stderrStr = Buffer.concat(stderrChunks).toString('utf8');

  // Post-execution inspection to verify exit state and OOM status
  let inspectState = {
    ExitCode: exitCode ?? 0,
    OOMKilled: false,
  };

  try {
    const postInspect = await runDockerCli(['inspect', containerId]);
    if (postInspect.exitCode === 0) {
      const parsed = JSON.parse(postInspect.stdout);
      if (Array.isArray(parsed) && parsed[0]?.State) {
        inspectState = {
          ExitCode:
            typeof parsed[0].State.ExitCode === 'number'
              ? parsed[0].State.ExitCode
              : exitCode ?? 0,
          OOMKilled: Boolean(parsed[0].State.OOMKilled),
        };
      }
    }
  } catch {
    // If post-inspection fails, rely on child process exit code
  }

  // Exact classification precedence:
  // 1. Explicit timeout latch
  // 2. Explicit output-abuse termination latch
  // 3. Post-exit OOMKilled verification
  // 4. In-container workspace bootstrap staging failure
  // 5. Normal process exit code classification
  // 6. Infrastructure failure fallback

  if (terminationLatch === 'TIMEOUT') {
    return {
      status: 'TIMEOUT',
      exitCode: null,
      durationMs,
      image,
      platform: 'linux/amd64',
      workspaceCommit,
      stdout: stdoutStr,
      stderr: stderrStr,
      stdoutTruncated,
      stderrTruncated,
      errorCategory: 'TIMEOUT',
      containerId,
      errorMessage: `Execution exceeded wall-clock timeout of ${resources.timeoutMs}ms`,
    };
  }

  if (terminationLatch === 'OUTPUT_ABUSE') {
    return {
      status: 'INFRASTRUCTURE_ERROR',
      exitCode: null,
      durationMs,
      image,
      platform: 'linux/amd64',
      workspaceCommit,
      stdout: stdoutStr,
      stderr: stderrStr,
      stdoutTruncated,
      stderrTruncated,
      errorCategory: 'OUTPUT_ABUSE',
      containerId,
      errorMessage: `Execution terminated: output exceeded abuse threshold of ${resources.activeOutputAbuseBytes} bytes`,
    };
  }

  if (inspectState.OOMKilled) {
    return {
      status: 'OOM',
      exitCode: inspectState.ExitCode,
      durationMs,
      image,
      platform: 'linux/amd64',
      workspaceCommit,
      stdout: stdoutStr,
      stderr: stderrStr,
      stdoutTruncated,
      stderrTruncated,
      errorCategory: 'OOM',
      containerId,
      errorMessage: 'Process was terminated by Linux Out-Of-Memory (OOM) killer',
    };
  }

  if (
    stderrStr.includes('TRUSTBOUNTY_BOOTSTRAP_ERROR') &&
    inspectState.ExitCode === 125
  ) {
    return {
      status: 'INFRASTRUCTURE_ERROR',
      exitCode: 125,
      durationMs,
      image,
      platform: 'linux/amd64',
      workspaceCommit,
      stdout: stdoutStr,
      stderr: stderrStr,
      stdoutTruncated,
      stderrTruncated,
      errorCategory: 'WORKSPACE_ERROR',
      containerId,
      errorMessage: 'Failed to populate /workspace from /input inside container',
    };
  }

  if (inspectState.ExitCode === 0) {
    return {
      status: 'SUCCESS',
      exitCode: 0,
      durationMs,
      image,
      platform: 'linux/amd64',
      workspaceCommit,
      stdout: stdoutStr,
      stderr: stderrStr,
      stdoutTruncated,
      stderrTruncated,
      errorCategory: 'NONE',
      containerId,
    };
  }

  if (inspectState.ExitCode !== 0 && inspectState.ExitCode !== null) {
    return {
      status: 'EXECUTION_FAILED',
      exitCode: inspectState.ExitCode,
      durationMs,
      image,
      platform: 'linux/amd64',
      workspaceCommit,
      stdout: stdoutStr,
      stderr: stderrStr,
      stdoutTruncated,
      stderrTruncated,
      errorCategory: 'NONE',
      containerId,
      errorMessage: `Command exited with non-zero status ${inspectState.ExitCode}`,
    };
  }

  return {
    status: 'INFRASTRUCTURE_ERROR',
    exitCode: null,
    durationMs,
    image,
    platform: 'linux/amd64',
    workspaceCommit,
    stdout: stdoutStr,
    stderr: stderrStr,
    stdoutTruncated,
    stderrTruncated,
    errorCategory: 'DOCKER_DAEMON_ERROR',
    containerId,
    errorMessage: 'Container exited with indeterminate status',
  };
}
