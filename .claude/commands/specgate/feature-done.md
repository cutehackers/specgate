---
description: Mark the current feature as done and optionally switch to a new current feature.
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

1. **Load pointer file**:
   - Set pointer path for this worktree:
     - `POINTER_PATH=specs/feature-stage.local.json`
   - Read `POINTER_PATH` from repo root.
   - If missing/invalid or `feature_dir` is empty, ask the user for the absolute `feature_dir` to mark as done.
   - Before finalizing, run `.specify/scripts/bash/specgate-sync-pointer.sh --feature-dir "<abs path>" --preserve-stage --json` to capture latest counters.

2. **Mark done**:
   - Run:
     ```bash
     .specify/scripts/bash/specgate-sync-pointer.sh \
       --feature-dir "<abs path>" \
       --status done \
       --stage done \
       --current-doc "" \
       --json
     ```

3. **Offer to switch to a new feature**:
   - Use `AskUserQuestion`: "Set a new current feature now?"
   - If yes, follow the `/feature-set` flow to choose a new `feature_dir` and update the pointer file to `status: "in_progress"`.
   - If no, stop after marking done.

4. **Apply feature-doc cleanup policy**:
   - Preserve mandatory maintenance docs:
     - `spec.md`, `code.md`, `screen_abstraction.md`, `quickstart.md`, `checklists/*`
   - Default removal targets (no extra prompt required):
     - `clarify.md` if all accepted decisions are already mirrored in `spec.md#Clarifications`
     - `research.md` if no kept document references it (`spec.md`, `code.md`, `quickstart.md`, `data-model.md`, `test-spec.md`)
     - temporary notes under `docs/` matching `analysis*.md`, `tmp*.md`, `notes*.md`
   - Always keep unless the user explicitly requests deletion:
     - `data-model.md`, `contracts/`, `test-spec.md`
   - Completion report must include two explicit lists:
     - `removed`: file path + short reason
     - `kept`: file path + short reason

5. **Report**: Confirm status change and, if switched, the new `feature_dir`.
