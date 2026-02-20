# SpecGate

SpecGate is a lightweight workflow pack for Spec-driven Development (SDD).
It provides command surfaces and scripts for Claude, OpenCode, and Codex.

Install directly into your project without cloning.

- Default install path: current directory (`.`)
- Default scope: all agents (`claude`, `codex`, `opencode`)
- Entry points:
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

## 1) Quick start

Install SpecGate:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --prefix .
```

Verify:

```bash
ls -la .specify .claude .codex .opencode
```

You should see the folders for your selected agents.
For Codex, run workflows via `.codex/skills/specgate/<workflow>/SKILL.md` directly.  
If a workflow needs additional input, ask it directly in the Codex chat (do not rely on `AskUserQuestion`).

## 2) Install modes

### Remote install (all agents, default)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --prefix .
```

### Install selected agents

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude --prefix .
```

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
# Install Codex skill under project: .codex/skills/specgate
bash /tmp/specgate-install.sh --ai codex --codex-target project --prefix .
```

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
# Install Codex skill under Codex home: ~/.codex/skills/specgate
bash /tmp/specgate-install.sh --ai codex --codex-target home --prefix .
```

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode --prefix .
```

`--ai` and `--agent` are aliases.
Supported values: `all`, `claude`, `codex`, `opencode`.

### Install from local clone

```bash
/path/to/specgate/install.sh --prefix .
```

## 3) Install options

```text
--prefix <path>     Install target directory (default: .)
--dry-run           Show plan only; no files are changed
--force             Overwrite existing target files/directories
--version <name>    Install from branch/tag (default: main)
--ai <list>         Install scope
--agent <list>      Alias for --ai
--codex-target <project|home>  Where to install Codex Agent Skills when --ai includes codex (default: project)
--uninstall         Remove SpecGate assets instead of installing
```

### Examples

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --dry-run --ai codex --codex-target project --prefix .
```

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --version v0.0.0 --prefix .
```

## 4) Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --prefix .
```

Remove only one agent:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --ai claude --prefix .
```

## 5) Installed assets

- `.specify/*`
- `.claude/commands/specgate/*`
- `.claude/hooks/statusline.js`
- `.codex/skills/specgate/*` (project install: `.codex/skills/specgate`, or home install: `~/.codex/skills/specgate`)
  - Includes workflow-dedicated skills: `feature-set`, `specify`, `clarify`, `codify`, `checklist`, `analyze`, `test-specify`, `test-codify`, `taskstoissues`, `constitution`, `feature-done`
- `.opencode/command/*`
- `docs/SPECGATE.md`

Note: `.specify` and `docs/SPECGATE.md` are always installed together for single-agent installs (`--ai codex`, `--ai claude`, etc.).

## 6) Recommended checks (instead of daily smoke check)

Run from repository root:

```bash
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

`specgate-smoke-check.sh` remains available as an installation validation script, but is not recommended as a routine daily check.

For detailed operation guidance, see `docs/SPECGATE.md`.

## Korean version

- [README-ko.md](./README-ko.md)
