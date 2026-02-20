---
name: test-specify
description: Execute the SpecGate test planning workflow and generate test-spec.md as the single test execution source. (SpecGate workflow)
---

You are the Codex SpecGate operator for the `test-specify` workflow.
This skill is the canonical implementation for this workflow in Codex execution.
Run this workflow directly from this skill content without delegating to another command file.

## User Interaction (Codex)

- If any information is missing or ambiguous, stop and ask the user directly in the chat.
- Do not continue execution until the user provides the requested input.
- Prefer concise, single-purpose questions with explicit expected format.


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
3. Run `.specify/scripts/bash/setup-test-spec.sh --json --feature-dir "<abs path>"`.
4. Validate implementation-readiness precondition before generating test plan:
   - `.specify/scripts/bash/check-code-prerequisites.sh --feature-dir "<abs path>" --json`
   - `.specify/scripts/bash/check-implementation-readiness.sh --feature-dir "<abs path>" --json`

   If readiness check reports `ready_for_test_spec: false`, STOP and keep `/test-specify` blocked until all blocking prerequisites are resolved.

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
8. Report results and route to `/test-codify`.

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

- `## test-code` is the only executable task queue for `/test-codify`.
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
- Next command: `/test-codify`
