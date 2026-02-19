---
description: Execute the SpecGate test planning workflow and generate test-spec.md as the single test execution source. (SpecGate workflow)
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
handoffs:
  - label: Implement Tests
    agent: test-write
    prompt: Execute /test-write using test-spec.md#test-code as the execution queue.
    send: true
---


## 0. Purpose & Inputs

This command plans tests and updates test artifacts for the active feature.

### User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Artifacts

**Generated/Updated**:

- `test-spec.md` (required, single source of truth)

## Workflow Overview

1. Resolve feature directory via pointer flow (`specs/feature-stage.local.json`).
2. Run `.specify/scripts/bash/specgate-sync-pointer.sh --feature-dir "<abs path>" --preserve-stage --json` to refresh pointer progress.
3. Run `.specify/scripts/bash/setup-test-spec.sh --json --feature-dir "<abs path>"`.
4. Validate implementation-readiness precondition before generating test plan:
   - `.specify/scripts/bash/check-code-prerequisites.sh --feature-dir "<abs path>" --json`
   - `.specify/scripts/bash/check-implementation-readiness.sh --feature-dir "<abs path>" --json`

   If readiness check reports `ready_for_test_spec: false`, STOP and keep `/test-spec` blocked until all blocking prerequisites are resolved.
5. Load context from:
   - `spec.md` (required)
   - `.specify/memory/constitution.md` (required)
   - `docs/TESTING_STANDARDS.md` (optional; fallback to constitution testing rules)
6. Build/refresh `test-spec.md` with mandatory sections:
   - `Metadata`
   - `Test Component Inventory`
   - `Test Matrix`
   - `test-code`
   - `Execution Context`
   - `Validation Commands`
   - `Coverage/Risk Notes`
7. Sync pointer after writing `test-spec.md`:
   ```bash
   .specify/scripts/bash/specgate-sync-pointer.sh \
     --feature-dir "<abs path>" \
     --status in_progress \
     --stage test_planning \
     --current-doc test-spec.md \
     --json
   ```
8. Report results and route to `/test-write`.

## Required test-spec.md Rules

### 1) Inventory Rule

Every planned test target must have a row in `Test Component Inventory` with:

- `Test ID`
- `Component`
- `Layer`
- `Source File`
- `Test File`
- `Coverage Target`
- `Existing Status` (`MISSING/PARTIAL/COMPLETE/LEGACY`)
- `Change Status` (`NEW/MODIFIED/UNCHANGED`)
- `Coverage Target` must be numeric percentage (`85%` or `85`)

### 2) Execution Queue Rule

- `## test-code` is the only executable task queue for `/test-write`.
- Task format:
  - `- [ ] TC001 [Layer] [Action] Description with test path`
- Actions: `NEW`, `UPDATE`, `REFACTOR`, `VERIFY`, `REGRESSION`.

### 3) Tracking Rule

- `## Execution Context` must be present and updated:
  - `Total`, `Pending`, `In Progress`, `Done`, `Blocked`, `Next Task`, `Last Updated`

## Coverage Policy

Use `docs/TESTING_STANDARDS.md` if available.
If missing, use `.specify/memory/constitution.md` testing discipline as fallback and note fallback in `Coverage/Risk Notes`.

## Completion Report

Report:

- Feature directory
- Count of `test-code` tasks
- Execution context summary
- Readiness status output from `check-implementation-readiness`
- Next command: `/test-write`
