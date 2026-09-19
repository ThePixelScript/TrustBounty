import { execFile, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type { GitCommandResult } from './types.ts';
import { sanitizeSecret } from './errors.ts';

let cachedEmptyConfigFile: string | null = null;
let cachedEmptyHooksDir: string | null = null;

/**
 * Returns the path to a dedicated empty gitconfig file to isolate git from host global/system config.
 */
export function getOrCreateEmptyGitConfigFile(): string {
  if (!cachedEmptyConfigFile || !fs.existsSync(cachedEmptyConfigFile)) {
    const dir = path.join(os.tmpdir(), 'tb-git-isolation');
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    cachedEmptyConfigFile = path.join(dir, 'empty.gitconfig');
    fs.writeFileSync(cachedEmptyConfigFile, '', { mode: 0o600 });
  }
  return cachedEmptyConfigFile;
}

/**
 * Returns the path to a dedicated empty directory to deterministically neutralize core.hooksPath.
 */
export function getOrCreateEmptyHooksDir(): string {
  if (!cachedEmptyHooksDir || !fs.existsSync(cachedEmptyHooksDir)) {
    const dir = path.join(os.tmpdir(), 'tb-git-isolation', 'empty-hooks');
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    cachedEmptyHooksDir = dir;
  }
  return cachedEmptyHooksDir;
}

export interface RunGitOptions {
  cwd?: string;
  timeoutMs?: number;
  extraEnv?: Record<string, string>;
  hooksPath?: string;
  allowFileProtocol?: boolean;
  signal?: AbortSignal;
}

/**
 * Executes a Git command using the native git CLI with argument arrays.
 * Never invokes a shell string, preventing shell injection vulnerabilities.
 * Deterministically disables Git hooks via -c core.hooksPath=<emptyDirectory> on every invocation.
 * Enforces replacement-ref neutralization via -c core.useReplaceRefs=false and GIT_NO_REPLACE_OBJECTS=1.
 * Enforces strict protocol whitelist via GIT_ALLOW_PROTOCOL (https only in production).
 * Isolates Git configuration from host system/global gitconfigs.
 */
export async function runGit(
  args: string[],
  options: RunGitOptions = {}
): Promise<GitCommandResult> {
  const startTime = Date.now();
  const emptyConfigFile = getOrCreateEmptyGitConfigFile();
  const hooksDir = options.hooksPath || getOrCreateEmptyHooksDir();

  // Prefix with hook neutralization and replacement-ref disabling
  const commandArgs = [
    '-c', `core.hooksPath=${hooksDir}`,
    '-c', 'core.useReplaceRefs=false',
    ...args,
  ];

  return new Promise((resolve) => {
    let childProcess: ReturnType<typeof execFile>;

    const abortHandler = () => {
      if (childProcess && childProcess.pid) {
        if (process.platform === 'win32') {
          try {
            execFileSync('taskkill', ['/pid', String(childProcess.pid), '/T', '/F'], {
              stdio: 'ignore',
            });
          } catch {
            // Best effort
          }
        } else {
          try {
            childProcess.kill('SIGKILL');
          } catch {
            // Best effort
          }
        }
      }
    };

    if (options.signal) {
      if (options.signal.aborted) {
        abortHandler();
      } else {
        options.signal.addEventListener('abort', abortHandler, { once: true });
      }
    }

    childProcess = execFile(
      'git',
      commandArgs,
      {
        cwd: options.cwd,
        timeout: options.timeoutMs ?? 60000,
        signal: options.signal,
        maxBuffer: 10 * 1024 * 1024,
        windowsHide: true,
        shell: false,
        env: {
          ...process.env,
          // Strict protocol allowlist: HTTPS only in production, file allowed only when explicitly enabled
          GIT_ALLOW_PROTOCOL: options.allowFileProtocol ? 'file:https' : 'https',
          // Neutralize git replacement objects
          GIT_NO_REPLACE_OBJECTS: '1',
          // Isolate from host gitconfig and disable interactive prompts / external helpers
          GIT_CONFIG_NOSYSTEM: '1',
          GIT_CONFIG_GLOBAL: emptyConfigFile,
          GIT_CONFIG_SYSTEM: emptyConfigFile,
          GIT_TERMINAL_PROMPT: '0',
          GIT_ASKPASS: '',
          GIT_ATTR_NOSYSTEM: '1',
          ...options.extraEnv,
        },
      },
      (error, stdout, stderr) => {
        if (options.signal) {
          options.signal.removeEventListener('abort', abortHandler);
        }

        const durationMs = Date.now() - startTime;
        const stdoutStr = (stdout || '').toString();
        const stderrStr = (stderr || '').toString();

        let exitCode = 0;
        if (error) {
          const status = (error as unknown as { status?: number }).status;
          if (typeof status === 'number') {
            exitCode = status;
          } else if (typeof (error as unknown as { code?: number | string }).code === 'number') {
            exitCode = (error as unknown as { code: number }).code;
          } else {
            exitCode = 1;
          }
        }

        resolve({
          command: 'git',
          args: args.map(sanitizeSecret),
          exitCode,
          stdout: stdoutStr,
          stderr: stderrStr,
          durationMs,
        });
      }
    );
  });
}
