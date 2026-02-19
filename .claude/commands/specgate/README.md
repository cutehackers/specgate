# SpecGate Commands (Claude)

This directory is the canonical Claude command surface for `SpecGate`.

## Primary Flow

1. `feature-set`
2. `specify`
3. `clarify` (optional)
4. `code`
5. `test-spec`
6. `test-write`
7. `feature-done`

## Supporting Commands

- `analyze`
- `checklist`
- `constitution`
- `taskstoissues`

## Operational Rules

- Command invocation style is flat: `/feature-set`, `/specify`, `/clarify`, `/code`, ...
- Keep implementation queue and progress in `code.md`.
- Keep test queue and progress in `test-spec.md`.
- Use `specs/feature-stage.local.json` as the FSM source of truth.
- Update pointer through `.specify/scripts/bash/specgate-sync-pointer.sh` at each phase boundary.
- `checklist` and `taskstoissues` are optional support commands only; they do not
  affect `/code` completion rules (`P1/P2-BLOCKING`) or phase transitions.
- For pre-step refresh, use `--preserve-stage` to avoid phase drift.
- Follow architecture gates and abstraction-only presentation policy.
- Run `.specify/scripts/bash/check-implementation-quality.sh` before closing `/code` phase tasks.
- Run `.specify/scripts/bash/check-test-coverage-targets.sh` after coverage generation in `/test-write`.

## Reference

- Workflow guide: `docs/SPECGATE.md`
- Shared scripts: `.specify/scripts/bash/`
- Shared templates: `.specify/templates/`
- Smoke check: `.specify/scripts/bash/specgate-smoke-check.sh`
