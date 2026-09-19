import type { RepositoryRef, RepositoryIdentityCheck } from './types.ts';

const SAFE_IDENTIFIER_REGEX = /^[a-zA-Z0-9_][a-zA-Z0-9._-]*$/;

/**
 * Validates that an identifier (owner or repository name) contains only safe characters
 * and does not attempt flag injection or path traversal.
 */
export function validateRepositoryIdentifier(value: string, fieldName: string): void {
  if (typeof value !== 'string' || !value.trim()) {
    throw new Error(`${fieldName} must be a non-empty string`);
  }
  const trimmed = value.trim();
  if (trimmed.startsWith('-')) {
    throw new Error(`${fieldName} cannot start with a hyphen (flag injection prevention)`);
  }
  if (!SAFE_IDENTIFIER_REGEX.test(trimmed)) {
    throw new Error(`${fieldName} contains invalid characters or path traversal elements: '${trimmed}'`);
  }
}

export interface CheckRepositoryIdentityOptions {
  allowFileProtocol?: boolean;
}

/**
 * Parses and verifies repository identity against the supplied repository location.
 * Establishes syntactic namespace consistency between location and specification.
 * Strictly restricts protocol schemes: only 'https://' in production; 'file:' only when allowed.
 */
export function checkRepositoryIdentity(
  repoLocation: string,
  repository: RepositoryRef,
  options: CheckRepositoryIdentityOptions = {}
): RepositoryIdentityCheck {
  if (typeof repoLocation !== 'string' || !repoLocation.trim()) {
    return {
      matches: false,
      ownerMatches: false,
      nameMatches: false,
      reason: 'Repository location must be a non-empty string',
    };
  }

  const trimmedLocation = repoLocation.trim();

  // Guard against command-line flag injection
  if (trimmedLocation.startsWith('-')) {
    return {
      matches: false,
      ownerMatches: false,
      nameMatches: false,
      reason: 'Repository location cannot start with a hyphen (flag injection protection)',
    };
  }

  // Guard against remote helper syntax (e.g. ext::..., fd::..., git::...)
  if (trimmedLocation.includes('::')) {
    return {
      matches: false,
      ownerMatches: false,
      nameMatches: false,
      reason: 'Remote helper syntax using "::" (e.g. ext::, fd::) is not permitted',
    };
  }

  // Guard against null bytes or control characters
  if (/[\0\r\n\t]/.test(trimmedLocation)) {
    return {
      matches: false,
      ownerMatches: false,
      nameMatches: false,
      reason: 'Repository location contains invalid control characters',
    };
  }

  // Reject scp-style SSH syntax (e.g. user@host:path or git@host:owner/repo)
  if (trimmedLocation.includes('@') && !trimmedLocation.includes('://')) {
    return {
      matches: false,
      ownerMatches: false,
      nameMatches: false,
      reason: 'SSH scp-style syntax (user@host:path) is not permitted. Only standard URLs are accepted.',
    };
  }

  // Validate protocol scheme
  let pathPart = trimmedLocation;
  if (trimmedLocation.includes('://')) {
    let parsedUrl: URL;
    try {
      parsedUrl = new URL(trimmedLocation);
    } catch {
      return {
        matches: false,
        ownerMatches: false,
        nameMatches: false,
        reason: `Invalid URL format: '${trimmedLocation}'`,
      };
    }

    const scheme = parsedUrl.protocol.toLowerCase();
    if (scheme === 'https:') {
      pathPart = parsedUrl.pathname;
    } else if (scheme === 'file:' && options.allowFileProtocol) {
      pathPart = parsedUrl.pathname;
    } else if (scheme === 'file:' && !options.allowFileProtocol) {
      return {
        matches: false,
        ownerMatches: false,
        nameMatches: false,
        reason: 'Local file protocol is restricted by default in production. Set allowFileProtocol: true for test fixtures.',
      };
    } else {
      return {
        matches: false,
        ownerMatches: false,
        nameMatches: false,
        reason: `Protocol '${scheme}' is not permitted. Production repositories must use 'https://'.`,
      };
    }
  } else {
    // Location does not have '://'
    if (!options.allowFileProtocol) {
      return {
        matches: false,
        ownerMatches: false,
        nameMatches: false,
        reason: "Local file transport is restricted by default in production. Production repositories must use an explicit 'https://' URL.",
      };
    }
    pathPart = trimmedLocation;
  }

  if (
    !repository ||
    typeof repository.owner !== 'string' ||
    !repository.owner.trim() ||
    typeof repository.name !== 'string' ||
    !repository.name.trim()
  ) {
    return {
      matches: false,
      ownerMatches: false,
      nameMatches: false,
      reason: 'Repository owner and name must be non-empty strings',
    };
  }

  // Validate characters of owner and name
  try {
    validateRepositoryIdentifier(repository.owner, 'repository.owner');
    validateRepositoryIdentifier(repository.name, 'repository.name');
  } catch (err: unknown) {
    return {
      matches: false,
      ownerMatches: false,
      nameMatches: false,
      reason: err instanceof Error ? err.message : String(err),
    };
  }

  const expectedOwner = repository.owner.trim().toLowerCase();
  const expectedName = repository.name.trim().toLowerCase();

  // Strip trailing slashes and optional .git extension
  const cleaned = pathPart.replace(/\.git$/i, '').replace(/[/\\]+$/, '');

  // Split into path segments (handling both / and \)
  const segments = cleaned
    .split(/[/\\]+/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0 && s !== '.');

  if (segments.length === 0) {
    return {
      matches: false,
      ownerMatches: false,
      nameMatches: false,
      reason: 'No path segments found in repository location',
    };
  }

  const lastSegment = segments[segments.length - 1].toLowerCase();
  const nameMatches = lastSegment === expectedName;

  if (!nameMatches) {
    return {
      matches: false,
      ownerMatches: false,
      nameMatches: false,
      reason: `Repository name mismatch: location specifies '${segments[segments.length - 1]}', expected '${repository.name}'`,
    };
  }

  if (segments.length >= 2) {
    const secondLastSegment = segments[segments.length - 2].toLowerCase();
    const ownerMatches = secondLastSegment === expectedOwner;

    if (!ownerMatches) {
      return {
        matches: false,
        ownerMatches: false,
        nameMatches: true,
        reason: `Repository owner mismatch: location specifies '${segments[segments.length - 2]}', expected '${repository.owner}'`,
      };
    }

    return {
      matches: true,
      ownerMatches: true,
      nameMatches: true,
    };
  }

  // Only single segment available (e.g. flat local directory in test mode)
  return {
    matches: true,
    ownerMatches: false,
    nameMatches: true,
    reason: 'Repository name matched; owner segment omitted in flat path location',
  };
}
