# SpecGate Guide

SpecGate is the Spec-driven Development (SDD) workflow used by Claude, OpenCode, and Codex.
It helps you move through one clear flow:

`spec.md -> clarify.md(optional) -> code.md -> test-spec.md -> test-write -> feature-done`

This repository is the installation package only; after installation, work is done inside your project.

---

## 1. Quick installation check

Install into current directory:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --prefix .
```

Verify files:

```bash
ls -la .specify .claude .codex .opencode
```

Then start using commands from your agent:

- `/feature-set`
- `/specify`
- `/clarify` (optional)
- `/code`
- `/test-spec`
- `/test-write`
- `/feature-done`

---

## 2. What SpecGate manages

- `.specify` : workflow scripts and templates
- `.claude/commands/specgate/*`
- `.opencode/command/*`
- `.codex/commands/specgate/*`
- `.claude/hooks/statusline.js`
- `docs/SPECGATE.md` (this file)

`specs/feature-stage.local.json` is not included in initial install.
It is created when you run `/feature-set`.

---

## 3. Standard workflow (first time)

1. Run `/feature-set <feature-folder-path>`
2. Run `/specify`
3. Run `/clarify` (if needed)
4. Run `/code`
5. Run `/test-spec`
6. Run `/test-write`
7. Run `/feature-done`

### Where each command should end

- `spec.md` and checklist sections from `/specify` should be complete for that feature.
- `/code` must include P1 items and all `[P2][BLOCKING]` items.
- `/test-spec` creates a single test execution queue in `test-spec.md`.
- `/test-write` should consume that queue.
- `/feature-done` should end after cleanup and validation.

If a step fails:
- Run `/feature-set` again when you see `No SpecGate pointer found`.
- Re-run the failed command first, then continue.

---

## 4. Pointer file (state tracking)

SpecGate stores current flow state in:

`specs/feature-stage.local.json`

Example:

```json
{
  "feature_dir": "/path/to/feature",
  "stage": "specifying|clarifying|coding|test_planning|test_writing|done|blocked",
  "current_doc": "spec.md|code.md|test-spec.md",
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

## 5. Quality gates (recommended)

Run in project root after commands (or before merging):

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

Tip: if your environment blocks some tools, use fallback options documented in the scripts.

---

## 6. Common mistakes (for beginners)

- Do not use legacy command surfaces (`velospec`, `plan`, `tasks`, `tasks-test`) in this environment.
- Do not put concrete Flutter widget or animation instructions into `code.md`/`test-spec.md`.
- Do not write `clarify.md` after `/feature-done`.
- If reinstalling into an existing project, use `--force` or remove target files first.

---

## 7. Uninstall

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
