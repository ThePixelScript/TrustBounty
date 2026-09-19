/**
 * TrustBounty Phase 2B-2: Evidence Bundle Storage & Verification.
 *
 * Implements:
 * 1. Content-addressed bundle layout: evidence_bundles/<evidenceHash>/
 * 2. Path safety on criterion ID artifact filenames.
 * 3. Atomic staging directory lifecycle with cleanup on error.
 * 4. Collision detection and idempotent handling of identical bundles.
 * 5. Post-commitment read-back verification.
 * 6. Standalone bundle integrity verification (auditor / V2 mode).
 */

import fs from 'node:fs';
import path from 'node:path';
import type {
  CanonicalEvidenceManifest,
  CriterionEvaluationResult,
  EvidenceBundle,
  RuntimeMetadata,
} from './evidence-types.ts';
import {
  computeEvidenceHash,
  computeKeccak256Digest,
  canonicalizeManifest,
} from './evidence-builder.ts';
import {
  EvidenceCollisionError,
  EvidenceCommitmentError,
  EvidenceVerificationError,
  InvalidManifestError,
} from './errors.ts';

const VALID_CRITERION_ID_REGEX = /^[A-Za-z0-9_-]{1,64}$/;

/**
 * Validates that a criterion ID is safe for filesystem artifact filenames.
 * Strictly prevents path traversal, separators, or invalid characters.
 */
export function validateCriterionIdForPath(id: string): void {
  if (typeof id !== 'string' || !VALID_CRITERION_ID_REGEX.test(id)) {
    throw new InvalidManifestError(
      `Criterion ID "${id}" is invalid or unsafe for filesystem artifact storage`
    );
  }
}

/**
 * Asserts that targetPath resolves strictly inside baseDir, preventing directory traversal.
 */
export function assertPathWithinDirectory(baseDir: string, targetPath: string): void {
  const resolvedBase = path.resolve(baseDir);
  const resolvedTarget = path.resolve(targetPath);

  if (
    resolvedTarget !== resolvedBase &&
    !resolvedTarget.startsWith(resolvedBase + path.sep)
  ) {
    throw new EvidenceVerificationError(
      `Path traversal detected: target "${targetPath}" resolves outside base directory "${baseDir}"`
    );
  }
}

export interface StoreEvidenceBundleParams {
  /** Target root directory for evidence bundles (e.g. "./evidence_bundles") */
  bundlesRoot: string;
  manifest: CanonicalEvidenceManifest;
  runtimeMetadata: RuntimeMetadata;
  criteriaResults: CriterionEvaluationResult[];
}

/**
 * Atomically stores an evidence bundle under bundlesRoot/<evidenceHash>/.
 */
export async function storeEvidenceBundle(
  params: StoreEvidenceBundleParams
): Promise<EvidenceBundle> {
  const { bundlesRoot, manifest, runtimeMetadata, criteriaResults } = params;

  // 1. Calculate and verify evidenceHash
  const evidenceHash = computeEvidenceHash(manifest);
  if (!/^0x[0-9a-f]{64}$/.test(evidenceHash)) {
    throw new EvidenceCommitmentError(`Computed invalid evidenceHash: ${evidenceHash}`);
  }

  // Ensure bundles root exists
  fs.mkdirSync(bundlesRoot, { recursive: true });

  const targetDir = path.resolve(bundlesRoot, evidenceHash);

  // Check if identical bundle already exists (idempotent handling)
  if (fs.existsSync(targetDir)) {
    const existingManifestPath = path.join(targetDir, 'manifest.json');
    if (fs.existsSync(existingManifestPath)) {
      try {
        const existingContent = fs.readFileSync(existingManifestPath, 'utf-8');
        const existingManifest = JSON.parse(existingContent) as CanonicalEvidenceManifest;
        const newCanonicalJson = canonicalizeManifest(manifest);
        const existingCanonicalJson = canonicalizeManifest(existingManifest);

        if (newCanonicalJson === existingCanonicalJson) {
          // Identical bundle already stored cleanly
          const existingMetadataPath = path.join(targetDir, 'runtime-metadata.json');
          const existingMetadata = fs.existsSync(existingMetadataPath)
            ? (JSON.parse(fs.readFileSync(existingMetadataPath, 'utf-8')) as RuntimeMetadata)
            : runtimeMetadata;

          return {
            evidenceHash,
            bundleDir: targetDir,
            manifestPath: existingManifestPath,
            metadataPath: existingMetadataPath,
            artifactsDir: path.join(targetDir, 'artifacts'),
            manifest: existingManifest,
            runtimeMetadata: existingMetadata,
          };
        } else {
          throw new EvidenceCollisionError(
            evidenceHash,
            'Existing bundle manifest differs from incoming manifest'
          );
        }
      } catch (err) {
        if (err instanceof EvidenceCollisionError) throw err;
        throw new EvidenceCollisionError(
          evidenceHash,
          `Existing bundle under ${targetDir} is unparseable or corrupted: ${err instanceof Error ? err.message : String(err)}`
        );
      }
    }
  }

  // 2. Allocate staging directory
  const runId = runtimeMetadata.runId || 'default';
  const stagingDir = path.resolve(
    bundlesRoot,
    `.staging-${manifest.bountyId}-${runId}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
  );

  const stagingArtifactsDir = path.join(stagingDir, 'artifacts');
  fs.mkdirSync(stagingArtifactsDir, { recursive: true });

  try {
    // 3. Write and verify raw artifact files (only for executed criteria with digests)
    for (const cr of criteriaResults) {
      if (
        (cr.record.type === 'BUILD' || cr.record.type === 'TEST') &&
        cr.record.stdoutDigest !== undefined
      ) {
        validateCriterionIdForPath(cr.record.id);

        const stdoutBuffer = cr.stdoutBytes ?? Buffer.alloc(0);
        const stderrBuffer = cr.stderrBytes ?? Buffer.alloc(0);

        const stdoutFile = path.join(stagingArtifactsDir, `${cr.record.id}.stdout.bin`);
        const stderrFile = path.join(stagingArtifactsDir, `${cr.record.id}.stderr.bin`);

        assertPathWithinDirectory(stagingArtifactsDir, stdoutFile);
        assertPathWithinDirectory(stagingArtifactsDir, stderrFile);

        fs.writeFileSync(stdoutFile, stdoutBuffer);
        fs.writeFileSync(stderrFile, stderrBuffer);

        // Verify disk digest matches record digest
        const diskStdoutDigest = computeKeccak256Digest(fs.readFileSync(stdoutFile));
        const diskStderrDigest = computeKeccak256Digest(fs.readFileSync(stderrFile));

        if (diskStdoutDigest !== cr.record.stdoutDigest) {
          throw new EvidenceCommitmentError(
            `Digest mismatch on written stdout artifact for criterion "${cr.record.id}": expected ${cr.record.stdoutDigest}, got ${diskStdoutDigest}`
          );
        }
        if (diskStderrDigest !== cr.record.stderrDigest) {
          throw new EvidenceCommitmentError(
            `Digest mismatch on written stderr artifact for criterion "${cr.record.id}": expected ${cr.record.stderrDigest}, got ${diskStderrDigest}`
          );
        }
      }
    }

    // 4. Write manifest.json (canonical JSON)
    const canonicalManifestJson = canonicalizeManifest(manifest);
    const stagingManifestPath = path.join(stagingDir, 'manifest.json');
    fs.writeFileSync(stagingManifestPath, canonicalManifestJson, 'utf-8');

    // 5. Write runtime-metadata.json
    const stagingMetadataPath = path.join(stagingDir, 'runtime-metadata.json');
    fs.writeFileSync(
      stagingMetadataPath,
      JSON.stringify(runtimeMetadata, null, 2),
      'utf-8'
    );

    // 6. Atomic move / rename staging directory to targetDir
    try {
      fs.renameSync(stagingDir, targetDir);
    } catch (renameErr) {
      // On Windows or cross-process race, handle collision
      if (fs.existsSync(targetDir)) {
        const existingManifestPath = path.join(targetDir, 'manifest.json');
        if (fs.existsSync(existingManifestPath)) {
          try {
            const existingContent = fs.readFileSync(existingManifestPath, 'utf-8');
            const existingManifest = JSON.parse(existingContent) as CanonicalEvidenceManifest;
            if (canonicalizeManifest(existingManifest) === canonicalManifestJson) {
              try {
                fs.rmSync(stagingDir, { recursive: true, force: true });
              } catch {
                // Best effort cleanup
              }
            } else {
              try {
                fs.rmSync(stagingDir, { recursive: true, force: true });
              } catch {
                // Best effort cleanup
              }
              throw new EvidenceCollisionError(
                evidenceHash,
                'Concurrent collision with non-identical manifest'
              );
            }
          } catch (readErr) {
            try {
              fs.rmSync(stagingDir, { recursive: true, force: true });
            } catch {
              // Best effort cleanup
            }
            if (readErr instanceof EvidenceCollisionError) throw readErr;
            throw new EvidenceCollisionError(
              evidenceHash,
              `Concurrent collision with unreadable target: ${readErr instanceof Error ? readErr.message : String(readErr)}`
            );
          }
        } else {
          try {
            fs.rmSync(stagingDir, { recursive: true, force: true });
          } catch {
            // Best effort cleanup
          }
          throw new EvidenceCollisionError(
            evidenceHash,
            'Target directory created concurrently without manifest.json'
          );
        }
      } else {
        throw new EvidenceCommitmentError(
          `Failed to finalize evidence bundle directory rename: ${renameErr instanceof Error ? renameErr.message : String(renameErr)}`,
          renameErr
        );
      }
    }

    // 7. Post-Commitment verification: read back finalized manifest
    const finalManifestPath = path.join(targetDir, 'manifest.json');
    const finalMetadataPath = path.join(targetDir, 'runtime-metadata.json');
    const readBackContent = fs.readFileSync(finalManifestPath, 'utf-8');
    const readBackManifest = JSON.parse(readBackContent) as CanonicalEvidenceManifest;
    const verifiedEvidenceHash = computeEvidenceHash(readBackManifest);

    if (verifiedEvidenceHash !== evidenceHash) {
      throw new EvidenceVerificationError(
        `Finalized manifest hash mismatch: expected ${evidenceHash}, computed ${verifiedEvidenceHash}`,
        evidenceHash
      );
    }

    return {
      evidenceHash,
      bundleDir: targetDir,
      manifestPath: finalManifestPath,
      metadataPath: finalMetadataPath,
      artifactsDir: path.join(targetDir, 'artifacts'),
      manifest: readBackManifest,
      runtimeMetadata,
    };
  } catch (error) {
    // Clean up staging directory on failure
    try {
      if (fs.existsSync(stagingDir)) {
        fs.rmSync(stagingDir, { recursive: true, force: true });
      }
    } catch {
      // Ignore secondary cleanup error
    }
    if (error instanceof EvidenceCommitmentError) {
      throw error;
    }
    throw new EvidenceCommitmentError(
      `Evidence bundle persistence failed: ${error instanceof Error ? error.message : String(error)}`,
      error
    );
  }
}

export interface VerifiedBundleResult {
  valid: boolean;
  evidenceHash: string;
  manifest: CanonicalEvidenceManifest;
  runtimeMetadata?: RuntimeMetadata;
}

/**
 * Audits and cryptographically verifies an existing evidence bundle directory.
 *
 * Verifies:
 * 1. Directory name matches manifest evidenceHash.
 * 2. manifest.json matches RFC 8785 canonical hash.
 * 3. Artifact files match declared Keccak-256 digests in manifest.
 * 4. Artifact IDs are strictly validated against ^[A-Za-z0-9_-]{1,64}$ without path traversal.
 * 5. Artifact paths remain strictly within the bundle artifacts/ directory.
 * 6. No orphan or undeclared files exist in artifacts/.
 * 7. No unauthorized artifact files exist for unexecuted or COVERAGE criteria.
 */
export async function verifyEvidenceBundle(bundleDir: string): Promise<VerifiedBundleResult> {
  const dirName = path.basename(bundleDir);
  const manifestPath = path.join(bundleDir, 'manifest.json');

  if (!fs.existsSync(manifestPath)) {
    throw new EvidenceVerificationError(`Missing manifest.json in bundle ${bundleDir}`);
  }

  let manifest: CanonicalEvidenceManifest;
  try {
    const content = fs.readFileSync(manifestPath, 'utf-8');
    manifest = JSON.parse(content) as CanonicalEvidenceManifest;
  } catch (err) {
    throw new EvidenceVerificationError(
      `Corrupted or unparseable manifest.json in ${bundleDir}: ${err instanceof Error ? err.message : String(err)}`
    );
  }

  const computedHash = computeEvidenceHash(manifest);
  if (dirName.startsWith('0x') && dirName.toLowerCase() !== computedHash.toLowerCase()) {
    throw new EvidenceVerificationError(
      `Bundle directory name ${dirName} does not match computed evidenceHash ${computedHash}`,
      computedHash
    );
  }

  const artifactsDir = path.resolve(bundleDir, 'artifacts');
  const expectedArtifactFiles = new Set<string>();

  // 1. Verify all manifest criteria and expected artifact paths
  for (const criterion of manifest.criteria) {
    validateCriterionIdForPath(criterion.id);

    if (
      (criterion.type === 'BUILD' || criterion.type === 'TEST') &&
      criterion.stdoutDigest !== undefined
    ) {
      const stdoutName = `${criterion.id}.stdout.bin`;
      const stderrName = `${criterion.id}.stderr.bin`;

      expectedArtifactFiles.add(stdoutName);
      expectedArtifactFiles.add(stderrName);

      const stdoutPath = path.resolve(artifactsDir, stdoutName);
      const stderrPath = path.resolve(artifactsDir, stderrName);

      assertPathWithinDirectory(artifactsDir, stdoutPath);
      assertPathWithinDirectory(artifactsDir, stderrPath);

      if (!fs.existsSync(stdoutPath)) {
        throw new EvidenceVerificationError(
          `Missing stdout artifact for criterion "${criterion.id}" at ${stdoutPath}`
        );
      }
      if (!fs.existsSync(stderrPath)) {
        throw new EvidenceVerificationError(
          `Missing stderr artifact for criterion "${criterion.id}" at ${stderrPath}`
        );
      }

      // Prohibit symlinks
      if (fs.lstatSync(stdoutPath).isSymbolicLink()) {
        throw new EvidenceVerificationError(
          `Symbolic link rejected for artifact: "${stdoutName}"`
        );
      }
      if (fs.lstatSync(stderrPath).isSymbolicLink()) {
        throw new EvidenceVerificationError(
          `Symbolic link rejected for artifact: "${stderrName}"`
        );
      }

      const stdoutBytes = fs.readFileSync(stdoutPath);
      const stderrBytes = fs.readFileSync(stderrPath);

      const computedStdoutDigest = computeKeccak256Digest(stdoutBytes);
      const computedStderrDigest = computeKeccak256Digest(stderrBytes);

      if (computedStdoutDigest !== criterion.stdoutDigest) {
        throw new EvidenceVerificationError(
          `Stdout digest mismatch for criterion "${criterion.id}": manifest has ${criterion.stdoutDigest}, artifact has ${computedStdoutDigest}`
        );
      }

      if (computedStderrDigest !== criterion.stderrDigest) {
        throw new EvidenceVerificationError(
          `Stderr digest mismatch for criterion "${criterion.id}": manifest has ${criterion.stderrDigest}, artifact has ${computedStderrDigest}`
        );
      }
    } else {
      // Unexecuted or COVERAGE criteria: must NOT have artifact files on disk
      const stdoutPath = path.resolve(artifactsDir, `${criterion.id}.stdout.bin`);
      const stderrPath = path.resolve(artifactsDir, `${criterion.id}.stderr.bin`);
      if (fs.existsSync(stdoutPath) || fs.existsSync(stderrPath)) {
        throw new EvidenceVerificationError(
          `Unexpected artifact file found for unexecuted criterion: "${criterion.id}"`
        );
      }
    }
  }

  // 2. Detect orphan files in artifactsDir
  if (fs.existsSync(artifactsDir)) {
    const actualFiles = fs.readdirSync(artifactsDir);
    for (const file of actualFiles) {
      if (!expectedArtifactFiles.has(file)) {
        throw new EvidenceVerificationError(
          `Unexpected orphan file in artifacts directory: "${file}"`
        );
      }
    }
  }

  let runtimeMetadata: RuntimeMetadata | undefined;
  const metadataPath = path.join(bundleDir, 'runtime-metadata.json');
  if (fs.existsSync(metadataPath)) {
    try {
      runtimeMetadata = JSON.parse(fs.readFileSync(metadataPath, 'utf-8')) as RuntimeMetadata;
    } catch {
      // Optional metadata parse failure does not invalidate cryptographic manifest
    }
  }

  return {
    valid: true,
    evidenceHash: computedHash,
    manifest,
    runtimeMetadata,
  };
}
