# SpecGate

SpecGate is a lightweight workflow pack for Spec-driven Development (SDD).
It provides command surfaces and scripts for Claude, OpenCode, and Codex.

Install directly into your project without cloning.

- Default install path: current directory (`.`)
- Default scope: all agents (`all` by default). Single-agent install is recommended below.
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

## Standard feature pipeline

- `/specify -> /clarify -> /codify -> /test-specify -> /test-codify`
- `/specify` must produce `spec.md`, `research.md`.
- `/clarify` must produce and maintain all of: `data-model.md`, `screen_abstraction.md`, `quickstart.md`, `tasks.md`.
- `/codify` must only implement code from the `/clarify` artifacts and `tasks.md`.
- `/test-specify` then `/test-codify` consume `test-spec.md` artifacts.
- `specs/feature-stage.local.json` is the local run-time pointer.
  - It is created in consumer projects by `/feature-set`.
  - It is intentionally excluded from this package distribution.

## 1) Quick start

Install SpecGate:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --preset claude --prefix .
```

Verify:

```bash
ls -la .specify .claude
```

You should see the folders for your selected agent.
For Codex, run workflows via `.codex/skills/specgate/<workflow>/SKILL.md` directly.  
If a workflow needs additional input, ask it directly in the Codex chat (do not rely on `AskUserQuestion`).

## 2) Agent-by-agent lifecycle (Install → Update → Remove)

Pick one agent type first, then run one command per phase.

### Claude

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --preset claude --prefix .

bash /tmp/specgate-install.sh --update --preset claude --prefix .

bash /tmp/specgate-install.sh --uninstall --preset claude --prefix .
```

### Opencode

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --preset opencode --prefix .

bash /tmp/specgate-install.sh --update --preset opencode --prefix .

bash /tmp/specgate-install.sh --uninstall --preset opencode --prefix .
```

### Codex (project scope)

`--preset codex` is project scope by default.

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --preset codex --prefix .

bash /tmp/specgate-install.sh --update --preset codex --prefix .

bash /tmp/specgate-install.sh --uninstall --preset codex --prefix .
```

### Codex (home scope)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --preset codex-home --prefix .

bash /tmp/specgate-install.sh --update --preset codex-home --prefix .

bash /tmp/specgate-install.sh --uninstall --preset codex-home --prefix .
```

## 3) Install modes

### Remote install (single agent)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --preset claude --prefix .
```

### Combined install (multiple agents)

Use one command when you want to install several agents together.

Install Claude + Opencode in one run:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode --prefix .
```

Install Claude + Opencode + Codex (project scope):

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode,codex --prefix .
```

Install Claude + Opencode + Codex (home scope):

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode,codex --codex-target home --prefix .
```

Install all agents (equivalent to `all`):

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai all --prefix .
```

Update or remove the same set by adding `--update`/`--uninstall`:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --update --ai claude,opencode --prefix .
bash /tmp/specgate-install.sh --uninstall --ai claude,opencode --prefix .
```

### Installation mapping guide

- Claude: install target becomes `.claude/commands/specgate/*`.
- Opencode: install target becomes `.opencode/command/*`.
- Codex + `--codex-target project`: `.codex/skills/specgate/*` (project scope).
- Codex + `--codex-target home`: `~/.codex/skills/specgate/*` (shared by projects).
- `--ai claude,opencode` installs both Claude and Opencode targets together.
- `--ai claude,opencode,codex` installs the union of all selected targets.

`--ai` and `--agent` are aliases.
Supported values: `all`, `claude`, `codex`, `opencode`.
(`--ai all` installs all known agent assets.)

### Install from local clone

```bash
/path/to/specgate/install.sh --preset claude --prefix .
```

## 4) Install options

```text
--prefix <path>     Install target directory (default: .)
--dry-run           Show plan only; no files are changed
--force             Overwrite existing target files/directories (no backup)
--update            Update only changed files in-place (no backup)
--clean             Remove selected SpecGate assets and reinstall
--version <name>    Install from branch/tag (default: main)
--preset <name>     Preset profile: claude | opencode | codex | codex-home | all
--ai <list>         Install scope
--agent <list>      Alias for --ai
--codex-target <project|home>  Where to install Codex Agent Skills when --ai includes codex (default: project)
--uninstall         Remove SpecGate assets instead of installing
```

Notes:
- No backup files are generated by `install`, `uninstall`, `clean`, or `update`.
- `--update` is safe to run repeatedly: unchanged files are skipped and only changed files are updated.

### Examples

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --dry-run --preset codex --prefix .
```

```bash
# Reset a broken or partial existing install in place
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --clean --preset claude --prefix .
```

```bash
# Update only changed files
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --update --preset claude --prefix .
```

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --version v0.0.0 --prefix .
```

## 5) Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --prefix .
```

`--uninstall` without `--ai` or `--preset` removes all agents by default.
To remove only one agent:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --preset claude --prefix .
```

Verify removal of all SpecGate assets:

```bash
[ ! -d .specify ] \
  && [ ! -d .claude/commands/specgate ] \
  && ( [ ! -f .claude/hooks/statusline.js ] || ! (grep -qF "# @specgate-managed:statusline" .claude/hooks/statusline.js || grep -qF "Claude Code Statusline - SpecGate Edition" .claude/hooks/statusline.js) ) \
  && [ ! -d .codex/skills/specgate ] \
  && [ ! -d .opencode/command ] \
  && [ ! -f docs/SPECGATE.md ] \
  && echo "SpecGate assets removed."
```

`statusline.js` is removed only if it was added by SpecGate (to avoid deleting custom user-installed statusline scripts).
`--update` also skips `statusline.js` unless it has SpecGate ownership markers.

If you installed Codex in home scope, remove with:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --preset codex-home --prefix .
```

```bash
[ ! -d ~/.codex/skills/specgate ] && echo "Codex home skills removed."
```

## 6) Installed assets

- `.specify/*`
- `.claude/commands/specgate/*`
- `.claude/hooks/statusline.js`
- `.codex/skills/specgate/*` (project install: `.codex/skills/specgate`, or home install: `~/.codex/skills/specgate`)
  - Includes workflow-dedicated skills: `feature-set`, `specify`, `clarify`, `codify`, `checklist`, `analyze`, `test-specify`, `test-codify`, `taskstoissues`, `constitution`, `feature-done`
- `.opencode/command/*`
- `docs/SPECGATE.md`
- `.specify/scripts/bash/check-naming-policy.sh`
- `.specify/scripts/bash/run-feature-workflow-sequence.sh`

Note: `.specify` and `docs/SPECGATE.md` are always installed together for single-agent installs (`--ai codex`, `--ai claude`, etc.) and the equivalent presets (`--preset codex`, `--preset claude`, etc.).

## 6) Recommended checks (instead of daily smoke check)

Run production workflow checks from repository root:

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> --json

```

Strict naming is enabled by default. If a feature is still on a legacy artifact state, temporarily run with:

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> --json --no-strict-naming
```

For full production check, include a temporary setup step when you want code-template regeneration:

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> --json --setup-code
```

`specgate-smoke-check.sh` remains available as an installation validation script, but is not recommended as a routine daily check.

For detailed operation guidance, see `docs/SPECGATE.md`.

## Korean version

- [README-ko.md](./README-ko.md)
