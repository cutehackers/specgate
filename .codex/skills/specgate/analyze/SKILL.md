---
name: analyze
description: Analyze consistency across `spec.md` and `tasks.md` with architecture and abstraction gates (SpecGate workflow)
---

You are the Codex SpecGate operator for the `analyze` workflow.
This skill is the canonical implementation for this workflow in Codex execution.
Run this workflow directly from this skill content without delegating to another command file.

## User Interaction (Codex)

- If any information is missing or ambiguous, stop and ask the user directly in the chat.
- Do not continue execution until the user provides the requested input.
- Prefer concise, single-purpose questions with explicit expected format.


## 0. Purpose

Run a non-destructive quality check before or during implementation.

## 1. Setup

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
2. Run `.specify/scripts/bash/check-spec-prerequisites.sh --feature-dir "<abs path>"`.
3. Run `.specify/scripts/bash/check-code-prerequisites.sh --feature-dir "<abs path>"`.
4. Load:
   - Required: `spec.md`, `tasks.md`
   - If present, also load each optional artifact and record only in findings:
     - `screen_abstraction.md`: validate screen/event coverage
     - `quickstart.md`: validate readiness scenarios
     - `test-spec.md`: validate test alignment
   - Missing optional artifacts are non-blocking and must be listed in `Non-blocking improvements`.

## 2. Analysis Focus

- Requirement coverage:
  - `spec.md` FR/US/AC are represented in `tasks.md#code-tasks`.
- Architecture compliance:
  - layer boundaries and dependency direction remain valid.
- Presentation abstraction compliance:
  - no concrete widget/layout/style/animation intent in code tasks.
- Test readiness:
- `test-spec.md` alignment for changed/high-risk paths (if `test-spec.md` is present; otherwise mark as missing context in findings).

## 3. Output Format

Provide a compact findings table:

| ID | Severity | Artifact | Issue | Recommended Fix |
|----|----------|----------|-------|-----------------|
| A1 | HIGH/MED/LOW | spec.md or tasks.md | [issue] | [action] |

Then add:

- `Blocking issues` (must fix before `/test-specify`)
- `Non-blocking improvements`
- `Next command`
