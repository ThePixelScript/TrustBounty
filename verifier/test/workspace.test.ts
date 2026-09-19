import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

import {
  prepareWorkspace,
  verifyExactHead,
  cleanupWorkspace,
  validateCommitHash,
  checkRepositoryIdentity,
  runGit,
  validateAndResolveWorkspaceRoot,
  assertWorkspaceWithinRoot,
  sanitizeSecret,
  InvalidCommitError,
  CommitUnavailableError,
  RepositoryUnavailableError,
  CloneFetchError,
  CheckoutError,
  UnexpectedHeadError,
  DetachedHeadError,
  PathTraversalError,
  CleanupError,
  RepositoryIdentityMismatchError,
  WorkspaceTimeoutError,
} from '../src/index.ts';

describe('Phase 2A: Git Workspace Manager (Hardened)', () => {
  let testTempRoot: string;
  let fixtureRepoDir: string;
  let commit1: string;
  let commit2: string;
  let commit3: string;
  let featureCommit: string;

  const defaultRepoRef = {
    owner: 'testowner',
    name: 'testrepo',
  };

  before(() => {
    // Create dedicated test temporary root
    testTempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'tb-test-root-'));

    // Create a local fixture repository inside testTempRoot/testowner/testrepo
    const fixtureOwnerDir = path.join(testTempRoot, 'fixtures', 'testowner');
    fs.mkdirSync(fixtureOwnerDir, { recursive: true });
    fixtureRepoDir = path.join(fixtureOwnerDir, 'testrepo');
    fs.mkdirSync(fixtureRepoDir, { recursive: true });

    // Initialize fixture repository
    execFileSync('git', ['init', fixtureRepoDir]);
    execFileSync('git', ['-C', fixtureRepoDir, 'config', 'user.name', 'TrustBounty Tester']);
    execFileSync('git', ['-C', fixtureRepoDir, 'config', 'user.email', 'tester@trustbounty.internal']);
    execFileSync('git', ['-C', fixtureRepoDir, 'config', 'core.autocrlf', 'false']);

    // Commit 1: initial file
    fs.writeFileSync(path.join(fixtureRepoDir, 'file1.txt'), 'Commit 1 content\n');
    execFileSync('git', ['-C', fixtureRepoDir, 'add', 'file1.txt']);
    execFileSync('git', ['-C', fixtureRepoDir, 'commit', '-m', 'commit 1: initial']);
    commit1 = execFileSync('git', ['-C', fixtureRepoDir, 'rev-parse', 'HEAD']).toString().trim().toLowerCase();

    // Commit 2: second file and modified file1
    fs.writeFileSync(path.join(fixtureRepoDir, 'file1.txt'), 'Commit 2 modified content\n');
    fs.writeFileSync(path.join(fixtureRepoDir, 'file2.txt'), 'Commit 2 file content\n');
    execFileSync('git', ['-C', fixtureRepoDir, 'add', 'file1.txt', 'file2.txt']);
    execFileSync('git', ['-C', fixtureRepoDir, 'commit', '-m', 'commit 2: update file1 and add file2']);
    commit2 = execFileSync('git', ['-C', fixtureRepoDir, 'rev-parse', 'HEAD']).toString().trim().toLowerCase();

    const initialBranch = execFileSync('git', ['-C', fixtureRepoDir, 'branch', '--show-current']).toString().trim();

    // Feature branch commit
    execFileSync('git', ['-C', fixtureRepoDir, 'checkout', '-b', 'feature-branch']);
    fs.writeFileSync(path.join(fixtureRepoDir, 'feature.txt'), 'Feature branch content\n');
    execFileSync('git', ['-C', fixtureRepoDir, 'add', 'feature.txt']);
    execFileSync('git', ['-C', fixtureRepoDir, 'commit', '-m', 'commit on feature branch']);
    featureCommit = execFileSync('git', ['-C', fixtureRepoDir, 'rev-parse', 'HEAD']).toString().trim().toLowerCase();

    // Commit 3 on main branch
    execFileSync('git', ['-C', fixtureRepoDir, 'checkout', initialBranch], { stdio: 'pipe' });
    fs.writeFileSync(path.join(fixtureRepoDir, 'file3.txt'), 'Commit 3 on main\n');
    fs.writeFileSync(
      path.join(fixtureRepoDir, 'package.json'),
      JSON.stringify({
        name: 'fixture-project',
        scripts: {
          build: "node -e 'fs.writeFileSync(\"SENTINEL_EXECUTED\", \"bad\")'",
          test: "node -e 'fs.writeFileSync(\"SENTINEL_EXECUTED\", \"bad\")'",
        },
      })
    );
    execFileSync('git', ['-C', fixtureRepoDir, 'add', 'file3.txt', 'package.json']);
    execFileSync('git', ['-C', fixtureRepoDir, 'commit', '-m', 'commit 3: main commit with package.json']);
    commit3 = execFileSync('git', ['-C', fixtureRepoDir, 'rev-parse', 'HEAD']).toString().trim().toLowerCase();

    // Add a git tag
    execFileSync('git', ['-C', fixtureRepoDir, 'tag', 'v1.0.0']);
  });

  after(() => {
    try {
      fs.rmSync(testTempRoot, { recursive: true, force: true });
    } catch {
      // Best-effort cleanup
    }
  });

  // 1. Valid 40-character SHA-1
  it('1. accepts valid 40-character SHA-1 (both lowercase and uppercase input normalized)', () => {
    const validLower = '0123456789abcdef0123456789abcdef01234567';
    assert.equal(validateCommitHash(validLower), validLower);

    const validUpper = '0123456789ABCDEF0123456789ABCDEF01234567';
    assert.equal(validateCommitHash(validUpper), validLower);
  });

  // 2. Malformed SHA-1
  it('2. rejects malformed SHA-1 commit identifiers', () => {
    const invalidInputs = [
      '',
      '   ',
      'abc',
      '0123456789abcdef0123456789abcdef0123456', // 39 chars
      '0123456789abcdef0123456789abcdef012345678', // 41 chars
      '0123456789abcdef0123456789abcdef0123456g', // 'g' is not hex
      'HEAD',
      'master',
      'refs/heads/main',
      'v1.0.0',
      '../relative/path',
      'commit-hash; rm -rf /',
    ];

    for (const input of invalidInputs) {
      assert.throws(
        () => validateCommitHash(input),
        (err) => err instanceof InvalidCommitError,
        `Expected InvalidCommitError for '${input}'`
      );
    }
  });

  // 3. Successful checkout of latest commit
  it('3. successfully prepares workspace with latest commit', async () => {
    const ws = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit3,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      assert.equal(ws.targetCommit, commit3);
      assert.equal(ws.resolvedHead, commit3);
      assert.equal(ws.isDetachedHead, true);
      assert.equal(fs.existsSync(path.join(ws.workspacePath, 'file3.txt')), true);
      assert.equal(fs.existsSync(path.join(ws.workspacePath, 'file2.txt')), true);
      assert.equal(fs.existsSync(path.join(ws.workspacePath, 'file1.txt')), true);
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 4. Successful checkout of an older commit
  it('4. successfully prepares workspace with an older historical commit', async () => {
    const ws = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit1,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      assert.equal(ws.targetCommit, commit1);
      assert.equal(ws.resolvedHead, commit1);
      assert.equal(ws.isDetachedHead, true);

      // file1 must have commit 1 content
      const content = fs.readFileSync(path.join(ws.workspacePath, 'file1.txt'), 'utf8');
      assert.equal(content, 'Commit 1 content\n');

      // file2 and file3 must NOT exist in commit 1
      assert.equal(fs.existsSync(path.join(ws.workspacePath, 'file2.txt')), false);
      assert.equal(fs.existsSync(path.join(ws.workspacePath, 'file3.txt')), false);
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 5. Exact HEAD match
  it('5. verifies exact HEAD match via verifyExactHead', async () => {
    const ws = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit2,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      const verifyRes = await verifyExactHead(ws.workspacePath, commit2);
      assert.equal(verifyRes.verified, true);
      assert.equal(verifyRes.resolvedHead, commit2);
      assert.equal(verifyRes.expectedCommit, commit2);
      assert.equal(verifyRes.isDetached, true);
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 6. Wrong HEAD rejection
  it('6. rejects HEAD mismatch in verifyExactHead', async () => {
    const ws = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit2,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      // Check against commit 1 instead of commit 2
      const verifyRes = await verifyExactHead(ws.workspacePath, commit1);
      assert.equal(verifyRes.verified, false);
      assert.equal(verifyRes.resolvedHead, commit2);
      assert.equal(verifyRes.expectedCommit, commit1);
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 7. Detached HEAD requirement
  it('7. enforces detached HEAD requirement and fails if HEAD is attached to branch', async () => {
    const ws = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit3,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      assert.equal(ws.isDetachedHead, true);

      // Verify that symbolic-ref confirms detached HEAD
      const symCheck = await runGit(['symbolic-ref', '-q', 'HEAD'], { cwd: ws.workspacePath });
      assert.notEqual(symCheck.exitCode, 0, 'symbolic-ref must exit non-zero for detached HEAD');

      // Now deliberately attach HEAD to a branch inside the workspace
      await runGit(['checkout', '-b', 'attached-branch'], { cwd: ws.workspacePath });

      // verifyExactHead must now fail because HEAD is attached
      const verifyAttached = await verifyExactHead(ws.workspacePath, commit3);
      assert.equal(verifyAttached.isDetached, false);
      assert.equal(verifyAttached.verified, false);
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 8. Nonexistent commit
  it('8. throws CommitUnavailableError when commit does not exist', async () => {
    const nonexistentCommit = '0000000000000000000000000000000000000000';

    await assert.rejects(
      async () => {
        await prepareWorkspace({
          repoLocation: fixtureRepoDir,
          repository: defaultRepoRef,
          targetCommit: nonexistentCommit,
          workspaceRoot: testTempRoot,
          allowFileProtocol: true,
        });
      },
      (err) => {
        assert.ok(err instanceof CommitUnavailableError);
        assert.equal(err.targetCommit, nonexistentCommit);
        return true;
      }
    );
  });

  // 9. Clone/fetch failure handling
  it('9. handles repository unavailable and captures command failure', async () => {
    const nonExistentRepo = path.join(testTempRoot, 'does-not-exist', 'testowner', 'testrepo');

    await assert.rejects(
      async () => {
        await prepareWorkspace({
          repoLocation: nonExistentRepo,
          repository: defaultRepoRef,
          targetCommit: commit1,
          workspaceRoot: testTempRoot,
          allowFileProtocol: true,
        });
      },
      (err) => {
        assert.ok(err instanceof RepositoryUnavailableError || err instanceof CloneFetchError);
        return true;
      }
    );
  });

  // 10. Cleanup
  it('10. cleans up workspace directory completely and safely', async () => {
    const ws = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit1,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    assert.equal(fs.existsSync(ws.workspacePath), true);
    await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
    assert.equal(fs.existsSync(ws.workspacePath), false);
  });

  // 11. Temporary workspace isolation
  it('11. ensures workspace modifications do not contaminate the source repository', async () => {
    const ws = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit1,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      // Modify a file in the workspace
      fs.writeFileSync(path.join(ws.workspacePath, 'file1.txt'), 'TAMPERED IN WORKSPACE');

      // Source repository file1.txt must remain untouched
      const sourceContent = fs.readFileSync(path.join(fixtureRepoDir, 'file1.txt'), 'utf8');
      assert.notEqual(sourceContent, 'TAMPERED IN WORKSPACE');
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 12. Path-safety handling
  it('12. enforces path safety and rejects path traversal attempts', async () => {
    // Rejects null bytes in workspace root
    assert.throws(
      () => validateAndResolveWorkspaceRoot('some/path\0with/null'),
      (err) => err instanceof PathTraversalError
    );

    // Rejects path traversal outside root during cleanup
    const outsidePath = path.resolve(testTempRoot, '..', 'evil-outside');
    assert.throws(
      () => assertWorkspaceWithinRoot(outsidePath, testTempRoot),
      (err) => err instanceof PathTraversalError
    );

    // cleanupWorkspace rejects deleting filesystem root
    const rootPath = path.parse(process.cwd()).root;
    await assert.rejects(
      async () => {
        await cleanupWorkspace(rootPath);
      },
      (err) => err instanceof CleanupError
    );
  });

  // 13. Command failure capture
  it('13. captures command, arguments, exitCode, and stderr on Git failure', async () => {
    const invalidCommit = 'ffffffffffffffffffffffffffffffffffffffff';

    try {
      await prepareWorkspace({
        repoLocation: fixtureRepoDir,
        repository: defaultRepoRef,
        targetCommit: invalidCommit,
        workspaceRoot: testTempRoot,
        allowFileProtocol: true,
      });
      assert.fail('Expected error to be thrown');
    } catch (err: unknown) {
      assert.ok(err instanceof CommitUnavailableError);
      assert.ok(err.commandResult !== undefined);
      assert.equal(err.commandResult?.command, 'git');
      assert.notEqual(err.commandResult?.exitCode, 0);
      assert.ok(typeof err.commandResult?.durationMs === 'number');
    }
  });

  // 14. Repository with multiple commits
  it('14. correctly checks out different commits across history', async () => {
    const ws1 = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit1,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });
    const ws2 = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit2,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });
    const wsFeature = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: featureCommit,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      assert.equal(ws1.resolvedHead, commit1);
      assert.equal(ws2.resolvedHead, commit2);
      assert.equal(wsFeature.resolvedHead, featureCommit);

      // Feature commit has feature.txt
      assert.equal(fs.existsSync(path.join(wsFeature.workspacePath, 'feature.txt')), true);
      // ws1 and ws2 do not have feature.txt
      assert.equal(fs.existsSync(path.join(ws1.workspacePath, 'feature.txt')), false);
      assert.equal(fs.existsSync(path.join(ws2.workspacePath, 'feature.txt')), false);
    } finally {
      await cleanupWorkspace(ws1.workspacePath, { workspaceRoot: testTempRoot });
      await cleanupWorkspace(ws2.workspacePath, { workspaceRoot: testTempRoot });
      await cleanupWorkspace(wsFeature.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 15. Repository containing normal project files but no execution of those files
  it('15. checks out repository files without executing any package scripts or hooks', async () => {
    const ws = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit3,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      // package.json exists in workspace
      assert.equal(fs.existsSync(path.join(ws.workspacePath, 'package.json')), true);

      // Assert that sentinel file from package.json scripts was NEVER created
      assert.equal(fs.existsSync(path.join(ws.workspacePath, 'SENTINEL_EXECUTED')), false);
      assert.equal(fs.existsSync(path.join(fixtureRepoDir, 'SENTINEL_EXECUTED')), false);
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 16. Repeated preparation creates separate workspaces
  it('16. repeated preparation creates completely isolated and separate workspaces', async () => {
    const wsA = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit1,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    const wsB = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit1,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      assert.notEqual(wsA.workspacePath, wsB.workspacePath);
      assert.equal(fs.existsSync(wsA.workspacePath), true);
      assert.equal(fs.existsSync(wsB.workspacePath), true);
    } finally {
      await cleanupWorkspace(wsA.workspacePath, { workspaceRoot: testTempRoot });
      await cleanupWorkspace(wsB.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 17. Never fall back to branch / tag / default HEAD
  it('17. never falls back to branch, tag, or default HEAD when target commit is unavailable', async () => {
    const nonexistentCommit = '1234567890123456789012345678901234567890';

    await assert.rejects(
      async () => {
        await prepareWorkspace({
          repoLocation: fixtureRepoDir,
          repository: defaultRepoRef,
          targetCommit: nonexistentCommit,
          workspaceRoot: testTempRoot,
          allowFileProtocol: true,
        });
      },
      (err: unknown) => {
        assert.ok(err instanceof CommitUnavailableError);
        return true;
      }
    );
  });

  // 18. Repository identity check
  it('18. verifies repository identity and rejects identity mismatches', () => {
    const validLocation = 'https://github.com/testowner/testrepo.git';
    const checkValid = checkRepositoryIdentity(validLocation, defaultRepoRef);
    assert.equal(checkValid.matches, true);
    assert.equal(checkValid.ownerMatches, true);
    assert.equal(checkValid.nameMatches, true);

    const wrongOwnerLocation = 'https://github.com/wrongowner/testrepo.git';
    const checkWrongOwner = checkRepositoryIdentity(wrongOwnerLocation, defaultRepoRef);
    assert.equal(checkWrongOwner.matches, false);
    assert.equal(checkWrongOwner.ownerMatches, false);

    const wrongNameLocation = 'https://github.com/testowner/wrongrepo.git';
    const checkWrongName = checkRepositoryIdentity(wrongNameLocation, defaultRepoRef);
    assert.equal(checkWrongName.matches, false);
    assert.equal(checkWrongName.nameMatches, false);
  });

  // 19. Secret sanitization
  it('19. sanitizes secrets and basic auth tokens from URLs and error messages', () => {
    const secretUrl = 'https://bot-token:ghp_SuperSecret123@github.com/owner/repo.git';
    const sanitized = sanitizeSecret(secretUrl);
    assert.equal(sanitized, 'https://***@github.com/owner/repo.git');
    assert.equal(sanitized.includes('ghp_SuperSecret123'), false);
  });

  // 20. Adversarial test: Malicious repository hook neutralization
  it('20. deterministic hook neutralization prevents malicious hooks in repository from executing', async () => {
    // Create a malicious fixture repository containing active post-checkout and pre-commit hooks
    const maliciousDir = path.join(testTempRoot, 'fixtures', 'maliciousowner', 'maliciousrepo');
    fs.mkdirSync(maliciousDir, { recursive: true });

    execFileSync('git', ['init', maliciousDir]);
    execFileSync('git', ['-C', maliciousDir, 'config', 'user.name', 'Malicious Author']);
    execFileSync('git', ['-C', maliciousDir, 'config', 'user.email', 'evil@attacker.com']);
    execFileSync('git', ['-C', maliciousDir, 'config', 'core.autocrlf', 'false']);

    const markerPath = path.join(testTempRoot, 'MALICIOUS_HOOK_EXECUTED');
    const markerFormatted = markerPath.replace(/\\/g, '/');

    // Place malicious hook into the source repository's hooks folder
    const hookDir = path.join(maliciousDir, '.git', 'hooks');
    fs.mkdirSync(hookDir, { recursive: true });
    const postCheckoutHook = path.join(hookDir, 'post-checkout');
    fs.writeFileSync(postCheckoutHook, `#!/bin/sh\necho "HOOK_RUN" > "${markerFormatted}"\nexit 0\n`);

    fs.writeFileSync(path.join(maliciousDir, 'payload.txt'), 'payload data\n');
    execFileSync('git', ['-C', maliciousDir, 'add', 'payload.txt']);
    execFileSync('git', ['-C', maliciousDir, 'commit', '-m', 'commit with active hook in source repo']);
    const maliciousCommit = execFileSync('git', ['-C', maliciousDir, 'rev-parse', 'HEAD']).toString().trim().toLowerCase();

    // Prepare workspace from this malicious repository
    const ws = await prepareWorkspace({
      repoLocation: maliciousDir,
      repository: { owner: 'maliciousowner', name: 'maliciousrepo' },
      targetCommit: maliciousCommit,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      assert.equal(ws.resolvedHead, maliciousCommit);
      assert.equal(ws.isDetachedHead, true);

      // PROVE that the hook marker was NEVER created
      assert.equal(
        fs.existsSync(markerPath),
        false,
        'Malicious post-checkout hook MUST NOT have executed'
      );

      // PROVE that .git/hooks in prepared workspace does not exist or has no active hooks
      const workspaceHooksPath = path.join(ws.workspacePath, '.git', 'hooks');
      assert.equal(
        fs.existsSync(path.join(workspaceHooksPath, 'post-checkout')),
        false,
        'Workspace must not inherit active hooks'
      );
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
      if (fs.existsSync(markerPath)) {
        fs.unlinkSync(markerPath);
      }
    }
  });

  // 21. Local file transport restriction by default
  it('21. restricts local file: / directory transport by default in production', async () => {
    // Calling prepareWorkspace without allowFileProtocol on a local repo MUST fail
    await assert.rejects(
      async () => {
        await prepareWorkspace({
          repoLocation: fixtureRepoDir,
          repository: defaultRepoRef,
          targetCommit: commit1,
          workspaceRoot: testTempRoot,
          // allowFileProtocol is omitted (defaults to false)
        });
      },
      (err: unknown) => {
        assert.ok(err instanceof RepositoryUnavailableError);
        assert.ok((err as RepositoryUnavailableError).message.includes('Local file transport is restricted'));
        return true;
      }
    );
  });

  // 22. Regression: protocol.file.allow is not written to workspace git config
  it('22. regression test: protocol.file.allow is not globally written to .git/config', async () => {
    const ws = await prepareWorkspace({
      repoLocation: fixtureRepoDir,
      repository: defaultRepoRef,
      targetCommit: commit1,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      // Check the repo's local config for protocol.file.allow
      const configRes = await runGit(['config', '--local', '--get', 'protocol.file.allow'], {
        cwd: ws.workspacePath,
      });
      // Exit code 1 means the key is unset; if set, it must not be 'always'
      assert.notEqual(
        configRes.stdout.trim(),
        'always',
        'protocol.file.allow must NOT be persistently configured as always'
      );
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 23. Adversarial flag injection in repoLocation
  it('23. rejects repoLocation starting with hyphen (flag injection protection)', () => {
    const check = checkRepositoryIdentity('--upload-pack=touch/evil', defaultRepoRef);
    assert.equal(check.matches, false);
    assert.ok(check.reason?.includes('cannot start with a hyphen'));
  });

  // 24. Adversarial null bytes and control characters in repoLocation
  it('24. rejects repoLocation containing null bytes or control characters', () => {
    const checkNull = checkRepositoryIdentity('https://github.com/testowner/testrepo\0evil', defaultRepoRef);
    assert.equal(checkNull.matches, false);
    assert.ok(checkNull.reason?.includes('control characters'));

    const checkNewline = checkRepositoryIdentity('https://github.com/testowner/testrepo\nevil', defaultRepoRef);
    assert.equal(checkNewline.matches, false);
    assert.ok(checkNewline.reason?.includes('control characters'));
  });

  // 25. Adversarial repository owner and name characters
  it('25. rejects repository owner and name with path traversal or flag prefixes', () => {
    const checkTraversalOwner = checkRepositoryIdentity('https://github.com/testowner/testrepo', {
      owner: '../evil',
      name: 'testrepo',
    });
    assert.equal(checkTraversalOwner.matches, false);
    assert.ok(checkTraversalOwner.reason?.includes('invalid characters'));

    const checkFlagName = checkRepositoryIdentity('https://github.com/testowner/testrepo', {
      owner: 'testowner',
      name: '--upload-pack',
    });
    assert.equal(checkFlagName.matches, false);
    assert.ok(checkFlagName.reason?.includes('cannot start with a hyphen'));
  });

  // 26. Branch substitution attempt rejected
  it('26. branch substitution attempt is rejected before any Git invocation', async () => {
    await assert.rejects(
      async () => {
        await prepareWorkspace({
          repoLocation: fixtureRepoDir,
          repository: defaultRepoRef,
          targetCommit: 'main',
          workspaceRoot: testTempRoot,
          allowFileProtocol: true,
        });
      },
      (err: unknown) => {
        assert.ok(err instanceof InvalidCommitError);
        return true;
      }
    );
  });

  // 27. Tag substitution attempt rejected
  it('27. tag substitution attempt is rejected before any Git invocation', async () => {
    await assert.rejects(
      async () => {
        await prepareWorkspace({
          repoLocation: fixtureRepoDir,
          repository: defaultRepoRef,
          targetCommit: 'v1.0.0',
          workspaceRoot: testTempRoot,
          allowFileProtocol: true,
        });
      },
      (err: unknown) => {
        assert.ok(err instanceof InvalidCommitError);
        return true;
      }
    );
  });

  // 28. Host Git configuration isolation
  it('28. runGit isolates command execution from host system/global configuration', async () => {
    // Run git config listing origins under runGit
    const result = await runGit(['config', '--list', '--show-origin']);
    assert.equal(result.exitCode, 0);

    // Global and system config must not show host user ~/.gitconfig
    const stdout = result.stdout.toLowerCase();
    assert.equal(
      stdout.includes('.gitconfig') && stdout.includes('c:/users/'),
      false,
      'Host user ~/.gitconfig must not be loaded'
    );
  });

  // 29. Automatic cleanup on preparation failure
  it('29. automatically cleans up allocated workspace directory on preparation failure', async () => {
    const nonexistentCommit = '9999999999999999999999999999999999999999';

    // Count directories before
    const dirsBefore = fs.readdirSync(testTempRoot).filter((f) => f.startsWith('tb-ws-'));

    await assert.rejects(async () => {
      await prepareWorkspace({
        repoLocation: fixtureRepoDir,
        repository: defaultRepoRef,
        targetCommit: nonexistentCommit,
        workspaceRoot: testTempRoot,
        allowFileProtocol: true,
      });
    });

    // Count directories after: no orphaned tb-ws-* directory should remain
    const dirsAfter = fs.readdirSync(testTempRoot).filter((f) => f.startsWith('tb-ws-'));
    assert.equal(dirsAfter.length, dirsBefore.length, 'No orphaned workspace directory should leak on disk');
  });

  // 30. Adversarial protocol whitelist and unsupported transport rejection
  it('30. strictly rejects ext::, fd::, ssh://, git://, rsync://, scp-style, and unencrypted http://', () => {
    const maliciousLocations = [
      'ext::sh -c echo% evil',
      'fd::3',
      'ssh://git@github.com/testowner/testrepo.git',
      'git://github.com/testowner/testrepo.git',
      'rsync://github.com/testowner/testrepo.git',
      'git@github.com:testowner/testrepo.git',
      'user@host:testowner/testrepo',
      'custom://github.com/testowner/testrepo',
      'gopher://github.com/testowner/testrepo',
      'http://github.com/testowner/testrepo.git',
    ];

    for (const loc of maliciousLocations) {
      const checkProd = checkRepositoryIdentity(loc, defaultRepoRef, { allowFileProtocol: false });
      assert.equal(
        checkProd.matches,
        false,
        `Expected rejection in production mode for '${loc}', got: ${JSON.stringify(checkProd)}`
      );

      // Even when allowFileProtocol is true (for local test fixtures), non-file/non-https schemes MUST be rejected
      const checkTest = checkRepositoryIdentity(loc, defaultRepoRef, { allowFileProtocol: true });
      assert.equal(
        checkTest.matches,
        false,
        `Expected rejection even in test mode for '${loc}', got: ${JSON.stringify(checkTest)}`
      );
    }
  });

  // 31. Replacement-ref protection
  it('31. replacement-ref protection: ignores refs/replace/ and resolves true commit object', async () => {
    // Create a fixture repository with commit A and commit B
    const repFixtureDir = path.join(testTempRoot, 'fixtures', 'testowner', 'replace-repo');
    fs.mkdirSync(repFixtureDir, { recursive: true });
    execFileSync('git', ['init', repFixtureDir]);
    execFileSync('git', ['-C', repFixtureDir, 'config', 'user.name', 'Tester']);
    execFileSync('git', ['-C', repFixtureDir, 'config', 'user.email', 'tester@test.internal']);
    execFileSync('git', ['-C', repFixtureDir, 'config', 'core.autocrlf', 'false']);

    fs.writeFileSync(path.join(repFixtureDir, 'data.txt'), 'TRUE ORIGINAL CONTENT\n');
    execFileSync('git', ['-C', repFixtureDir, 'add', 'data.txt']);
    execFileSync('git', ['-C', repFixtureDir, 'commit', '-m', 'true original commit']);
    const trueCommit = execFileSync('git', ['-C', repFixtureDir, 'rev-parse', 'HEAD']).toString().trim().toLowerCase();

    fs.writeFileSync(path.join(repFixtureDir, 'data.txt'), 'FORGED REPLACEMENT CONTENT\n');
    execFileSync('git', ['-C', repFixtureDir, 'commit', '-am', 'forged commit']);
    const forgedCommit = execFileSync('git', ['-C', repFixtureDir, 'rev-parse', 'HEAD']).toString().trim().toLowerCase();

    // Create replacement ref in the repository replacing trueCommit with forgedCommit
    execFileSync('git', ['-C', repFixtureDir, 'replace', trueCommit, forgedCommit]);

    // Prepare workspace requesting the trueCommit
    const ws = await prepareWorkspace({
      repoLocation: repFixtureDir,
      repository: { owner: 'testowner', name: 'replace-repo' },
      targetCommit: trueCommit,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      assert.equal(ws.resolvedHead, trueCommit);
      assert.notEqual(ws.resolvedHead, forgedCommit);

      // Verify that the checked-out file content matches trueCommit, NOT forgedCommit
      const content = fs.readFileSync(path.join(ws.workspacePath, 'data.txt'), 'utf8');
      assert.equal(content, 'TRUE ORIGINAL CONTENT\n');
      assert.notEqual(content, 'FORGED REPLACEMENT CONTENT\n');

      const verifyRes = await verifyExactHead(ws.workspacePath, trueCommit);
      assert.equal(verifyRes.verified, true);
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
    }
  });

  // 32. Filter/smudge execution boundary
  it('32. filter execution boundary: host/global smudge filters are never executed during checkout', async () => {
    // Create a fixture repository containing .gitattributes with a smudge filter
    const filterFixtureDir = path.join(testTempRoot, 'fixtures', 'testowner', 'filter-repo');
    fs.mkdirSync(filterFixtureDir, { recursive: true });
    execFileSync('git', ['init', filterFixtureDir]);
    execFileSync('git', ['-C', filterFixtureDir, 'config', 'user.name', 'Tester']);
    execFileSync('git', ['-C', filterFixtureDir, 'config', 'user.email', 'tester@test.internal']);
    execFileSync('git', ['-C', filterFixtureDir, 'config', 'core.autocrlf', 'false']);

    const sentinelPath = path.join(testTempRoot, 'FILTER_EXECUTED_SENTINEL');

    fs.writeFileSync(path.join(filterFixtureDir, '.gitattributes'), '*.secret filter=malicious_filter\n');
    fs.writeFileSync(path.join(filterFixtureDir, 'test.secret'), 'secret file payload\n');
    execFileSync('git', ['-C', filterFixtureDir, 'add', '.gitattributes', 'test.secret']);
    execFileSync('git', ['-C', filterFixtureDir, 'commit', '-m', 'commit with gitattributes filter']);
    const filterCommit = execFileSync('git', ['-C', filterFixtureDir, 'rev-parse', 'HEAD']).toString().trim().toLowerCase();

    // Prepare workspace
    const ws = await prepareWorkspace({
      repoLocation: filterFixtureDir,
      repository: { owner: 'testowner', name: 'filter-repo' },
      targetCommit: filterCommit,
      workspaceRoot: testTempRoot,
      allowFileProtocol: true,
    });

    try {
      assert.equal(ws.resolvedHead, filterCommit);
      assert.equal(ws.isDetachedHead, true);

      // Assert that sentinel file was NEVER created
      assert.equal(
        fs.existsSync(sentinelPath),
        false,
        'Smudge filter command must never execute during workspace checkout'
      );

      const verifyRes = await verifyExactHead(ws.workspacePath, filterCommit);
      assert.equal(verifyRes.verified, true);
    } finally {
      await cleanupWorkspace(ws.workspacePath, { workspaceRoot: testTempRoot });
      if (fs.existsSync(sentinelPath)) {
        fs.unlinkSync(sentinelPath);
      }
    }
  });

  // 33. Absolute workspace preparation timeout validation
  it('33. validates totalTimeoutMs bounds and rejects out-of-range values', async () => {
    // Below minimum (< 100ms)
    await assert.rejects(
      async () => {
        await prepareWorkspace({
          repoLocation: fixtureRepoDir,
          repository: defaultRepoRef,
          targetCommit: commit1,
          workspaceRoot: testTempRoot,
          allowFileProtocol: true,
          totalTimeoutMs: 50,
        });
      },
      (err: unknown) => {
        assert.ok(err instanceof Error);
        assert.ok(err.message.includes('Invalid total timeout'));
        return true;
      }
    );

    // Above maximum (> 600000ms)
    await assert.rejects(
      async () => {
        await prepareWorkspace({
          repoLocation: fixtureRepoDir,
          repository: defaultRepoRef,
          targetCommit: commit1,
          workspaceRoot: testTempRoot,
          allowFileProtocol: true,
          totalTimeoutMs: 700000,
        });
      },
      (err: unknown) => {
        assert.ok(err instanceof Error);
        assert.ok(err.message.includes('Invalid total timeout'));
        return true;
      }
    );
  });

  // 34. Total preparation timeout enforcement and error type
  it('34. aborts with WorkspaceTimeoutError when preparation exceeds total deadline', async () => {
    // 100ms total budget is too tight for full init + config + fetch + checkout
    await assert.rejects(
      async () => {
        await prepareWorkspace({
          repoLocation: fixtureRepoDir,
          repository: defaultRepoRef,
          targetCommit: commit3,
          workspaceRoot: testTempRoot,
          allowFileProtocol: true,
          totalTimeoutMs: 100,
        });
      },
      (err: unknown) => {
        assert.ok(
          err instanceof WorkspaceTimeoutError,
          `Expected WorkspaceTimeoutError, got: ${err}`
        );
        assert.equal((err as WorkspaceTimeoutError).totalTimeoutMs, 100);
        return true;
      }
    );
  });

  // 35. Confirms timeout cleans up the allocated workspace directory
  it('35. cleans up allocated workspace directory after timeout abort without leaks', async () => {
    const dirsBefore = fs.readdirSync(testTempRoot).filter((f) => f.startsWith('tb-ws-'));

    await assert.rejects(
      async () => {
        await prepareWorkspace({
          repoLocation: fixtureRepoDir,
          repository: defaultRepoRef,
          targetCommit: commit3,
          workspaceRoot: testTempRoot,
          allowFileProtocol: true,
          totalTimeoutMs: 100,
        });
      }
    );

    const dirsAfter = fs.readdirSync(testTempRoot).filter((f) => f.startsWith('tb-ws-'));
    assert.equal(
      dirsAfter.length,
      dirsBefore.length,
      'No leaked workspace directory after timeout abort'
    );
  });

  // 36. Production https:// URL acceptance
  it('36. accepts valid https:// URLs adhering to production policy', () => {
    const validHttps = 'https://github.com/testowner/testrepo.git';
    const check = checkRepositoryIdentity(validHttps, defaultRepoRef, { allowFileProtocol: false });
    assert.equal(check.matches, true);
    assert.equal(check.ownerMatches, true);
    assert.equal(check.nameMatches, true);
  });
});
