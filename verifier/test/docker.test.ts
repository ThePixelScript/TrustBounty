import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  executeInSandbox,
  reconcileStaleContainers,
  ENVIRONMENT_IMAGE_REGEX,
  RESOURCE_BOUNDS,
  ConcurrencyLimiter,
} from '../src/index.ts';

import {
  validateAndResolveResources,
  validateWorkspacePath,
  validateImageReference,
  validateCommit,
  validateContainerSecurityInspection,
  runDockerCli,
} from '../src/docker.ts';

import type { SandboxConfig } from '../src/docker-types.ts';

const UBUNTU_DIGEST_IMAGE =
  'ubuntu@sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d';
const DUMMY_COMMIT = 'e0a4f5c2b3d1e0a4f5c2b3d1e0a4f5c2b3d1e0a4';

describe('Phase 2B-1: Unit Tests', () => {
  describe('Image Reference Validation', () => {
    it('accepts strictly valid digest-pinned image references', () => {
      assert.doesNotThrow(() =>
        validateImageReference(
          'ubuntu@sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d'
        )
      );
      assert.doesNotThrow(() =>
        validateImageReference(
          'ghcr.io/org/repo/image@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        )
      );
    });

    it('rejects mutable tags, uppercase hex, and missing digests', () => {
      assert.throws(() => validateImageReference('ubuntu:latest'));
      assert.throws(() => validateImageReference('node:20-alpine'));
      assert.throws(() =>
        validateImageReference(
          'ubuntu@sha256:513C074113A871B51A8D16AB445C88779D6452D937A164FB5CC479F32668A41D'
        )
      );
      assert.throws(() => validateImageReference('ubuntu@sha256:short'));
      assert.throws(() => validateImageReference(''));
      assert.throws(() => validateImageReference('   '));
    });
  });

  describe('Commit Validation', () => {
    it('accepts 40-hex lowercase and uppercase commit hashes and normalizes to lowercase', () => {
      const lower = 'e0a4f5c2b3d1e0a4f5c2b3d1e0a4f5c2b3d1e0a4';
      assert.equal(validateCommit(lower), lower);
      assert.equal(validateCommit(lower.toUpperCase()), lower);
    });

    it('rejects invalid commit hashes', () => {
      assert.throws(() => validateCommit('not-a-hash'));
      assert.throws(() => validateCommit('e0a4f5c2b3d1'));
      assert.throws(() => validateCommit('e0a4f5c2b3d1e0a4f5c2b3d1e0a4f5c2b3d1e0a4z'));
      assert.throws(() => validateCommit(''));
    });
  });

  describe('Workspace Path Validation', () => {
    it('accepts existing directory absolute path', () => {
      const tmpDir = os.tmpdir();
      const resolved = validateWorkspacePath(tmpDir);
      assert.equal(resolved, path.resolve(tmpDir));
    });

    it('rejects non-existent directory, files, null bytes, and empty strings', () => {
      assert.throws(() => validateWorkspacePath(''));
      assert.throws(() => validateWorkspacePath('   '));
      assert.throws(() => validateWorkspacePath('/path/with/\0/null'));
      assert.throws(() => validateWorkspacePath(path.join(os.tmpdir(), 'non-existent-dir-tb-12345')));

      // Create a temporary file and assert it rejects non-directory
      const tmpFile = path.join(os.tmpdir(), 'tb-file-test.txt');
      fs.writeFileSync(tmpFile, 'test');
      try {
        assert.throws(() => validateWorkspacePath(tmpFile));
      } finally {
        fs.unlinkSync(tmpFile);
      }
    });
  });

  describe('Resource Bounds Validation', () => {
    it('resolves defaults when resources are omitted', () => {
      const resolved = validateAndResolveResources();
      assert.equal(resolved.cpus, RESOURCE_BOUNDS.cpus.default);
      assert.equal(resolved.memoryBytes, RESOURCE_BOUNDS.memoryBytes.default);
      assert.equal(resolved.pidsLimit, RESOURCE_BOUNDS.pidsLimit.default);
      assert.equal(resolved.shmSizeBytes, RESOURCE_BOUNDS.shmSizeBytes.default);
      assert.equal(resolved.timeoutMs, RESOURCE_BOUNDS.timeoutMs.default);
      assert.equal(resolved.maxStdoutBytes, RESOURCE_BOUNDS.maxStdoutBytes.default);
      assert.equal(resolved.maxStderrBytes, RESOURCE_BOUNDS.maxStderrBytes.default);
      assert.equal(resolved.activeOutputAbuseBytes, RESOURCE_BOUNDS.activeOutputAbuseBytes.default);
    });

    it('accepts custom resource limits within valid bounds', () => {
      const custom = {
        cpus: 4.0,
        memoryBytes: 2 * 1024 * 1024 * 1024,
        pidsLimit: 512,
        timeoutMs: 30000,
        shmSizeBytes: 512 * 1024 * 1024,
      };
      const resolved = validateAndResolveResources(custom);
      assert.equal(resolved.cpus, 4.0);
      assert.equal(resolved.memoryBytes, 2 * 1024 * 1024 * 1024);
      assert.equal(resolved.pidsLimit, 512);
      assert.equal(resolved.timeoutMs, 30000);
      assert.equal(resolved.shmSizeBytes, 512 * 1024 * 1024);
    });

    it('rejects out-of-bounds resources', () => {
      assert.throws(() => validateAndResolveResources({ cpus: 0.1 }));
      assert.throws(() => validateAndResolveResources({ cpus: 16.0 }));
      assert.throws(() => validateAndResolveResources({ memoryBytes: 100 * 1024 * 1024 }));
      assert.throws(() => validateAndResolveResources({ pidsLimit: 10 }));
      assert.throws(() => validateAndResolveResources({ timeoutMs: 1000 }));
      assert.throws(() => validateAndResolveResources({ timeoutMs: 1_000_000 }));
      assert.throws(() => validateAndResolveResources({ maxStdoutBytes: 100 }));
      assert.throws(() => validateAndResolveResources({ activeOutputAbuseBytes: 1000 }));
    });
  });

  describe('Container Security Inspection Parser', () => {
    const validInspect = JSON.stringify([
      {
        Id: 'c1',
        HostConfig: {
          NetworkMode: 'none',
          CapDrop: ['ALL'],
          SecurityOpt: ['no-new-privileges=true'],
          ReadonlyRootfs: true,
          Privileged: false,
          Init: true,
          RestartPolicy: { Name: 'no' },
        },
        Config: {
          User: '10001:10001',
        },
        Mounts: [
          {
            Destination: '/input',
            RW: false,
            Type: 'bind',
          },
        ],
      },
    ]);

    it('accepts compliant security inspection', () => {
      const res = validateContainerSecurityInspection(validInspect);
      assert.equal(res.readonlyRootfs, true);
      assert.equal(res.networkMode, 'none');
    });

    it('rejects inspection if NetworkMode is not none', () => {
      const bad = JSON.parse(validInspect);
      bad[0].HostConfig.NetworkMode = 'bridge';
      assert.throws(() => validateContainerSecurityInspection(JSON.stringify(bad)));
    });

    it('rejects inspection if CapDrop does not contain ALL', () => {
      const bad = JSON.parse(validInspect);
      bad[0].HostConfig.CapDrop = [];
      assert.throws(() => validateContainerSecurityInspection(JSON.stringify(bad)));
    });

    it('rejects inspection if User is not 10001:10001', () => {
      const bad = JSON.parse(validInspect);
      bad[0].Config.User = '0:0';
      assert.throws(() => validateContainerSecurityInspection(JSON.stringify(bad)));
    });

    it('rejects inspection if ReadonlyRootfs is false', () => {
      const bad = JSON.parse(validInspect);
      bad[0].HostConfig.ReadonlyRootfs = false;
      assert.throws(() => validateContainerSecurityInspection(JSON.stringify(bad)));
    });

    it('rejects inspection if Privileged is true', () => {
      const bad = JSON.parse(validInspect);
      bad[0].HostConfig.Privileged = true;
      assert.throws(() => validateContainerSecurityInspection(JSON.stringify(bad)));
    });

    it('rejects inspection if /input mount is missing or read-write', () => {
      const bad1 = JSON.parse(validInspect);
      bad1[0].Mounts = [];
      assert.throws(() => validateContainerSecurityInspection(JSON.stringify(bad1)));

      const bad2 = JSON.parse(validInspect);
      bad2[0].Mounts[0].RW = true;
      assert.throws(() => validateContainerSecurityInspection(JSON.stringify(bad2)));
    });
  });

  describe('Concurrency Limiter', () => {
    it('allows up to maxConcurrent calls and queues subsequent calls', async () => {
      const limiter = new ConcurrencyLimiter(2);
      assert.equal(limiter.getActiveCount(), 0);

      const release1 = await limiter.acquire();
      assert.equal(limiter.getActiveCount(), 1);

      const release2 = await limiter.acquire();
      assert.equal(limiter.getActiveCount(), 2);
      assert.equal(limiter.getQueueLength(), 0);

      let acquired3 = false;
      const p3 = limiter.acquire().then((rel) => {
        acquired3 = true;
        return rel;
      });

      // Assert that third acquire is queued and not yet resolved
      assert.equal(acquired3, false);
      assert.equal(limiter.getQueueLength(), 1);

      // Release first slot -> third acquire resolves
      release1();
      const release3 = await p3;
      assert.equal(acquired3, true);
      assert.equal(limiter.getActiveCount(), 2);
      assert.equal(limiter.getQueueLength(), 0);

      release2();
      release3();
      assert.equal(limiter.getActiveCount(), 0);
    });
  });
});

describe('Phase 2B-1: Docker Integration Tests', () => {
  let testWorkspaceRoot: string;
  let testWorkspace: string;

  before(() => {
    testWorkspaceRoot = path.join(os.tmpdir(), 'tb-docker-tests');
    fs.mkdirSync(testWorkspaceRoot, { recursive: true, mode: 0o700 });
    testWorkspace = fs.mkdtempSync(path.join(testWorkspaceRoot, 'ws-'));

    // Populate mock repository files
    fs.writeFileSync(path.join(testWorkspace, 'README.md'), '# TrustBounty Test Repo\n');
    fs.writeFileSync(
      path.join(testWorkspace, 'app.sh'),
      '#!/bin/sh\necho "App executed successfully"\n',
      { mode: 0o755 }
    );
  });

  after(async () => {
    try {
      if (fs.existsSync(testWorkspaceRoot)) {
        fs.rmSync(testWorkspaceRoot, { recursive: true, force: true });
      }
    } catch {
      // Best effort cleanup
    }
    // Clean up any stray containers
    await reconcileStaleContainers({ maxAgeMs: 0 });
  });

  it('1. executes a successful criterion command and returns SUCCESS with exitCode 0', async () => {
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command: 'echo "hello from TrustBounty sandbox" && cat README.md',
    });

    assert.equal(result.status, 'SUCCESS');
    assert.equal(result.exitCode, 0);
    assert.equal(result.errorCategory, 'NONE');
    assert.equal(result.platform, 'linux/amd64');
    assert.match(result.stdout, /hello from TrustBounty sandbox/);
    assert.match(result.stdout, /# TrustBounty Test Repo/);
    assert.equal(result.stdoutTruncated, false);
    assert.equal(result.stderrTruncated, false);
    assert.ok(result.durationMs > 0);
  });

  it('2. executes a failing command and returns EXECUTION_FAILED with non-zero exitCode', async () => {
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command: 'echo "failing step" >&2 && exit 42',
    });

    assert.equal(result.status, 'EXECUTION_FAILED');
    assert.equal(result.exitCode, 42);
    assert.equal(result.errorCategory, 'NONE');
    assert.match(result.stderr, /failing step/);
  });

  it('3. enforces unprivileged non-root execution (UID 10001:10001)', async () => {
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command: 'echo "UID=$(id -u) GID=$(id -g)"',
    });

    assert.equal(result.status, 'SUCCESS');
    assert.equal(result.exitCode, 0);
    assert.match(result.stdout, /UID=10001 GID=10001/);
  });

  it('4. enforces that source /input mount is strictly read-only', async () => {
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command: 'touch /input/exploit.txt',
    });

    assert.equal(result.status, 'EXECUTION_FAILED');
    assert.notEqual(result.exitCode, 0);
    assert.match(result.stderr.toLowerCase(), /read-only file system/);

    // Verify host workspace has not been mutated
    assert.equal(fs.existsSync(path.join(testWorkspace, 'exploit.txt')), false);
  });

  it('5. enforces that /workspace tmpfs is isolated, writable, and executable', async () => {
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command:
        'echo "#!/bin/sh" > gen.sh && echo "echo generated-script-works" >> gen.sh && chmod +x gen.sh && ./gen.sh',
    });

    assert.equal(result.status, 'SUCCESS');
    assert.equal(result.exitCode, 0);
    assert.match(result.stdout, /generated-script-works/);

    // Host workspace should not contain gen.sh
    assert.equal(fs.existsSync(path.join(testWorkspace, 'gen.sh')), false);
  });

  it('6. enforces that /tmp tmpfs is mounted with noexec', async () => {
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command:
        'echo "#!/bin/sh" > /tmp/bad.sh && echo "echo bad" >> /tmp/bad.sh && chmod +x /tmp/bad.sh && /tmp/bad.sh',
    });

    assert.equal(result.status, 'EXECUTION_FAILED');
    assert.notEqual(result.exitCode, 0);
    assert.match(result.stderr.toLowerCase(), /permission denied/);
  });

  it('7. verifies bounded shared memory (/dev/shm) is available', async () => {
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command: 'dd if=/dev/zero of=/dev/shm/test.dat bs=1M count=10 && ls -lh /dev/shm',
    });

    assert.equal(result.status, 'SUCCESS');
    assert.equal(result.exitCode, 0);
    assert.match(result.stdout, /test\.dat/);
  });

  it('8. enforces that network is completely disabled (--network none)', async () => {
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command: 'perl -MIO::Socket::INET -e "IO::Socket::INET->new(PeerAddr => \'1.1.1.1:80\', Timeout => 1) or die \$!"',
    });

    assert.equal(result.status, 'EXECUTION_FAILED');
    assert.notEqual(result.exitCode, 0);
    assert.match(result.stderr.toLowerCase(), /unreachable|failed/);
  });

  it('9. drains streams continuously and flags stdoutTruncated when cap is exceeded', async () => {
    // Generate 2MB of output with a 1MB limit
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command: 'perl -e "print \'A\' x (2 * 1024 * 1024);"',
      resources: {
        maxStdoutBytes: 1024 * 1024, // 1 MB limit
      },
    });

    assert.equal(result.status, 'SUCCESS');
    assert.equal(result.exitCode, 0);
    assert.equal(result.stdoutTruncated, true);
    assert.equal(result.stdout.length, 1024 * 1024);
  });

  it('10. enforces timeout lifecycle with two-tier termination', async () => {
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command: 'sleep 30',
      resources: {
        timeoutMs: 5000, // 5 second timeout
      },
    });

    assert.equal(result.status, 'TIMEOUT');
    assert.equal(result.errorCategory, 'TIMEOUT');
    assert.equal(result.exitCode, null);
    assert.match(result.errorMessage || '', /exceeded wall-clock timeout/);
  });

  it('11. detects and classifies Linux OOMKilled condition accurately', async () => {
    // Allocate 700MB with memory limit 512MB
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command: 'perl -e \'$x = "a" x (700 * 1024 * 1024);\'',
      resources: {
        memoryBytes: 512 * 1024 * 1024, // 512 MB
        memorySwapBytes: 512 * 1024 * 1024,
      },
    });

    assert.equal(result.status, 'OOM');
    assert.equal(result.errorCategory, 'OOM');
    assert.match(result.errorMessage || '', /Out-Of-Memory/);
  });

  it('12. asserts container is completely deleted from Docker engine after execution', async () => {
    const result = await executeInSandbox({
      workspacePath: testWorkspace,
      workspaceCommit: DUMMY_COMMIT,
      image: UBUNTU_DIGEST_IMAGE,
      command: 'echo "cleanup check"',
    });

    assert.equal(result.status, 'SUCCESS');
    assert.ok(result.containerId);

    // Verify container no longer exists in docker inspect
    const inspectRes = await runDockerCli(['inspect', result.containerId!]);
    assert.notEqual(inspectRes.exitCode, 0);
  });

  it('13. reconcileStaleContainers finds and purges stale TrustBounty containers', async () => {
    const testContainerName = 'tb-verify-reconcile-test-' + Date.now();

    // Create a managed container directly
    const createRes = await runDockerCli([
      'create',
      '--name',
      testContainerName,
      '--label',
      'trustbounty.managed=true',
      '--label',
      'trustbounty.verifierId=test-verifier',
      UBUNTU_DIGEST_IMAGE,
      'sleep',
      '60',
    ]);
    assert.equal(createRes.exitCode, 0);

    const containerId = createRes.stdout.trim().split(/\r?\n/)[0].trim();
    assert.ok(containerId);

    // Reconcile with maxAgeMs: 0 to force purge
    const purged = await reconcileStaleContainers({
      verifierId: 'test-verifier',
      maxAgeMs: 0,
    });

    assert.ok(purged.includes(containerId));

    // Assert container is gone
    const inspectRes = await runDockerCli(['inspect', containerId]);
    assert.notEqual(inspectRes.exitCode, 0);
  });
});
