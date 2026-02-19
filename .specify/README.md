# SpecGate Engine (.specify)

`.specify` contains the shared workflow engine used by Claude, Codex, and
OpenCode for `SpecGate`.

## Key Directories

- `templates/`: canonical artifact templates (`spec.md`, `code.md`,
  `test-spec.md`, checklists)
- `scripts/bash/`: stage checks, setup scripts, and status commands
- `memory/`: constitution and workflow policy

## Core Scripts

- `scripts/bash/check-spec-prerequisites.sh`
- `scripts/bash/check-code-prerequisites.sh`
- `scripts/bash/check-implementation-readiness.sh`
- `scripts/bash/check-implementation-quality.sh`
- `scripts/bash/check-test-prerequisites.sh`
- `scripts/bash/check-test-coverage-targets.sh`
- `scripts/bash/setup-code.sh`
- `scripts/bash/setup-test-spec.sh`
- `scripts/bash/specgate-sync-pointer.sh`
- `scripts/bash/specgate-status.sh`
- `scripts/bash/specgate-smoke-check.sh`

## Environment Notes

- `check-implementation-readiness.sh` validates implementation queue readiness (`code.md#code-tasks`)
  and emits blocking-task diagnostics for `/code` → `/test-spec` transitions.
- `check-implementation-quality.sh` runs `dart format`, `flutter analyze`, and
  `flutter test`. If Flutter cache path is not writable
  (`.../bin/cache/engine.stamp`), add `--allow-tool-fallback` to continue
  with a degraded-quality warning and rerun in a writable environment.

## Core Templates

- `templates/spec-template.md`
- `templates/clarify-template.md` (`clarify.md`, temporary)
- `templates/code-template.md`
- `templates/test-spec-template.md` (`test-spec.md`)
- `templates/screen-abstraction-template.md`

## Contract

- Workflow: `spec.md -> clarify(optional) -> code.md -> test-spec.md`
- FSM pointer: `specs/feature-stage.local.json`
- Pointer auto-sync: `scripts/bash/specgate-sync-pointer.sh`
- Pre-step sync rule: use `--preserve-stage` to avoid phase drift while refreshing counters.
- Architecture baseline: `docs/ARCHITECTURE.md`
- Branding and policy guide: `docs/SPECGATE.md`

## Operational docs

- Quick operational guide: `docs/SPECGATE.md`
- Externalization/packaging plan: `docs/SPECGATE-EXTERNALIZATION-PLAN.md`
