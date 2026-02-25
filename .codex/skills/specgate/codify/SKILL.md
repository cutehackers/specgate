---
name: codify
description: Execute implementation for a feature based on finalized /clarify artifacts.
---

You are the Codex SpecGate operator for the `codify` workflow.
This skill is the canonical implementation workflow in Codex execution.
Run this workflow directly from this skill content without delegating to another command file.

## User Interaction (Codex)

- If any information is missing or ambiguous, stop and ask the user directly in the chat.
- Do not continue execution until the user provides the requested input.
- Prefer concise, single-purpose questions with explicit expected format.


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

`/codify` is the authoritative implementation step.
Default execution flow: `/specify` -> `/clarify` -> `/codify` -> `/test-specify` -> `/test-codify` (implementation then test execution).

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
          - If relative: search by **basename only** and present choices and ask the user in chat.
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
        - If `--feature-dir` is missing: ask the user in chat for an absolute path.
   - Always end with an absolute path.
   - After resolving feature path, run:
     ```bash
     .specify/scripts/bash/specgate-sync-pointer.sh --feature-dir "<abs path>" --preserve-stage --json
     ```
     to refresh pointer progress before implementation.
   - Resolve naming policy source for coding checks:
     1. `<FEATURE_DIR>/docs/ARCHITECTURE.md` or `<FEATURE_DIR>/docs/architecture.md` if it contains:
        - a machine-readable `json` code-block naming section
        - a valid section heading (`Naming Rules`, `Naming Convention`, `Naming Policy`)
        - heading regex: `^#{1,4}\s*Naming\s+(Rules|Convention|Policy)\s*$` (case-insensitive)
        - substantive rule content
     2. If absent/unusable, fallback to:
        - `<FEATURE_DIR>/docs/constitution.md`
        - `<FEATURE_DIR>/constitution.md`
        - `<REPO_ROOT>/.specify/memory/constitution.md`
     3. If neither has usable guidance, use existing repository default naming guardrails.
        - In production validation (`run-feature-workflow-sequence` with strict mode), missing or invalid `json` naming policy is treated as a blocking error.
     - Store result as `NAMING_SOURCE_FILE` for use in implementation trace checks.
   - Resolve layer policy source for coding checks:
     - `.specify/layer_rules/contract.yaml`
     - `.specify/layer_rules/overrides/<feature-id>.yaml`
     - feature `docs/ARCHITECTURE.md`/`docs/architecture.md` (when included in machine-readable `layer_rules` block)
     - feature `constitution` documents
     - repository memory constitution
     - If none exists and strict mode is requested, stop and bootstrap policy files before implementation.
   - Then run `.specify/scripts/bash/setup-code.sh --json --feature-dir "<abs path>"` from repo root and parse JSON for FEATURE_SPEC, CODE_DOC, FEATURE_DIR, FEATURE_DOCS_DIR.
     - Keep these layer fields available while generating implementation:
       - `LAYER_RULES_SOURCE_KIND`, `LAYER_RULES_SOURCE_FILE`, `LAYER_RULES_SOURCE_REASON`
       - `LAYER_RULES_POLICY_JSON`, `LAYER_RULES_RESOLVED_PATH`, `LAYER_RULES_HAS_LAYER_RULES`
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

3. **Load context**: Read FEATURE_SPEC and resolved naming policy source (from step 1.1). Read planning outputs from `specify/clarify` stage as implementation source:
   - `RESEARCH` (informational decisions)
   - `DATA_MODEL`
   - `SCREEN_ABSTRACTION`
   - `QUICKSTART`
   - `CODE_DOC` (`tasks.md`)
   - If `NAMING_SOURCE_FILE` is `DEFAULT`, record `Architecture Baseline` fallback note in execution log before coding.

3.1 **Implementation artifact gate (required before coding)**:
   - If any of `DATA_MODEL`, `SCREEN_ABSTRACTION`, `QUICKSTART`, or `CODE_DOC` is missing/empty, **STOP** and ask for `/clarify`.
   - If required sections are missing from `tasks.md` (e.g. `## code-tasks`), **STOP** and ask for `/clarify`.
   - Confirm `data-model.md` and `screen_abstraction.md` are in alignment:
     - screen `event` must exist in data-model related context
     - user stories in `spec.md` must be represented by at least one screen contract
   - Confirm `quickstart.md` has executable validation scenarios.
   - Confirm implemented naming identifiers align with resolved naming source:
      - entity names, events, screen IDs, and repository/task naming follow the selected naming policy
      - any conflict found should block implementation and route to `/clarify`.
   - Confirm resolved layer policy can drive implementation:
     - Domain/Data/Presentation file paths must honor `LAYER_RULES_POLICY_JSON` restrictions.
     - Use-case policy constraints (return-type requirements, forbidden direct repository implementation usage) are enforced.
     - strict mode requires `LAYER_RULES_HAS_LAYER_RULES=true`; otherwise stop and request policy bootstrap.

4. **Execute implementation from tasks.md**:
   - `/codify` does not generate/overwrite planning artifacts; it must only consume `screen_abstraction.md`, `data-model.md`, `quickstart.md`, and `tasks.md` to implement code and tests.
   - Parse `tasks.md` and implement tasks in dependency order:
     - `P1` tasks first, then `P2`, then `P3`.
     - Respect `[P]` parallel markers and explicit dependency notes.
  - For each task:
     - implement code artifacts in the target repo paths
     - enforce layer constraints for each target file before editing:
       - map file path to target layer and validate against the resolved layer policy
       - reject forbidden imports (`forbid_import_patterns`) and forbidden cross-layer references
     - add/adjust tests for changed behavior
      - include quickstart-linked validation when task scope applies
      - update task status to `[x]` only after verification.
   - If a task is blocked by unresolved ambiguity, mark it pending and route the blocker to `/clarify` immediately.

5. **Implementation validation**:
   - Validate touched areas against `quickstart.md` scenarios and relevant contract assumptions.
   - Run `.specify/scripts/bash/check-layer-compliance.sh --feature-dir "<abs path>" --strict-layer --json` and fix blocking violations.
   - Run `.specify/scripts/bash/check-implementation-quality.sh --feature-dir "<abs path>" --json` and stop on failure.
   - Run targeted project tests that cover implemented P1/P2 tasks.

6. **Run code gate**: Execute `.specify/scripts/bash/check-code-prerequisites.sh --feature-dir "<abs path>"` and stop on failure.

7. **Stop and report**: Report feature directory, CODE_DOC path, executed task IDs, test results, naming source (`ARCHITECTURE`/`CONSTITUTION`/`DEFAULT` + path), layer source (`CONTRACT`/`OVERRIDE`/`FEATURE`/`DEFAULT` + path), and confirm pointer is in `coding` stage (`current_doc: tasks.md`).

## Phases

### Phase 0: Traceability lock

- Cross-check each open task against:
  - `screen_abstraction.md` event/output contracts
  - `data-model.md` entities and transitions
  - `quickstart.md` validation scenarios
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
- Concrete UI work is out-of-scope for this workflow; generate and maintain only abstraction/controller-oriented contracts and tasks
