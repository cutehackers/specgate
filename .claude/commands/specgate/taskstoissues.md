---
description: Convert existing tasks into actionable, dependency-ordered GitHub issues for the feature based on available design artifacts.
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
tools: ['github/github-mcp-server/issue_write']
---



## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

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
   - Then run `.specify/scripts/bash/check-prerequisites.sh --json --paths-only --feature-dir "<abs path>"` from repo root and parse FEATURE_DIR and FEATURE_DOCS_DIR. All paths must be absolute.
   - Validate that `<feature_dir>/docs/tasks.md` exists before proceeding:
     - If not found, fail with:
       - `ERROR: tasks.md required for /taskstoissues`
       - `Run /codify first to create implementation tasks before creating issues.`
     - For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").
   - After successful completion, run:
     ```bash
     .specify/scripts/bash/specgate-sync-pointer.sh \
       --feature-dir "<abs path>" \
       --preserve-stage \
       --json
     ```
     - Refresh counters only. Do not transition stage in this supporting command.
   1. Read `<feature_dir>/docs/tasks.md` and use `## code-tasks` as the
      single issue source.
      - Issue creation targets unchecked actionable items only.
      - Ignore `OBSOLETE:` items.
      - Priority tags in `tasks.md` are informative only here; this command never
        changes `/codify` readiness or phase gates.
   1. Get the Git remote by running:

   ```bash
   git config --get remote.origin.url
   ```

   > [!CAUTION]
   > ONLY PROCEED TO NEXT STEPS IF THE REMOTE IS A GITHUB URL

   1. For each selected `code-tasks` item, use the GitHub MCP server to create
      a new issue in the repository that is representative of the Git remote.

   > [!CAUTION]
   > UNDER NO CIRCUMSTANCES EVER CREATE ISSUES IN REPOSITORIES THAT DO NOT MATCH THE REMOTE URL

## Execution Contract

Task source:

- Parse `tasks.md` `## code-tasks` and target only unchecked tasks with task id prefix `C###`.
- Keep the existing `P1/P2/P3` and `[P2][BLOCKING]` metadata:
  - `P1`: required baseline implementation tasks.
  - `P2-BLOCKING`: release-quality blockers; they block `/codify -> /test-specify` transitions in the workflow.
  - Other `P2`: non-blocking quality tasks, optional for immediate test/spec planning.
  - `P3`: optional polish/improvement tasks.
- This command only maps metadata into issues for human planning/triage. It does **not** enforce
  `/codify` completion rules or modify workflow transitions.
- Skip tasks marked `OBSOLETE:` or duplicated by id/title in this run.

Issue creation rules:

- On each create attempt, handle failures explicitly:
  - MCP failure for one item increments `FAILED`.
  - Keep processed issue URLs in a short list.
  - Never retry silently in a tight loop; if at least 2 consecutive failures occur, stop and prompt the user with a resumable context.

Output format contract:

- `REMOTE_REPO`: validated GitHub remote URL
- `TOTAL_SELECTED`: number of candidate tasks
- `CREATED`: number of issues successfully created
- `FAILED`: number of failed issue creations
- `CREATED_ISSUES`: map of task-id to issue URL; return `{}` when none are created
- `FAILED_ITEMS`: list with `{id, reason}` objects; return `[]` when none fail

Failure condition:

- If `FAILED > 0`, report failure summary and do not claim workflow success.
