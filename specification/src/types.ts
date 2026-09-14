export type CriterionType = 'BUILD' | 'TEST' | 'COVERAGE';

export interface BaseCriterion {
  id: string;
  type: CriterionType;
  required: boolean;
}

export interface BuildCriterion extends BaseCriterion {
  type: 'BUILD';
  command: string;
}

export interface TestCriterion extends BaseCriterion {
  type: 'TEST';
  command: string;
}

export interface CoverageCriterion extends BaseCriterion {
  type: 'COVERAGE';
  operator: '>=';
  thresholdBps: number;
}

export type AcceptanceCriterion = BuildCriterion | TestCriterion | CoverageCriterion;

export interface RepositoryRef {
  owner: string;
  name: string;
}

export interface AcceptanceSpecification {
  version: '1.0';
  repository: RepositoryRef;
  baseCommit: string;
  criteria: AcceptanceCriterion[];
}

export interface ValidationError {
  path: string;
  message: string;
}

export interface ValidationSuccess {
  valid: true;
  specification: AcceptanceSpecification;
}

export interface ValidationFailure {
  valid: false;
  errors: ValidationError[];
}

export type ValidationResult = ValidationSuccess | ValidationFailure;
