# SpecGate

SpecGate is a lightweight workflow package for Spec-Driven Development (SDD).
It provides commands and scripts for Claude, OpenCode, and Codex.

This repository can be installed directly into your project without cloning.

- Default install path: current directory (`.`)
- Default scope: all agents (`all` by default). The guide below uses a single-agent example.
- Entry commands:
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

## Standard feature flow

- `/specify -> /clarify -> /codify -> /test-specify -> /test-codify`
- `/specify` creates and updates `spec.md`, `research.md`.
- `/clarify` creates and updates at least `data-model.md`, `screen_abstraction.md`, `quickstart.md`, `tasks.md`.
- `/codify` should only implement code based on `/clarify` outputs and `tasks.md`.
- `/test-specify` and `/test-codify` create and execute `test-spec.md` separately.
- `specs/feature-stage.local.json` is the local workflow pointer.
  - It is created when `/feature-set` runs in a consumer repository.
  - It is not included in package distribution.

## 1.2) Beginner install (recommended)

### Option A) Install one agent

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --preset [claude|opencode|codex|codex-home] --prefix .
```

Pick one of:

- Claude:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
    | bash -s -- --preset claude --prefix .
  ```

- Opencode:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
    | bash -s -- --preset opencode --prefix .
  ```

- Codex (project scope):

  ```bash
  curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
    | bash -s -- --preset codex --prefix .
  ```

- Codex (home scope):

  ```bash
  curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
    | bash -s -- --preset codex-home --prefix .
  ```

### Option B) Install multiple agents together

Pass a comma-separated list with `--ai`.

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --ai claude,opencode --prefix .

curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --ai claude,opencode,codex --prefix .

curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --ai claude,opencode,codex --codex-target home --prefix .
```

Preset examples:

```text
claude, opencode, codex, codex-home, all
```

### 1.3 Update / remove

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --update --preset claude --prefix .

curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --uninstall --preset claude --prefix .
```

### 1.4 Verify installation

```bash
ls -la .specify .claude .codex .opencode
```

If install is broken:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --dry-run --preset claude --prefix .

curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --clean --preset claude --prefix .
```

Run locally from repo clone:

```bash
bash /path/to/specgate/install.sh --preset claude --prefix .
```

Installation is complete once your selected agent folders appear.
Codex executes workflows directly from `.codex/skills/specgate/<workflow>/SKILL.md`.
If a workflow needs user input, ask in chat directly instead of `AskUserQuestion`.

## 1.5) Architecture-driven layer policy (inference-first)

You can generate layer policy from prose-first architecture docs without maintaining JSON/YAML payloads in every feature.

```bash
cp docs/architecture-template.md "<abs-feature-path>/docs/ARCHITECTURE.md"
bash .specify/scripts/bash/load-layer-rules.sh --source-dir "<abs-feature-path>/docs" --repo-root . --write-contract --json
```

Recommended workflow:

- Keep `docs/ARCHITECTURE.md` (human-readable, prose-first).
- Add an explicit `layer_rules` block only when needed (use ` ```layer_rules`), when available.
- Run `load-layer-rules.sh`:
  - `source_mode` becomes `INFERRED` when parsing is not possible.
  - `source_kind` becomes `INFERRED`.
  - `inference.confidence` and `inference.evidence` are stored in JSON output.
- strict mode notes:
  - `confidence >= 0.75` passes parse action as accepted.
  - `0.5 ~ 0.75` emits warning but proceeds.
  - `< 0.5` is treated as low-confidence and can fail strict checks depending on `--strict-layer`.

### 1.5.0) Convert an existing `ARCHITECTURE.md` to template-ready format

If you already have `docs/ARCHITECTURE.md`, you can migrate it without rewriting everything.

1) Backup original document first.
```bash
cp "<feature-path>/docs/ARCHITECTURE.md" "<feature-path>/docs/ARCHITECTURE.md.bak"
```

2) Keep user-readable content and add/align required signal sections:
- `## Presentation` section contains: `- Do not import Data layer types in Presentation.`
- `## Domain` section contains: `- Do not import Presentation.` and/or `- Do not import Data layer types in Domain.`
- `## Data` section contains: `- Do not import Presentation.`
- Add `errors` and `behavior` constraints in text form (for example: return type required, `StateError` forbidden, `dispatch`-only state changes).

3) Optional machine-readable block (recommended for deterministic extraction):
```layer_rules
kind: layer_rules
version: "1"
layer_rules:
  domain:
    forbid_import_patterns:
      - "^package:.*\\/presentation\\/"
      - "^package:.*\\/data\\/"
  data:
    forbid_import_patterns:
      - "^package:.*\\/presentation\\/"
  presentation:
    forbid_import_patterns:
      - "^package:.*\\/data\\/"
```

4) Validate immediately:
```bash
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "<feature-path>/docs" \
  --repo-root . \
  --write-contract \
  --json
```

5) Verify in JSON:
- `source_mode` should become `INFERRED` (if no block) or `PARSED` (if block exists).
- `inference.confidence` should ideally be `>= 0.75`.
- `inference.evidence` should include at least:
  - one `layer_rules.<layer>.forbid_import_patterns` entry
  - naming/behavior/error hints if you added them
- `policy.layer_rules` should not be empty.

You can use the full migration checklist from `docs/architecture-template.md`.

See:

- User template: [`docs/architecture-template.md`](docs/architecture-template.md)
- Runtime template: [`.specify/templates/architecture-template.md`](.specify/templates/architecture-template.md)
- Runtime docs: [docs/SPECGATE.md](docs/SPECGATE.md)

### 1.5.1) Production validation

- Inference/strict-mode smoke validation:
  ```bash
  bash .specify/scripts/bash/specgate-smoke-check.sh
  ```
- Additional regression checks to run before release:
  - `bash .specify/scripts/bash/load-layer-rules.sh --source-dir <feature-path>/docs --repo-root . --write-contract --json`
  - `bash .specify/scripts/bash/check-layer-compliance.sh --feature-dir <feature-path> --strict-layer --json`
  - `bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <feature-path> --strict-layer --json`
- Verified on 2026-02-25: smoke checks pass, including prose-only inference with confidence/evidence metadata.

## 2) Advanced: per-agent references

Choose agent type first, then use the 3-step sequence (install|update|remove).

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

### Codex (project scope, default)

`--preset codex` uses project scope.

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

## 3) Advanced install modes

### Single-agent remote install

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --preset claude --prefix .
```

### Multi-agent install guide

Use one command with `--ai` to install multiple agents.

1. Claude + Opencode

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode --prefix .
```

2. Claude + Opencode + Codex (project scope)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode,codex --prefix .
```

3. Claude + Opencode + Codex (home scope)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode,codex --codex-target home --prefix .
```

4. All

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai all --prefix .
```

For update/remove on the same set, add `--update`/`--uninstall`.

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --update --ai claude,opencode --prefix .
bash /tmp/specgate-install.sh --uninstall --ai claude,opencode --prefix .
```

`--ai` and `--agent` are aliases.

Supported values: `all`, `claude`, `codex`, `opencode`.
(`--ai all` installs all known agent assets.)

### Installation mapping

- Claude: `.claude/commands/specgate/*`
- Opencode: `.opencode/command/*`
- Codex + `--codex-target project`: `.codex/skills/specgate/*` (project scope)
- Codex + `--codex-target home`: `~/.codex/skills/specgate/*` (shared scope)
- `--ai claude,opencode` installs both Claude and Opencode targets.
- `--ai claude,opencode,codex` installs all selected targets.

### Install from local clone

```bash
/path/to/specgate/install.sh --preset claude --prefix .
```

## 4) Install options

```text
--prefix <path>              Install target directory (default: .)
--dry-run                    Print planned operations only
--force                      Overwrite existing files without backup
--update                     Update only changed files (no backup)
--clean                      Remove current SpecGate assets and reinstall
--version <name>             Branch/tag to install (default: main)
--preset <name>              Preset: claude | opencode | codex | codex-home | all
--ai <list>                  Select agent list
--agent <list>               Alias of --ai
--codex-target <project|home> Install location for Codex Skills (default: project)
--uninstall                  Run in remove mode
```

Notes:

- install/update/uninstall/clean never create backup files.
- `--update` is safe for repeat runs; unchanged files are skipped.

### Examples

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --dry-run --preset codex --prefix .
```

```bash
# Reinstall from scratch when install state is partially broken
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

## 5) Remove

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --prefix .
```

If you omit `--ai` or `--preset`, all are removed by default (`all`).
Remove one agent only:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --preset claude --prefix .
```

Verify removal:

```bash
[ ! -d .specify ] \
  && [ ! -d .claude/commands/specgate ] \
  && ( [ ! -f .claude/hooks/statusline.js ] || ! (grep -qF "# @specgate-managed:statusline" .claude/hooks/statusline.js || grep -qF "Claude Code Statusline - SpecGate Edition" .claude/hooks/statusline.js) ) \
  && [ ! -d .codex/skills/specgate ] \
  && [ ! -d .opencode/command ] \
  && [ ! -f docs/SPECGATE.md ] \
  && echo "SpecGate assets removed."
```

`statusline.js` is only removed when it is identified as a SpecGate-owned file.
`--update` also updates `statusline.js` only when ownership markers exist.

If you installed Codex home scope:

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
- `.codex/skills/specgate/*` (project install: `.codex/skills/specgate`, home install: `~/.codex/skills/specgate`)
  - Workflow SKILL files: `feature-set`, `specify`, `clarify`, `codify`, `checklist`, `analyze`, `test-specify`, `test-codify`, `taskstoissues`, `constitution`, `feature-done`
- `.opencode/command/*`
- `docs/SPECGATE.md`
- `.specify/scripts/bash/check-naming-policy.sh`
- `.specify/scripts/bash/run-feature-workflow-sequence.sh`

Note: even with single-agent installs (`--preset codex`, `--preset claude`), `.specify` and `docs/SPECGATE.md` are always installed.

## 6) Daily check guide (smoke-check substitute)

Run the following from repository root before working on a feature:

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> --json
```

Strict naming is enabled by default. Temporarily bypass for legacy artifacts:

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> --json --no-strict-naming
```

## 6.1) Consumer-project layer governance (strict-layer toggle)

In consumer projects, layer policy is resolved under `.specify/layer_rules`.

- `.specify/layer_rules/contract.yaml`
- `.specify/layer_rules/overrides/<feature-id>.yaml` (optional)

Initialize/sync policy before strict runs:

```bash
bash .specify/scripts/bash/bootstrap-layer-rules.sh --repo-root . --feature-dir "<abs-feature-path>" --json
```

Verify the effective policy before running gates:

```bash
bash .specify/scripts/bash/load-layer-rules.sh --source-dir "<feature-path-or-file>" --json
```

Parser dependency: `load-layer-rules.sh` requires `PyYAML` (recommended) or `ruamel.yaml` in the Python environment to parse YAML blocks deterministically. Without one of these, parsing errors are returned and policy resolution is treated as unreliable.

Install one of them before first strict run:

```bash
python3 -m pip install PyYAML
# or
python3 -m pip install ruamel.yaml
```

### `load-layer-rules.sh` usage

This command resolves merged layer policy from:

- `.specify/layer_rules/contract.yaml` (global)
- `.specify/layer_rules/overrides/<feature-id>.yaml` (override)
- `<feature>/docs/ARCHITECTURE.md`
- `<feature>/docs/architecture.md`
- `<feature>/docs/constitution.md`
- `<feature>/constitution.md`

`--source-dir` accepts either a feature folder or a direct source file path:

- when a directory is provided, it checks the following files in that directory (no recursive scan):

- `<source-dir>/docs/ARCHITECTURE.md`
- `<source-dir>/docs/architecture.md`
- `<source-dir>/docs/constitution.md`
- `<source-dir>/constitution.md`

- when a file is provided, that file is treated as an explicit policy source and parsed directly (for example: `docs/ARCHITECTURE.md`).

If `--repo-root` is omitted, it defaults to the project root.

Use cases:

```bash
# only inspect merged policy
bash .specify/scripts/bash/load-layer-rules.sh --source-dir "<feature-path-or-file>" --json

# synchronize to contract.yaml
bash .specify/scripts/bash/load-layer-rules.sh --source-dir "<feature-path-or-file>" --write-contract --json

# force overwrite contract.yaml
bash .specify/scripts/bash/load-layer-rules.sh --source-dir "<feature-path-or-file>" --write-contract --force-contract --json
```

Direct one-line example with an explicit architecture path:

```bash
# explicit feature file path example
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "./docs/ARCHITECTURE.md" \
  --write-contract \
  --force-contract \
  --json
```

Legacy `--feature-dir` form is still supported.

```bash
bash .specify/scripts/bash/load-layer-rules.sh --feature-dir "<feature-path-or-file>" --json
```

`load-layer-rules.sh` is the standard path for policy check/sync:

- merge priority is `contract -> override -> architecture/constitution`
- `--write-contract` writes merged result to `contract.yaml`
- `--force-contract` replaces existing `contract.yaml`
- verify using `contract_path` and `contract_written`

Inspect outputs (`source_kind`, `source_file`, `source_reason`, `resolved_path`, `has_layer_rules`, `applied_sources`, `contract_path`, `contract_written`, `parse_events`, `parse_summary`) in JSON mode.
In sequence runs (`run-feature-workflow-sequence.sh --json`), check `layer_rules_preflight` for parser preflight status before naming/code checks.

`source_kind` examples:

- `CONTRACT`: global contract loaded
- `OVERRIDE`: feature override loaded
- `CONSTITUTION` / `ARCHITECTURE`: extracted from feature docs
- `CONTRACT_GENERATED`: contract was produced by `--write-contract`
- `DEFAULT`: no source found (strict mode should fail)

`strict-layer` is disabled by default (report-only). Run strict mode for hard failures on missing/violated rules:

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir "<abs-feature-path>" --strict-layer --strict-naming --json
```

Run relaxed mode temporarily (warnings + report only):

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir "<abs-feature-path>" --no-strict-layer --json
```

- `--strict-layer` treats missing/violated layer policy and parser failures as hard failure.
  - Hard-fail conditions include `parse_summary.failed > 0` and `parse_summary.blocked_by_parser_missing > 0` from sequence paths-only preflight.
- `--no-strict-layer` is for migration periods and keeps sequence green while reporting issues.

Add `--setup-code` when you also want template generation.

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir "<abs-feature-path>" --json --setup-code
```

`specgate-smoke-check.sh` remains for install verification, not routine daily checks.

See `docs/SPECGATE.md` for more operational details.

## Korean version

- [README-ko.md](./README-ko.md)
