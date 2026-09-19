/**
 * TrustBounty Phase 2B-1: Docker Sandbox Runner Types
 *
 * Defines configuration, resource boundaries, and execution result schemas
 * for isolated containerized verification.
 */

/**
 * High-level execution status classification.
 */
export type ExecutionStatus =
  | 'SUCCESS'
  | 'EXECUTION_FAILED'
  | 'TIMEOUT'
  | 'OOM'
  | 'INFRASTRUCTURE_ERROR';

/**
 * Detailed error category classification.
 */
export type ErrorCategory =
  | 'NONE'
  | 'TIMEOUT'
  | 'OOM'
  | 'OUTPUT_ABUSE'
  | 'IMAGE_ERROR'
  | 'CONFIG_ERROR'
  | 'WORKSPACE_ERROR'
  | 'DOCKER_DAEMON_ERROR';

/**
 * Configurable resource limits and bounds for container execution.
 */
export interface SandboxResources {
  /** CPU quota in cores (default: 2.0, min: 0.5, max: 8.0) */
  cpus?: number;
  /** Memory ceiling in bytes (default: 4GB = 4,294,967,296, min: 512MB, max: 16GB) */
  memoryBytes?: number;
  /** Memory + swap ceiling in bytes (default: 4GB, min: memoryBytes, max: 16GB) */
  memorySwapBytes?: number;
  /** Maximum number of processes/threads (default: 256, min: 64, max: 1024) */
  pidsLimit?: number;
  /** Size of tmpfs mounted at /workspace in bytes (default: 2GB = 2,147,483,648, min: 512MB, max: 8GB) */
  workspaceTmpfsBytes?: number;
  /** Size of tmpfs mounted at /tmp in bytes (default: 512MB = 536,870,912, min: 64MB, max: 2GB) */
  tmpTmpfsBytes?: number;
  /** Size of /dev/shm in bytes (default: 256MB = 268,435,456, min: 64MB, max: 1GB) */
  shmSizeBytes?: number;
  /** Maximum stdout bytes retained in memory (default: 5MB = 5,242,880, min: 1MB, max: 20MB) */
  maxStdoutBytes?: number;
  /** Maximum stderr bytes retained in memory (default: 5MB = 5,242,880, min: 1MB, max: 20MB) */
  maxStderrBytes?: number;
  /** Combined active output-abuse threshold in bytes to trigger SIGKILL (default: 20MB, min: 10MB, max: 50MB) */
  activeOutputAbuseBytes?: number;
  /** Execution timeout in milliseconds (default: 180,000ms = 3 min, min: 5,000ms, max: 600,000ms) */
  timeoutMs?: number;
}

/**
 * Image pull policy for Docker sandbox.
 */
export type ImagePullPolicy = 'never' | 'if-missing' | 'always';

/**
 * Configuration options for executing a command inside the Docker sandbox.
 * Callers provide strictly typed values; arbitrary Docker CLI flags are forbidden.
 */
export interface SandboxConfig {
  /** Absolute path to the Phase 2A PreparedWorkspace directory */
  workspacePath: string;
  /** Verified 40-character hexadecimal commit SHA-1 of the workspace */
  workspaceCommit: string;
  /** Pinned container image reference (<image>@sha256:<64-hex>) */
  image: string;
  /** Criterion shell command to execute in /workspace */
  command: string;
  /** Optional bounty identifier for container naming and telemetry */
  bountyId?: string;
  /** Optional run identifier for container naming and telemetry */
  runId?: string;
  /** Optional verifier deployment instance identifier */
  verifierId?: string;
  /** Optional resource constraints */
  resources?: SandboxResources;
  /** Image pull policy (defaults to 'if-missing') */
  imagePullPolicy?: ImagePullPolicy;
}

/**
 * Structured result of executing a command in the Docker sandbox.
 */
export interface ExecutionResult {
  /** Execution status classification */
  status: ExecutionStatus;
  /** Process exit code (null if killed, timed out, or crashed before start) */
  exitCode: number | null;
  /** Wall-clock execution duration in milliseconds measured host-side */
  durationMs: number;
  /** Container image reference */
  image: string;
  /** Execution platform (strictly 'linux/amd64') */
  platform: string;
  /** Workspace commit SHA-1 */
  workspaceCommit: string;
  /** Captured stdout (bounded) */
  stdout: string;
  /** Captured stderr (bounded) */
  stderr: string;
  /** True if stdout was truncated due to retention limits */
  stdoutTruncated: boolean;
  /** True if stderr was truncated due to retention limits */
  stderrTruncated: boolean;
  /** High-level error category */
  errorCategory: ErrorCategory;
  /** Assigned 64-hex Docker container ID */
  containerId?: string;
  /** Diagnostic error message if execution failed or experienced an infrastructure error */
  errorMessage?: string;
}

/**
 * Options for reconciling orphaned or stale containers.
 */
export interface ReconcileOptions {
  /** Optional verifier deployment instance ID to filter by */
  verifierId?: string;
  /** Maximum age in milliseconds beyond which containers are considered stale (default: 360,000ms = 6 min) */
  maxAgeMs?: number;
}
