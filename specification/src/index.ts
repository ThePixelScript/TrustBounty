export type {
  AcceptanceSpecification,
  RepositoryRef,
  ExecutionEnvironment,
  AcceptanceCriterion,
  BuildCriterion,
  TestCriterion,
  CoverageCriterion,
  CriterionType,
  ValidationResult,
  ValidationSuccess,
  ValidationFailure,
  ValidationError,
} from './types.ts';

export { validateSpecification } from './validate.ts';
export { canonicalizeSpecification } from './canonicalize.ts';
export { hashSpecification } from './hash.ts';
