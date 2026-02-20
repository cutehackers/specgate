# Feature Specification: [FEATURE NAME]

## Metadata

- **Feature Directory**: `/path/to/feature`
- **Feature ID**: `package_name:relative/feature/path`
- **Created**: [DATE]
- **Updated**: [DATE]
- **Status**: Draft
- **Architecture Baseline**: `docs/ARCHITECTURE.md`
- **Naming Source**: `<resolved docs/ARCHITECTURE.md or constitution path>`
- **Input**: "$ARGUMENTS"

## Problem Statement & Scope

### Problem Statement

[Describe the user/business problem this feature solves.]

### In Scope

- [Capability in scope]
- [Capability in scope]

### Out of Scope

- [Explicitly excluded capability]
- [Explicitly excluded capability]

## User Scenarios

> Use stable IDs. Prioritize by delivery value. Every scenario must be independently testable.

### US-001 [Title] (Priority: P1)

- **User Goal**: [Who wants what and why]
- **Independent Completion**: [How to validate this scenario alone]
- **Acceptance Scenarios**:

1. **Given** [context], **When** [action], **Then** [outcome]
2. **Given** [context], **When** [action], **Then** [outcome]

### US-002 [Title] (Priority: P2)

- **User Goal**: [Who wants what and why]
- **Independent Completion**: [How to validate this scenario alone]
- **Acceptance Scenarios**:

1. **Given** [context], **When** [action], **Then** [outcome]

### US-003 [Title] (Priority: P3)

- **User Goal**: [Who wants what and why]
- **Independent Completion**: [How to validate this scenario alone]
- **Acceptance Scenarios**:

1. **Given** [context], **When** [action], **Then** [outcome]

## Acceptance Matrix

| Scenario ID | Given | When | Then | Verification |
|-------------|-------|------|------|--------------|
| AC-001 | [state] | [action] | [expected] | [manual/test/checklist] |
| AC-002 | [state] | [action] | [expected] | [manual/test/checklist] |

## Functional Requirements

| FR-ID | Requirement | Acceptance | Architecture Mapping | Verification |
|------|-------------|------------|----------------------|--------------|
| FR-001 | System MUST [capability] | [criteria] | [Presentation/Domain/Data] | [test/check] |
| FR-002 | System MUST [capability] | [criteria] | [Presentation/Domain/Data] | [test/check] |
| FR-003 | System MUST [capability] | [criteria] | [Presentation/Domain/Data] | [test/check] |

## Domain Model

### Entities

- **[Entity]**: [Role, key fields, identifier]
- **[Entity]**: [Role, key fields, identifier]

### Relationships

- [Relationship rule]
- [Relationship rule]

### Lifecycle & Constraints

- [State transition]
- [Validation or invariant]

## Edge Cases

- [Boundary condition handling]
- [Concurrency/conflict handling]
- [Failure and recovery handling]
- [Empty/no-data handling]
- [Permission/security handling]

## Architecture Compliance

> Validate against resolved naming source:
> `docs/ARCHITECTURE.md` (if naming section exists) or Constitution fallback.

| Check | Status (PASS/OPEN) | Notes |
|------|---------------------|-------|
| Layer dependency rule (`Presentation -> Domain <- Data`) | [PASS/OPEN] | [note] |
| Domain framework-agnostic rule | [PASS/OPEN] | [note] |
| Riverpod/event-driven pattern alignment | [PASS/OPEN] | [note] |
| Screen abstraction-only policy for presentation planning | [PASS/OPEN] | [note] |
| Generic naming ambiguity policy (`utils.dart`, `helpers.dart`, `Util`, `Helper`, `Manager`) | [PASS/OPEN] | [note] |

## Success Criteria

| SC-ID | Metric | Target | Measurement Method |
|------|--------|--------|--------------------|
| SC-001 | [metric] | [target] | [method] |
| SC-002 | [metric] | [target] | [method] |
| SC-003 | [metric] | [target] | [method] |

## Clarifications

### Session [YYYY-MM-DD]

- Q: [question] -> A: [answer]

## Assumptions

- [Assumption]
- [Assumption]
- [Assumption]

## Authoring Guardrails

- Keep this file focused on behavior and requirements, not implementation details.
- Do not specify concrete widget/layout/style/animation implementation.
- Keep requirements testable, measurable, and architecture-aware.
- Move unresolved ambiguity to `clarify.md` and `## Clarifications` entries.
- Keep implementation sequencing and task queues in `tasks.md`, not in this file.
