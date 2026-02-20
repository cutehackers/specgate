---
name: test-codify
description: Execute the SpecGate test implementation workflow using test-spec.md#test-code as the execution source. (SpecGate workflow)
---

You are the Codex SpecGate operator for the `test-codify` workflow.
This skill is the canonical implementation for this workflow in Codex execution.
Run this workflow directly from this skill content without delegating to another command file.

## User Interaction (Codex)

- If any information is missing or ambiguous, stop and ask the user directly in the chat.
- Do not continue execution until the user provides the requested input.
- Prefer concise, single-purpose questions with explicit expected format.


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

1. Resolve feature directory with this priority:
   1. Use local pointer path for this worktree:
      - `POINTER_PATH=specs/feature-stage.local.json`
   2. If `POINTER_PATH` exists and `status` != "done":
      - If `--feature-dir` is provided: **STOP** and tell the user to use `/feature-set` or `/feature-done` to change the current feature. `--feature-dir` is only allowed when no active feature is set.
      - Otherwise, use `feature_dir` from the pointer file.
   3. Otherwise (no pointer file, invalid, or `status` == "done"):
      - If `--feature-dir` is provided:
        - If absolute: use it.
        - If relative: search by **basename only** and present choices and ask the user in chat.
          ```bash
          REL_PATH="<provided>"
          REPO_ROOT="$(pwd)"
          BASENAME="$(basename "$REL_PATH")"
          CANDIDATES_ALL=$(find "$REPO_ROOT" -type d -name "$BASENAME" 2>/dev/null | sort -u)
          COUNT=$(printf "%s" "$CANDIDATES_ALL" | sed '/^$/d' | wc -l | tr -d ' ')
          CANDIDATES=$(printf "%s" "$CANDIDATES_ALL" | head -10)
          ```
          - If `COUNT` > 10, show only the first 10 and label the list as `10+` (e.g., "Showing 10 of $COUNT (10+)").
      - If `--feature-dir` is missing: ask the user in chat for an absolute path.
   4. Always end with an absolute path.
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
