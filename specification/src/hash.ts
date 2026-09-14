import { keccak256 } from 'js-sha3';
import type { AcceptanceSpecification } from './types.ts';
import { canonicalizeSpecification } from './canonicalize.ts';

/**
 * Computes the cryptographic commitment of an acceptance specification.
 *
 * Commitment formula:
 *   specHash = Keccak-256(RFC8785(specification))
 *
 * Returns a normalized lowercase 0x-prefixed 32-byte (64 hex character) string.
 */
export function hashSpecification(spec: AcceptanceSpecification | unknown): string {
  const canonicalJson = canonicalizeSpecification(spec);
  const digest = keccak256(canonicalJson).toLowerCase();
  return `0x${digest}`;
}
