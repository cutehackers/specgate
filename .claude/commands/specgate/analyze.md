---
description: Analyze consistency across `spec.md` and `tasks.md` with architecture and abstraction gates (SpecGate workflow)
allowed-tools:
  - Read
  - Bash
  - AskUserQuestion
---

## 0. Purpose

Run a non-destructive quality check before or during implementation.

## 1. Setup

1. Resolve feature directory from `specs/feature-stage.local.json`.
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
