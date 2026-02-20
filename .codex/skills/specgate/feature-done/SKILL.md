---
name: feature-done
description: Mark the current feature as done and optionally switch to a new current feature. (SpecGate workflow)
---

You are the Codex SpecGate operator for the `feature-done` workflow.
This skill is the canonical implementation for this workflow in Codex execution.
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

1. **Load pointer file**:
   - Set pointer path for this worktree:
     - `POINTER_PATH=specs/feature-stage.local.json`
   - Read `POINTER_PATH` from repo root.
   - If missing/invalid or `feature_dir` is empty, ask the user in chat for the absolute `feature_dir` to mark as done.
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
   - Ask the user in chat: "Set a new current feature now?"
   - If yes, follow the `/feature-set` flow to choose a new `feature_dir` and update the pointer file to `status: "in_progress"`.
   - If no, stop after marking done.

4. **Apply feature-doc cleanup policy**:
   - Preserve mandatory maintenance docs:
     - `spec.md`, `tasks.md`, `screen_abstraction.md`, `quickstart.md`, `checklists/*`
   - Default removal targets (no extra prompt required):
     - `clarify.md` if all accepted decisions are already mirrored in `spec.md#Clarifications`
     - `research.md` if no kept document references it (`spec.md`, `tasks.md`, `quickstart.md`, `data-model.md`, `test-spec.md`)
     - temporary notes under `docs/` matching `analysis*.md`, `tmp*.md`, `notes*.md`
   - Always keep unless the user explicitly requests deletion:
     - `data-model.md`, `contracts/`, `test-spec.md`
   - Completion report must include two explicit lists:
     - `removed`: file path + short reason
     - `kept`: file path + short reason

5. **Report**: Confirm status change and, if switched, the new `feature_dir`.
