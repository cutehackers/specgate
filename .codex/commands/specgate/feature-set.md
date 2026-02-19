---
description: Set or change the current feature pointer used by the command workflow. (SpecGate workflow)
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
model: haiku
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

1. **Resolve feature directory**:
   - If `--feature-dir` is provided:
     - If absolute: use it.
     - If relative: search by **basename only** and present choices with `AskUserQuestion`.

       ```bash
       REL_PATH="<provided>"
       REPO_ROOT="$(pwd)"
       BASENAME="$(basename "$REL_PATH")"
       CANDIDATES_ALL=$(find "$REPO_ROOT" -type d -name "$BASENAME" 2>/dev/null | sort -u)
       COUNT=$(printf "%s" "$CANDIDATES_ALL" | sed '/^$/d' | wc -l | tr -d ' ')
       CANDIDATES=$(printf "%s" "$CANDIDATES_ALL" | head -10)
       ```

       - If `COUNT` > 10, show only the first 10 and label the list as `10+` (e.g., "Showing 10 of $COUNT (10+)").

   - If `--feature-dir` is missing:
     - Search the repo for existing feature specs and propose candidates:
       ```bash
       REPO_ROOT="$(pwd)"
       CANDIDATES=$(find "$REPO_ROOT" -type f -path "*/docs/spec.md" 2>/dev/null | sed 's|/docs/spec.md$||' | sort -u | head -10)
       ```
     - If no candidates are found, ask the user for an absolute path.
   - Always end with an absolute path.

2. **Sync pointer state** (worktree-local file):
   - Run from repo root:
     ```bash
     .specify/scripts/bash/specgate-sync-pointer.sh \
       --feature-dir "<abs path>" \
       --status in_progress \
       --stage specifying \
       --current-doc spec.md \
       --json
     ```
   - Pointer path is `specs/feature-stage.local.json`.
   - `feature_id` is auto-resolved from `docs/spec.md` when available.

3. **Report**: Confirm the selected `feature_dir`, pointer file path, and suggest running `/specify` next.
