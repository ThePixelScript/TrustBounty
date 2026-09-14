import type { AcceptanceSpecification, ValidationResult, ValidationError } from './types.ts';

const VALID_CRITERION_TYPES = new Set(['BUILD', 'TEST', 'COVERAGE']);
const ALLOWED_TOP_LEVEL_KEYS = new Set(['version', 'repository', 'baseCommit', 'criteria']);
const ALLOWED_REPOSITORY_KEYS = new Set(['owner', 'name']);
const ALLOWED_BUILD_TEST_CRITERION_KEYS = new Set(['id', 'type', 'command', 'required']);
const ALLOWED_COVERAGE_CRITERION_KEYS = new Set(['id', 'type', 'operator', 'thresholdBps', 'required']);

/**
 * Pure validation function for AcceptanceSpecification.
 * Validates structure, types, constraints, and business rules without mutating input.
 */
export function validateSpecification(input: unknown): ValidationResult {
  const errors: ValidationError[] = [];

  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    return {
      valid: false,
      errors: [
        {
          path: '',
          message: 'Specification must be a non-null object',
        },
      ],
    };
  }

  const spec = input as Record<string, unknown>;

  // Reject unknown top-level keys
  for (const key of Object.keys(spec)) {
    if (!ALLOWED_TOP_LEVEL_KEYS.has(key)) {
      errors.push({
        path: key,
        message: `Unknown field: "${key}"`,
      });
    }
  }

  // Version check
  if (typeof spec.version !== 'string' || spec.version !== '1.0') {
    errors.push({
      path: 'version',
      message: 'Specification version must be "1.0"',
    });
  }

  // Repository check
  if (typeof spec.repository !== 'object' || spec.repository === null || Array.isArray(spec.repository)) {
    errors.push({
      path: 'repository',
      message: 'Specification repository must be a non-null object',
    });
  } else {
    const repo = spec.repository as Record<string, unknown>;
    for (const key of Object.keys(repo)) {
      if (!ALLOWED_REPOSITORY_KEYS.has(key)) {
        errors.push({
          path: `repository.${key}`,
          message: `Unknown field: "repository.${key}"`,
        });
      }
    }
    if (typeof repo.owner !== 'string' || repo.owner.trim() === '') {
      errors.push({
        path: 'repository.owner',
        message: 'Repository owner must be a non-empty string',
      });
    }
    if (typeof repo.name !== 'string' || repo.name.trim() === '') {
      errors.push({
        path: 'repository.name',
        message: 'Repository name must be a non-empty string',
      });
    }
  }

  // baseCommit check
  if (typeof spec.baseCommit !== 'string' || spec.baseCommit.trim() === '') {
    errors.push({
      path: 'baseCommit',
      message: 'Specification baseCommit must be a non-empty string',
    });
  }

  // Criteria check
  if (!Array.isArray(spec.criteria)) {
    errors.push({
      path: 'criteria',
      message: 'Specification criteria must be an array',
    });
  } else if (spec.criteria.length === 0) {
    errors.push({
      path: 'criteria',
      message: 'Specification criteria must contain at least one criterion',
    });
  } else {
    const seenIds = new Set<string>();

    for (let i = 0; i < spec.criteria.length; i++) {
      const item = spec.criteria[i];
      const basePath = `criteria[${i}]`;

      if (typeof item !== 'object' || item === null || Array.isArray(item)) {
        errors.push({
          path: basePath,
          message: 'Criterion must be a non-null object',
        });
        continue;
      }

      const criterion = item as Record<string, unknown>;

      // id check
      if (typeof criterion.id !== 'string' || criterion.id.trim() === '') {
        errors.push({
          path: `${basePath}.id`,
          message: 'Criterion id must be a non-empty string',
        });
      } else if (seenIds.has(criterion.id)) {
        errors.push({
          path: `${basePath}.id`,
          message: `Duplicate criterion ID: "${criterion.id}"`,
        });
      } else {
        seenIds.add(criterion.id);
      }

      // required check
      if (typeof criterion.required !== 'boolean') {
        errors.push({
          path: `${basePath}.required`,
          message: 'Criterion required must be a boolean',
        });
      }

      // type check and type-specific fields
      if (typeof criterion.type !== 'string' || !VALID_CRITERION_TYPES.has(criterion.type)) {
        errors.push({
          path: `${basePath}.type`,
          message: `Unknown or unsupported criterion type: "${String(criterion.type)}". Supported types: BUILD, TEST, COVERAGE`,
        });
      } else if (criterion.type === 'BUILD' || criterion.type === 'TEST') {
        for (const key of Object.keys(criterion)) {
          if (!ALLOWED_BUILD_TEST_CRITERION_KEYS.has(key)) {
            errors.push({
              path: `${basePath}.${key}`,
              message: `Unknown field: "${basePath}.${key}"`,
            });
          }
        }
        if (typeof criterion.command !== 'string' || criterion.command.trim() === '') {
          errors.push({
            path: `${basePath}.command`,
            message: `Command must be a non-empty string for ${criterion.type} criterion`,
          });
        }
      } else if (criterion.type === 'COVERAGE') {
        for (const key of Object.keys(criterion)) {
          if (!ALLOWED_COVERAGE_CRITERION_KEYS.has(key)) {
            errors.push({
              path: `${basePath}.${key}`,
              message: `Unknown field: "${basePath}.${key}"`,
            });
          }
        }
        if (criterion.operator !== '>=') {
          errors.push({
            path: `${basePath}.operator`,
            message: `Unsupported coverage operator: "${String(criterion.operator)}". Only ">=" is supported in v1.0`,
          });
        }

        const threshold = criterion.thresholdBps;
        if (
          typeof threshold !== 'number' ||
          !Number.isInteger(threshold) ||
          threshold < 0 ||
          threshold > 10000
        ) {
          errors.push({
            path: `${basePath}.thresholdBps`,
            message: 'Coverage threshold must be an integer between 0 and 10000 basis points',
          });
        }
      }
    }
  }

  if (errors.length > 0) {
    return {
      valid: false,
      errors,
    };
  }

  return {
    valid: true,
    specification: spec as unknown as AcceptanceSpecification,
  };
}
