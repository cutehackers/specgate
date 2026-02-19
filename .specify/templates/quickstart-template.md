# Quickstart Validation: [FEATURE NAME]

**Feature Directory**: `/path/to/feature`  
**Spec**: `<feature_dir>/docs/spec.md`  
**Plan**: `<feature_dir>/docs/code.md`  
**Screen Contracts**: `<feature_dir>/docs/screen_abstraction.md`  
**Created**: [DATE]

## Purpose

Provide executable validation scenarios for screen contracts. This file verifies
contract behavior and recovery handling; it does not redefine contract schema.

## Validation Scope

- Validate contract paths for P1/P2 stories first
- Validate success and error/recovery paths
- Validate integration touchpoints with data model and contracts where relevant

## Rules

- Reference screens by `screen` id from `screen_abstraction.md`
- Do not copy full `screen/input/output/ui_state/event/error_state` blocks
- Write scenarios as validation flows only
- Keep steps implementation-agnostic (no widget/layout/style details)

## Preconditions

- [Environment condition]
- [Required seed data]
- [Auth/permission state]

## Validation Scenarios

### QS-001 [US1] [SCREEN_ID] Happy Path

- `screen_ref`: [SCREEN_ID]
- `precondition`: [required state]
- `input`: [input data/context]
- `event`: [trigger]
- `expected`:
  - `ui_state`: [expected state transitions]
  - `output`: [expected domain/navigation outcomes]
- `cross_checks`:
  - [data-model entity/state expectation]
  - [contract interaction expectation]

### QS-002 [US1] [SCREEN_ID] Error and Recovery

- `screen_ref`: [SCREEN_ID]
- `precondition`: [required state]
- `input`: [input data/context]
- `event`: [error-triggering event]
- `expected`:
  - `ui_state`: [error state expectation]
  - `output`: [error-safe output expectation]
- `recovery`:
  - [user/system recovery action]
  - [expected post-recovery state]
- `cross_checks`:
  - [data-model rollback/retry expectation]
  - [contract error handling expectation]

### QS-003 [US2] [SCREEN_ID] Alternate Path

- `screen_ref`: [SCREEN_ID]
- `precondition`: [required state]
- `input`: [input data/context]
- `event`: [alternate trigger]
- `expected`:
  - `ui_state`: [expected state transitions]
  - `output`: [expected domain/navigation outcomes]
- `cross_checks`:
  - [data-model expectation]
  - [contract expectation]

## Completion Checklist

- [ ] Every P1/P2 screen contract has at least one quickstart scenario
- [ ] Every scenario references a valid `screen_ref`
- [ ] Error/recovery scenarios exist for declared `error_state`
- [ ] No duplicated abstraction schema blocks are present
