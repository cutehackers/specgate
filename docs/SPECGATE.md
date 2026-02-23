# SpecGate Guide

SpecGate is the Spec-driven Development (SDD) workflow used by Claude, OpenCode, and Codex.
It helps you move through one clear flow:

`/specify -> /clarify -> /codify -> /test-specify -> /test-codify`

This repository is the installation package only; after installation, work is done inside your project.

---

## 1. Quick installation check

Install into current directory:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude --prefix .
```

Verify files:

```bash
ls -la .specify .claude .codex .opencode
```

If install is affected by a partially broken previous install, run:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --clean --ai claude --prefix .
```

Then start using commands from your agent:

- `/feature-set`
- `/specify`
- `/clarify`
- `/codify`
- `/checklist`
- `/analyze`
- `/test-specify`
- `/test-codify`
- `/taskstoissues`
- `/constitution`
- `/feature-done`

For Codex, use workflow SKILLs in `.codex/skills/specgate/*/SKILL.md` directly.  
When a workflow needs user input, do not use `AskUserQuestion`; ask the user directly in chat and wait for their response.

---

## 2. What SpecGate manages

- `.specify` : workflow scripts and templates
- `.claude/commands/specgate/*`
- `.opencode/command/*`
- `.claude/hooks/statusline.js`
- `.codex/skills/specgate/*`
- workflow-specific Codex skills under `.codex/skills/specgate/*/SKILL.md`
- `docs/SPECGATE.md` (this file)

`specs/feature-stage.local.json` is not included in initial install.
It is created when you run `/feature-set`.

---

## 3. Install options (from install.sh)

```text
--prefix <path>     Install target directory (default: .)
--dry-run           Show plan only; no files are changed
--force             Overwrite existing target files/directories (no backup)
--update            Update only changed files in-place (no backup files)
--clean             Remove selected SpecGate assets and reinstall
--version <name>    Install from branch/tag (default: main)
--ai <list>         Install scope
--agent <list>      Alias for --ai
--codex-target <project|home>  Where to install Codex Agent Skills when --ai includes codex (default: project)
--uninstall         Remove SpecGate assets instead of installing
```

Notes:
- install, uninstall, clean, and update operations do not generate backup files.
- `--update` is idempotent for unchanged files: it skips files that have not changed.

Tips:

- `--clean` is the recommended reset mode for an interrupted or partial install.
- `--update` is the recommended mode for updating changed files without reinstalling.
- Empty directories in target locations are treated as empty install targets and are replaced automatically.

---

## 4. Standard workflow (first time)

1. Run `/feature-set <feature-folder-path>`
2. Run `/specify`
3. Run `/clarify`
4. Run `/codify`
5. Optionally run `/checklist` to validate requirement quality
6. Run `/test-specify`
7. Run `/test-codify`
8. Optionally run `/analyze` after `/test-codify` or before `/feature-done`
9. Optionally run `/taskstoissues` to sync implementation tasks to GitHub issues
10. Optionally run `/constitution` when governance rules change
11. Run `/feature-done`

### Where each command should end

- `spec.md` and checklist sections from `/specify` should be complete for that feature.
- `/clarify` must generate `data-model.md`, `screen_abstraction.md`, `quickstart.md`, and refresh `tasks.md`.
- `research.md` ownership is explicit:
  - `/specify` creates and owns the baseline ambiguity/dependency record.
  - `/clarify` may update `research.md` only when ambiguity resolution changes external assumptions or previously unresolved requirements.
  - `/codify` must treat `research.md` as read-only implementation input.
- `/codify` must implement all `tasks.md` P1 items and all `[P2][BLOCKING]` items.
- `/checklist` should close with a completed checklist artifact and noted non-blocking improvements.
- `/test-specify` creates a single test execution queue in `test-spec.md`.
- `/test-codify` should consume that queue.
- `/analyze` should output findings and next recommended command.
- `/taskstoissues` should map only actionable `tasks.md` tasks to issue requests.
- `/constitution` should keep templates and project policy aligned.
- `/feature-done` should end after cleanup and validation.

If a step fails:
- Run `/feature-set` again when you see `No SpecGate pointer found`.
- Re-run the failed command first, then continue.

---

## 5. Pointer file (state tracking)

SpecGate stores current flow state in:

`specs/feature-stage.local.json`

Example:

```json
{
  "feature_dir": "/path/to/feature",
  "stage": "specifying|clarifying|coding|test_planning|test_writing|done|blocked",
  "current_doc": "spec.md|tasks.md|test-spec.md",
  "progress": {
    "code": { "done": 0, "total": 8 },
    "test": { "done": 0, "total": 4 }
  }
}
```

Use the following when needed:

- `specgate-status.sh` : current status print
- `specgate-sync-pointer.sh --preserve-stage --feature-dir "<abs-path>"` : sync before/after stage changes
- `specgate-sync-pointer.sh --feature-dir "<abs-path>" --json` : current progress only

---

## 6. Quality gates (recommended)

Run in project root after commands (or before merging):

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> [--json] [--setup-code] [--strict-naming]

bash -n .specify/scripts/bash/check-code-prerequisites.sh \
  .specify/scripts/bash/check-implementation-readiness.sh \
  .specify/scripts/bash/check-implementation-quality.sh \
  .specify/scripts/bash/check-spec-prerequisites.sh \
  .specify/scripts/bash/check-test-prerequisites.sh \
  .specify/scripts/bash/check-test-coverage-targets.sh \
  .specify/scripts/bash/specgate-sync-pointer.sh \
  .specify/scripts/bash/specgate-status.sh \
  .specify/scripts/bash/setup-code.sh \
  .specify/scripts/bash/setup-test-spec.sh

./.specify/scripts/bash/specgate-status.sh
```

Tip: `specgate-smoke-check.sh` is kept as an installation validation script, not a daily routine.

`run-feature-workflow-sequence.sh` is the production-style day-to-day gate sequence:
`check-prerequisites --paths-only --json` → (optional `check-naming-policy --strict-naming --json`) → `check-spec-prerequisites --json` → `check-code-prerequisites --json` (and optionally `setup-code --json`).

`--strict-naming` enforces that `naming` conventions in architecture or constitution documents are defined in machine-readable JSON code blocks.

Tip: if your environment blocks some tools, use fallback options documented in the scripts.

## 7. Codex automation candidates (optional)

For Codex users, the most stable automation candidates are:

- `test-specify` (queue generation from accepted spec)
- `test-codify` (deterministic test run loop execution)

Both remain interactive-safe to run after plan/setup is stable, but the heavier requirement-rich workflows (`feature-set`, `specify`, `clarify`, `codify`, `feature-done`) should stay in SKILL execution because they include user decisions and branching.

Suggested automation cadence:
- `test-specify` weekly/hourly status refresh: run after upstream changes or when requirements are updated.
- `test-codify` as a recurring loop: run only when `test-spec.md` task queue is ready and no blocking changes are pending.

---

## 8. Common mistakes (for beginners)

- Do not use legacy command surfaces (`velospec`, `plan`, `tasks`, `tasks-test`) in this environment.
- Do not put concrete Flutter widget or animation instructions into `tasks.md`/`test-spec.md`.
- Do not write `clarify.md` after `/feature-done`.
- If reinstalling into an existing project, use `--clean` (or `--force` for overwrite without backup).

---

## 9. Uninstall

If needed:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --prefix .
```

To remove one agent only:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --ai claude --prefix .
```

`statusline.js` is only removed when it is identified as a SpecGate-owned file to avoid deleting custom statusline scripts from other tools.
`--update` also only updates `statusline.js` when it is a SpecGate-owned file.
