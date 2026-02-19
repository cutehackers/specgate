---
description: Execute the implementation code-spec workflow using the code template to generate design artifacts. (SpecGate workflow)
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

`/code` is the authoritative workflow for planning artifacts.
Default execution flow: `/specify` -> `/clarify` -> `/code` -> `/test-spec`.

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
     to refresh pointer progress before generating artifacts.
   - Then run `.specify/scripts/bash/setup-code.sh --json --feature-dir "<abs path>"` from repo root and parse JSON for FEATURE_SPEC, CODE_DOC, FEATURE_DIR, FEATURE_DOCS_DIR. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").
   - After successful completion, sync pointer:
     ```bash
     .specify/scripts/bash/specgate-sync-pointer.sh \
       --feature-dir "<abs path>" \
       --status in_progress \
       --stage coding \
       --current-doc code.md \
       --json
     ```
     - `feature_id` and `progress` are synchronized automatically from feature docs.

2. **Run spec gate**: Execute `.specify/scripts/bash/check-spec-prerequisites.sh --feature-dir "<abs path>"` and stop on failure.

3. **Load context**: Read FEATURE_SPEC and `.specify/memory/constitution.md`. If `<feature_dir>/docs/clarify.md` exists, include it as supporting context (source of clarification history). Load CODE_DOC template (already copied).

3.1 **Spec section gate (required before planning)**:
   - Validate `FEATURE_SPEC` includes all required sections:
     - `## Metadata`
     - `## Problem Statement & Scope`
     - `## User Scenarios`
     - `## Acceptance Matrix`
     - `## Functional Requirements`
     - `## Domain Model`
     - `## Edge Cases`
     - `## Architecture Compliance`
     - `## Success Criteria`
     - `## Clarifications`
   - If any required section is missing or empty:
     - **STOP** and report missing section names.
     - Instruct user to run `/specify` or `/clarify` to fix spec completeness before `/code`.

3. **Execute code workflow**: Follow the structure in CODE_DOC template to:
   - Fill Technical Context (mark unknowns as "NEEDS CLARIFICATION")
   - Fill Constitution Check section from constitution
   - Evaluate gates (ERROR if violations unjustified)
   - Phase 0: Generate research.md (resolve all NEEDS CLARIFICATION + define screen abstraction principles)
   - Phase 1A: Generate screen_abstraction.md as the source-of-truth screen contract artifact
   - Phase 1B: Generate data-model.md, contracts/, quickstart.md where quickstart is validation-only and references screen contracts
   - Phase 1C: Define parallel development plan from contracts and document mock-server workflow in `code.md`
   - Phase 1C: Update agent context by running the agent script
   - Phase 2: Generate `code.md#code-tasks` with checklist-style IDs, story-mapped dependency order, and execution checkpoints
   - Re-evaluate Constitution Check post-design

4. **Run code gate**: Execute `.specify/scripts/bash/check-code-prerequisites.sh --feature-dir "<abs path>"` and stop on failure.

5. **Stop and report**: Command ends after Phase 2 code-task planning. Report feature directory, CODE_DOC path, generated artifacts, and set pointer stage to `coding` (`current_doc: code.md`).

## Phases

### Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]
   - Screen Abstraction Impact: [how this decision affects screen contracts]

**Output**: research.md with all NEEDS CLARIFICATION resolved and abstraction decisions documented

### Phase 1A: Screen Abstraction

**Prerequisites:** `research.md` complete

1. **Extract screens from feature spec and user stories**:
   - Define screen boundaries by user intent, not widget structure
   - Map each screen to one or more user stories (P1/P2/P3)

2. **Generate `screen_abstraction.md`** with one section per screen:
   - `screen`: Stable screen identifier
   - `purpose`: User intent and success condition
   - `input`: Data dependencies and inbound navigation context
   - `output`: Domain-facing outcomes and outbound navigation effects
   - `ui_state`: Required state modes (loading/empty/success/error/disabled if needed)
   - `event`: User/system events mapped to domain actions
   - `error_state`: Error condition, user-visible message strategy, recovery action
   - `dependencies`: Providers/use cases/repositories referenced by contract
   - Use `.specify/templates/screen-abstraction-template.md` as canonical structure when available

3. **Validate abstraction coverage**:
   - Every P1/P2 user story MUST map to at least one screen section
   - Every `event` MUST map to a domain action/use case
   - ERROR if any required schema field is missing

4. **Abstraction guardrails**:
   - Do NOT include widget tree, pixel values, component names, layout positions, style tokens, or animation timings
   - Keep this document implementation-agnostic so users can implement concrete screens manually

**Output**: screen_abstraction.md

### Phase 1B: Design & Contracts

**Prerequisites:** `research.md` and `screen_abstraction.md` complete

1. **Extract entities from feature spec and screen abstraction outputs** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Generate API contracts** from functional requirements + screen events:
   - For each abstraction event/output pair → endpoint or domain contract
   - Use standard REST/GraphQL patterns
   - Output OpenAPI/GraphQL schema to `/contracts/`

3. **Generate quickstart validation scenarios** in `quickstart.md`:
   - Treat quickstart as a validation playbook, not a second abstraction spec
   - Use `.specify/templates/quickstart-template.md` as canonical structure when available
   - Reference screen contracts by `screen` identifier from `screen_abstraction.md` (do not restate full schema fields)
   - Validate each path using `input -> event -> expected ui_state/output`
   - Include error and recovery checks derived from `error_state`
   - Include cross-artifact checks for data-model and contracts when relevant
   - Avoid concrete UI implementation steps

4. **Agent context update**:
   - Run `.specify/scripts/bash/update-agent-context.sh --feature-dir "<abs path>" claude`
   - These scripts detect which AI agent is in use
   - Update the appropriate agent-specific context file
   - Add only new technology from current plan
   - Preserve manual additions between markers

**Output**: data-model.md, /contracts/*, quickstart.md, agent-specific file

### Phase 1C: Parallel Development & Mock Strategy

**Prerequisites:** `contracts/` decision completed in Phase 1B

1. **Set strategy in `code.md` section `## Parallel Development & Mock Strategy`**:
   - Declare whether contracts are present (`YES` or `NO`)
   - If contracts are present, define a concrete mock-server approach and startup command
   - List contract coverage scope (which endpoints/events are mocked)
   - Define client validation path against mock before backend integration

2. **Task enforcement in `code.md#code-tasks`**:
   - If contracts are present, include at least one mock/contract task in execution queue
   - Link the task to the relevant story or integration scope

**Output**: `code.md` mock strategy section and queued mock task(s) when contracts exist

### Phase 2: Code Task Breakdown

**Prerequisites:** `research.md`, `screen_abstraction.md`, `data-model.md` (if applicable), and `quickstart.md` complete

1. **Prepare baseline**:
   - Read `code.md`, `FEATURE_SPEC` (`spec.md`), and all artifacts generated in Phase 0/1A/1B
   - Include `contracts/` and other optional artifacts if present

### Priority policy (P1/P2/P3)

- `P1`: Must-have for baseline acceptance. Required before `/code` can transition to `/test-spec`.
  - `P2`: Required for release quality and major flow coverage.
  - `P2-BLOCKING` tasks must be completed to move from `/code` to `/test-spec`.
  - Non-blocking `P2` can remain pending when capacity/risk trade-off requires.
- `P3`: Optional polish/improvement tasks. Track only when capacity allows or explicitly requested by the user.
- `P2-BLOCKING` tag is required for blocking `P2` tasks.
- Implementation completion condition: all applicable `P1` tasks and all `P2-BLOCKING` tasks must be completed.
- `P3` can remain pending without blocking phase transitions.

2. **Generate `code.md`**:
   - Use `.specify/templates/code-template.md` as the task-output template
   - Build in `Phase 1: Setup`, `Phase 2: Foundational`, `Phase 3+: User Story` (P1/P2/P3), and `Final Polish`
   - Every task must use strict format:
     - `- [ ] [TaskID] [P1|P2|P3] [Story?|Domain?] [NEW|UPDATE|VERIFY] [path or action]`
     - For blocking P2 use `[P2][BLOCKING]`.
   - Include at least one `[Validation]` task that runs:
     - `.specify/scripts/bash/check-implementation-quality.sh --feature-dir "<abs path>" --json`
   - Use exact file paths and reference screen identifiers from `screen_abstraction.md`
   - UI/screen tasks are contract-only by policy:
     - Allowed focus: `input`, `event`, `ui_state`, `output`, `error_state`
     - Forbidden focus: concrete layout/style/animation/visual implementation details
   - Existing `code.md` handling:
     - If `code.md` does not exist: create it.
     - If `code.md` exists: update it in place (do not blindly overwrite).
     - Preserve completed tasks (`- [X]`) and their Task IDs whenever still valid.
     - Add new tasks with next available Task ID.
     - If an old pending task is no longer valid, keep checklist format and set the description prefix to `OBSOLETE:` with a short reason.
     - Only regenerate from scratch when structure is corrupted or unusable, and report that explicitly.
     - If a pending screen task contains concrete UI instructions, rewrite it to abstraction wording when possible; otherwise mark it `OBSOLETE: concrete UI detail disallowed by workflow policy`.

3. **Dependency and consistency validation**:
   - Confirm each P1/P2 story has at least one mapped screen-abstraction task
   - Confirm each task has explicit dependencies and execution order (or `[P]` where parallelizable)
   - Validate that all tasks with `[Story]` labels map to requirements from `spec.md`
   - Verify quickstart checks become independent validation tasks where possible

4. **Finalize `code.md` and mark as implementation-ready**:
   - Confirm task format is consistent across all phases
   - Confirm file paths are repository-relative and valid for the selected project structure
   - Confirm no concrete visual/layout instructions are embedded in task descriptions
   - If `screen_abstraction.md` exists, run lexical validation on screen-related task lines and detect concrete UI terms such as:
     - `layout`, `pixel`, `padding`, `margin`, `spacing`, `typography`, `font`, `color`, `theme`, `style`, `animation`, `motion`, `visual`, `shadow`, `gradient`, `radius`, `border`, `position`
   - For each violation:
     - Prefer rewrite to abstraction-only wording before finalizing `code.md`
     - If ambiguous, mark pending task `OBSOLETE: concrete UI detail disallowed by workflow policy` and add/keep an abstraction replacement task
   - Never finalize `code.md` with unresolved concrete UI task wording
   - Confirm task status continuity is preserved for in-progress execution (`[X]`/`[ ]`)

**Output**: code.md

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications
- `screen_abstraction.md` is required output for `/code`
- `screen_abstraction.md` defines WHAT each screen contract guarantees
- `quickstart.md` defines HOW to validate those contracts end-to-end
- `quickstart.md` must reference screen IDs and must not duplicate full abstraction schema blocks
- `research.md` and `quickstart.md` must reflect screen abstraction decisions and validation paths
- Screen artifacts must stay abstract (no concrete visual implementation details)
- When `contracts/` exists, `code.md` must include a concrete mock startup command and at least one mock/contract task for parallel client development
- Concrete UI work is out-of-scope for this workflow; generate and maintain only abstraction/controller-oriented contracts and tasks
