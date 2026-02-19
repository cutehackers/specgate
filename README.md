# SpecGate

Standalone SpecGate workflow repository.

This repository contains only the shared SpecGate command surface, templates,
and scripts used by
Claude / OpenCode / Codex for SDD phase flow.

- `spec.md -> clarify.md(optional) -> code.md -> test-spec.md`
- Pointer FSM is stored in `specs/feature-stage.local.json`.
  The file is generated when starting a feature flow and is not part of the initial install payload.
- Flat invocation style (`/feature-set`, `/specify`, `/clarify`, `/code`, `/test-spec`, `/test-write`, `/feature-done`)

## Installation in a consumer project

Install directly from the repository without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh | bash -s -- --prefix .
```

Pin to a branch/tag by adding `--version`:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --version v0.0.0 --prefix .
```

Or install from a local clone:

From the project root that will use SpecGate:

```bash
# one-shot install into repo root (keeps engine under .specify/.claude/.opencode/.codex)
/path/to/specgate/install.sh --prefix .

# optional: keep command artifacts in a dedicated folder
/path/to/specgate/install.sh --prefix .specify
```

The installer creates/overwrites:

- `.specify/*`
- `.claude/commands/specgate/*`
- `.opencode/command/*`
- `.codex/commands/specgate/*`
- `.claude/hooks/statusline.js`

### Install options

- `--dry-run`: show planned file operations without changing files
- `--force`: overwrite existing target files (default keeps existing files and skips)
- `--version`: branch or tag for remote bootstrap (default: `main`)

## Required smoke checks

Before release/update, run from repository root:

```bash
bash -n .specify/scripts/bash/check-code-prerequisites.sh \
  .specify/scripts/bash/check-implementation-readiness.sh \
  .specify/scripts/bash/check-implementation-quality.sh \
  .specify/scripts/bash/check-spec-prerequisites.sh \
  .specify/scripts/bash/check-test-prerequisites.sh \
  .specify/scripts/bash/check-test-coverage-targets.sh \
  .specify/scripts/bash/specgate-sync-pointer.sh \
  .specify/scripts/bash/specgate-status.sh \
  .specify/scripts/bash/specgate-smoke-check.sh \
  .specify/scripts/bash/setup-code.sh \
  .specify/scripts/bash/setup-test-spec.sh

./.specify/scripts/bash/specgate-smoke-check.sh
```

- `docs/SPECGATE.md` contains full operational guidance.
