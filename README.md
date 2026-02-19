# SpecGate Engine

Standalone SpecGate workflow engine repository.

This repository contains only the shared SpecGate command surface, templates,
and scripts used by
Claude / OpenCode / Codex for SDD phase flow.

- `spec.md -> clarify.md(optional) -> code.md -> test-spec.md`
- Pointer FSM in `specs/feature-stage.local.json`
- Flat invocation style (`/feature-set`, `/specify`, `/clarify`, `/code`, `/test-spec`, `/test-write`, `/feature-done`)

## Installation in a consumer project

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

## Upgrade a consumer install

From inside this repo:

```bash
/path/to/specgate/sync.sh --check
/path/to/specgate/sync.sh --apply
```

You can pass `--install-prefix <path>` with `--apply` to automatically run installer
into a consumer directory after the engine has been updated.

```bash
/path/to/specgate/sync.sh --apply --install-prefix /abs/path/to/consumer
```

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
