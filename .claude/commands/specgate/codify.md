---
description: Execute implementation for a feature based on finalized /clarify artifacts.
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
handoffs: 
  - label: Create Checklist
    agent: checklist
    prompt: Create a checklist for the following domain...
---



## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

`/codify` is the authoritative implementation step.
Default execution flow: `/specify` -> `/clarify` -> `/codify` -> `/test-specify` -> `/test-codify`.

1. **Setup**:
   - Resolve `feature-dir` with this priority:
     1. Use local pointer path for this worktree:
        - `POINTER_PATH=specs/feature-stage.local.json`
     2. If `POINTER_PATH` exists and `status` != "done":
        - If `--feature-dir` is provided: **STOP** and tell the user to use `/feature-set` or `/feature-done` to change the current feature. `--feature-dir` is only allowed when no active feature is set.
        - Otherwise, use `feature_dir` from the pointer file.
     3. Otherwise (no pointer file, invalid, or `status` == "done"):
        - If `--feature-dir` is provided:
          - If absolute: use it.
          - If relative: search by **basename only** and present choices with `AskUserQuestion`.
            Example (run from repo root):
            ```bash
            REL_PATH="<provided>"
            REPO_ROOT="$(pwd)"
            BASENAME="$(basename "$REL_PATH")"
            CANDIDATES_ALL=$(find "$REPO_ROOT" -type d -name "$BASENAME" 2>/dev/null | sort -u)
            COUNT=$(printf "%s" "$CANDIDATES_ALL" | sed '/^$/d' | wc -l | tr -d ' ')
            CANDIDATES=$(printf "%s" "$CANDIDATES_ALL" | head -10)
            ```
            - If `COUNT` > 10, show only the first 10 and label the list as `10+` (e.g., "Showing 10 of $COUNT (10+)").
        - If `--feature-dir` is missing: ask for an absolute path via `AskUserQuestion`.
   - Always end with an absolute path.
   - After resolving feature path, run:
     ```bash
     .specify/scripts/bash/specgate-sync-pointer.sh --feature-dir "<abs path>" --preserve-stage --json
     ```
     to refresh pointer progress before implementation.
 - Resolve naming policy source for coding checks:
     1. Use `<FEATURE_DIR>/docs/ARCHITECTURE.md` or `<FEATURE_DIR>/docs/architecture.md` when it has one of:
        - A section heading `Naming Rules`, `Naming Convention`, or `Naming Policy`
        - A matching heading regex `^#{1,4}\s*Naming\s+(Rules|Convention|Policy)\s*$` (case-insensitive)
        - A usable naming rule in a JSON code block
     2. If none of the above apply, fallback to:
        - `<FEATURE_DIR>/docs/constitution.md`
        - `<FEATURE_DIR>/constitution.md`
        - `<REPO_ROOT>/.specify/memory/constitution.md`
     3. If still missing, use default repository naming guardrails. Strict production sequence requires `--no-strict-naming` or pre-correction.
   - Persist result as `NAMING_SOURCE_FILE`.
   - Then run `.specify/scripts/bash/setup-code.sh --json --feature-dir "<abs path>"` from repo root and parse JSON for FEATURE_SPEC, CODE_DOC, FEATURE_DIR, FEATURE_DOCS_DIR.
   - Resolve required artifact paths from FEATURE_DOCS_DIR:
     - `DATA_MODEL=<FEATURE_DOCS_DIR>/data-model.md`
     - `SCREEN_ABSTRACTION=<FEATURE_DOCS_DIR>/screen_abstraction.md`
     - `QUICKSTART=<FEATURE_DOCS_DIR>/quickstart.md`
     - `RESEARCH=<FEATURE_DOCS_DIR>/research.md`
     - `CONTRACTS_DIR=<FEATURE_DIR>/contracts`
   - After successful completion, sync pointer:
     ```bash
     .specify/scripts/bash/specgate-sync-pointer.sh \
       --feature-dir "<abs path>" \
       --status in_progress \
       --stage coding \
       --current-doc tasks.md \
       --json
     ```
     - `feature_id` and `progress` are synchronized automatically from feature docs.

2. **Run spec gate**: Execute `.specify/scripts/bash/check-spec-prerequisites.sh --feature-dir "<abs path>"` and stop on failure.

3. **Load context**: Read FEATURE_SPEC and resolved naming policy source (from step 1). Read planning outputs from `specify/clarify` stage as implementation source:
   - `RESEARCH` (informational decisions)
   - `DATA_MODEL`
   - `SCREEN_ABSTRACTION`
   - `QUICKSTART`
   - `CODE_DOC` (`tasks.md`)

3.1 **Implementation artifact gate (required before coding)**:
   - If any of `DATA_MODEL`, `SCREEN_ABSTRACTION`, `QUICKSTART`, or `CODE_DOC` is missing/empty, **STOP** and ask for `/clarify`.
   - If required sections are missing from `tasks.md` (e.g. `## code-tasks`), **STOP** and ask for `/clarify`.
   - Confirm `data-model.md` and `screen_abstraction.md` are in alignment:
     - screen `event` must exist in data-model related context
     - user stories in `spec.md` must be represented by at least one screen contract
   - Confirm `quickstart.md` has executable validation scenarios.
   - Confirm implemented naming identifiers align with resolved naming source:
     - entity names, events, screen IDs, and task naming conventions follow the selected policy.

4. **Execute implementation from tasks.md**:
   - `/codify` does not generate/overwrite planning artifacts; it must only consume `screen_abstraction.md`, `data-model.md`, `quickstart.md`, and `tasks.md` to implement code and tests.
   - Parse `tasks.md` and implement tasks in dependency order:
     - `P1` tasks first, then `P2`, then `P3`.
     - Respect `[P]` parallel markers and explicit dependency notes.
   - For each task:
     - implement code artifacts in the target repo paths
     - add/adjust tests for changed behavior
     - include quickstart-linked validation when task scope applies
     - update task status to `[x]` only after verification.
   - If a task is blocked by unresolved ambiguity, mark it pending and route the blocker to `/clarify` immediately.

5. **Implementation validation**:
   - Validate touched areas against `quickstart.md` scenarios and relevant contract assumptions.
   - Run `.specify/scripts/bash/check-implementation-quality.sh --feature-dir "<abs path>" --json` and stop on failure.
   - Run targeted project tests that cover implemented P1/P2 tasks.

6. **Run code gate**: Execute `.specify/scripts/bash/check-code-prerequisites.sh --feature-dir "<abs path>"` and stop on failure.

7. **Stop and report**: Report feature directory, CODE_DOC path, executed task IDs, test results, and confirm pointer is in `coding` stage (`current_doc: tasks.md`).
   - Include naming source category (`ARCHITECTURE`/`CONSTITUTION`/`DEFAULT`) and path for traceability.

## Phases

### Phase 0: Traceability lock

- Cross-check each open task against:
  - `screen_abstraction.md` event/output contracts
  - `data-model.md` entities and transitions
  - `quickstart.md` validation scenarios
  - Naming policy source applied to implemented identifiers
- Reject implementation if contract mapping or naming alignment is missing.

### Phase 1: Implementation execution

- Implement tasks in strict execution order by `tasks.md`:
  - setup/foundational tasks
  - story-level feature tasks
  - cross-cutting/refactor tasks
- Keep task descriptions implementation-oriented and code-first.
- Preserve completed tasks and existing task IDs while implementing.

### Phase 2: Verification

- For each completed area:
  - run quickstart-derived validations
  - run quality gate command
  - update task outcome notes in tasks.md when useful
- Keep tasks.md checkbox state authoritative for execution status.

## Priority policy (P1/P2/P3)

- `P1`: Must-have for baseline acceptance. Must complete before `/codify` transitions to `/test-specify`.
- `P2`: Required for release quality and major flow coverage.
- `P2-BLOCKING` tasks are required before transitioning from `/codify` to `/test-specify`.
- `P3`: Optional polish tasks tracked for backlog.

## Key rules

- Use absolute paths only.
- `/codify` is implementation-only; it must not create design artifacts (`research.md`, `screen_abstraction.md`, `data-model.md`, `quickstart.md`).
- If planning artifacts diverge from implementation reality, pause and request `/clarify`.
- `tasks.md` is the implementation execution log and remains mandatory artifact name.
