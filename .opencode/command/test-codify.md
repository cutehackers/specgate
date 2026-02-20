---
description: Execute the SpecGate test implementation workflow using test-spec.md#test-code as the execution source. (SpecGate workflow)
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---

## 0. Purpose & Inputs

This command executes the test plan defined in `test-spec.md` and updates progress in the same file.

### User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Artifacts

**Read**:

- `test-spec.md` (required)
- `spec.md`, `tasks.md`, `data-model.md` (optional context)

**Write**:

- `test/**` test code files
- `test-spec.md` (`test-code` checkboxes + `Execution Context` only)

## Workflow Overview

1. Resolve feature directory from pointer flow.
2. Run `.specify/scripts/bash/specgate-sync-pointer.sh --feature-dir "<abs path>" --preserve-stage --json` to refresh pointer progress.
3. Run `.specify/scripts/bash/check-test-prerequisites.sh --json --feature-dir "<abs path>"`.
4. Read `test-spec.md` and parse:
   - `Test Component Inventory`
   - `test-code`
   - `Execution Context`
5. Execute `test-code` tasks in phase order.
6. After each completed task:
   - mark checkbox complete in `test-code`
   - update `Execution Context` counters and `Next Task`
   - run:
     ```bash
     .specify/scripts/bash/specgate-sync-pointer.sh \
       --feature-dir "<abs path>" \
       --status in_progress \
       --stage test_writing \
       --current-doc test-spec.md \
       --json
     ```
7. Verify scoped tests and coverage, then run coverage target gate:
   ```bash
   .specify/scripts/bash/check-test-coverage-targets.sh \
     --feature-dir "<abs path>" \
     --lcov coverage/lcov.info \
     --allow-missing-lcov \
     --json
   ```
   - If this gate fails, keep related `test-code` tasks unresolved and report target deltas.
   - If lcov is not yet generated, this command exits successfully with skipped status; report as a warning and continue.
8. Run final pointer sync using the same command and report outcomes.

## Preconditions

- `test-spec.md` must exist.
- `test-spec.md` must include `## test-code` and `## Execution Context`.
- If `docs/TESTING_STANDARDS.md` is missing, use constitution testing rules and log fallback in report.

## Execution Rules

- Never modify production source in `lib/`.
- Only write/update test artifacts under `test/`.
- Keep package boundaries: source and tests stay in the same package.
- Maintain mirrored path rule (`lib/...` -> `test/...`).

## Validation Commands

Run relevant commands for affected package roots:

```bash
flutter test --no-pub
flutter test --coverage --no-pub
dart run build_runner build --delete-conflicting-outputs
 .specify/scripts/bash/check-test-coverage-targets.sh --feature-dir "<abs path>" --lcov coverage/lcov.info --allow-missing-lcov --json
```

## Progress Tracking Rules

Update only inside `test-spec.md`:

- In `## test-code`: checkboxes for task completion
- In `## Execution Context`: `Total`, `Pending`, `In Progress`, `Done`, `Blocked`, `Next Task`, `Last Updated`

## Completion Report

Include:

- Mode (`full` or scoped)
- Updated test files count
- Completed task count from `test-code`
- Final `Execution Context`
- Coverage summary vs target (must include coverage gate result)
