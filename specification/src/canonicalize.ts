import canonicalize from 'canonicalize';
import type { AcceptanceSpecification } from './types.ts';
import { validateSpecification } from './validate.ts';

/**
 * Produces a deterministic RFC 8785 canonical JSON string for a validated specification.
 * Rejects unvalidated or invalid specifications.
 * Does not mutate the input.
 */
export function canonicalizeSpecification(spec: AcceptanceSpecification | unknown): string {
  const validation = validateSpecification(spec);
  if (!validation.valid) {
    const errorSummary = validation.errors.map((e) => `${e.path}: ${e.message}`).join('; ');
    throw new TypeError(`Cannot canonicalize invalid specification: ${errorSummary}`);
  }

  const result = canonicalize(validation.specification);
  if (result === undefined) {
    throw new Error('Canonicalization produced undefined output');
  }

  return result;
}
