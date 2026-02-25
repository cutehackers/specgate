# SpecGate Guide

SpecGate is the Spec-Driven Development (SDD) workflow for Claude, OpenCode, and Codex.
One clear flow is defined:

`/specify -> /clarify -> /codify -> /test-specify -> /test-codify`

This repository only contains the installer and runtime assets.
Actual project work happens in your consumer repo.

---

## 0) Use this guide with README first

- Korean docs: [`README-ko.md`](../README-ko.md)
- English docs: [`README.md`](../README.md)

If you need one-command quick start:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --preset claude --prefix .
```

---

## 1) What SpecGate manages

- `.specify` : scripts and templates
- `.claude/commands/specgate/*`
- `.opencode/command/*`
- `.claude/hooks/statusline.js`
- `.codex/skills/specgate/*` (or `~/.codex/skills/specgate/*` for home scope)
- `docs/SPECGATE.md` (this document)
- `.specify/scripts/bash/run-feature-workflow-sequence.sh`
- `.specify/scripts/bash/check-naming-policy.sh`

`specs/feature-stage.local.json` is created only in consumer projects via `/feature-set`.

---

## 2) Install options (install.sh)

```text
--prefix <path>               Install target directory (default: .)
--dry-run                     Show plan only
--force                       Overwrite existing files (no backup)
--update                      Update changed files only
--clean                       Remove selected assets and reinstall
--version <name>              Branch/tag to install (default: main)
--preset <name>               claude | opencode | codex | codex-home | all
--ai <list>                   Install scope (alias: --agent)
--agent <list>                Alias of --ai
--codex-target <project|home> Codex skill install target (default: project)
--uninstall                   Remove assets
```

Notes:

- Install/update/remove/clean operations do not create backup files.
- `--update` is idempotent for unchanged files.

---

## 3) Standard workflow and quality gates

### 3.1 Normal command sequence

1. `/feature-set`
2. `/specify`
3. `/clarify`
4. `/codify`
5. `/test-specify`
6. `/test-codify`

### 3.2 Output contract

- `/specify` : `spec.md`, `research.md`
- `/clarify` : `data-model.md`, `screen_abstraction.md`, `quickstart.md`, `tasks.md`
- `/codify` : implementation from `tasks.md` + `/clarify` artifacts only
- `/test-specify` and `/test-codify` : `test-spec.md`
- `specs/feature-stage.local.json` exists only inside consumer repository

### 3.3 Recommended daily gate

Run from repo root with feature directory:

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> --json
```

Strict naming is default. For legacy migration:

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> --json --no-strict-naming
```

---

## 4) Layer governance (strict-layer)

### 4.1 Purpose

`strict-layer` verifies architecture/constitution layer constraints before codify-related tasks.
Without explicit rules, implementation may bypass intended separation of layers.

### 4.2 Where rules live in consumer projects

- `.specify/layer_rules/contract.yaml`
- `.specify/layer_rules/overrides/<feature-id>.yaml`
- `.specify/layer_rules/resolved/<feature-id>.json`

`contract.yaml` is the first-class policy source for all codify runs; feature overrides are layered on top.

### 4.3 Policy generation and loading scripts

#### bootstrap-layer-rules.sh

Use this once when you want to initialize a project-level rule baseline and apply defaults.

```bash
bash .specify/scripts/bash/bootstrap-layer-rules.sh --repo-root . --feature-dir "<abs-feature-path>" --json
```

#### load-layer-rules.sh

Load + merge + optionally write contract for feature-level governance.

```bash
bash .specify/scripts/bash/load-layer-rules.sh --source-dir "<abs-feature-path>" --repo-root . --json
```

`load-layer-rules.sh`는 YAML 문서 파싱 시 `PyYAML`(권장) 또는 `ruamel.yaml`이 필요합니다. 두 파서가 모두 없으면 `errors`가 발생하고 정책은 신뢰성 있게 적용되지 않습니다.

Compatibility form:

```bash
bash .specify/scripts/bash/load-layer-rules.sh --feature-dir "<abs-feature-path>" --repo-root . --json
```

##### Merge sources

- `.specify/layer_rules/contract.yaml` (global baseline)
- `.specify/layer_rules/overrides/<feature-id>.yaml` (feature override, if exists)
- `<feature>/docs/ARCHITECTURE.md`
- `<feature>/docs/architecture.md`
- `<feature>/docs/constitution.md`
- `<feature>/constitution.md`

##### `--source-dir` scanning policy

`--source-dir` only checks fixed paths (no recursive search):

- `<source-dir>/docs/ARCHITECTURE.md`
- `<source-dir>/docs/architecture.md`
- `<source-dir>/docs/constitution.md`
- `<source-dir>/constitution.md`

`--feature-id` is only used for feature override/resolved cache file naming:
`.specify/layer_rules/overrides/<feature-id>.yaml`, `.specify/layer_rules/resolved/<feature-id>.json`.

##### Recommended commands

```bash
# inspect resolved policy
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "<abs-feature-path>" \
  --repo-root . \
  --json

# write merged result to contract.yaml
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "<abs-feature-path>" \
  --repo-root . \
  --write-contract \
  --json

# force overwrite existing contract.yaml
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "<abs-feature-path>" \
  --repo-root . \
  --write-contract \
  --force-contract \
  --json
```

Practical one-line form with a real architecture doc path:

```bash
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "/Users/me/workspace/app/lib/src/features/home" \
  --repo-root "/Users/me/workspace/app" \
  --write-contract \
  --force-contract \
  --json
```

### 4.4 JSON output fields to check

From `--json` output, confirm:

- `source_kind`: origin type (`CONTRACT`, `OVERRIDE`, `CONSTITUTION`, `ARCHITECTURE`, `CONTRACT_GENERATED`, `DEFAULT`)
- `source_file`: resolved source filename
- `source_reason`: why that source was chosen
- `has_layer_rules`: must be `true` under strict mode
- `applied_sources`: merge history list
- `resolved_path`: resolved JSON path
- `contract_path`: path where merged contract was written
- `contract_written`: boolean for `--write-contract` success
- `parse_events`: ordered parser event log (attempt/fail/success) for YAML/JSON candidate extraction
- `parse_summary`: aggregate counters for parser outcomes (`total`, `success`, `failed`, `schema_mismatch`, etc.)
- `parse_summary` is used as a hard-fail gate in strict mode when:
  - `failed > 0`
  - `blocked_by_parser_missing > 0`
- parser status codes to check in `parse_events`:
  - `NO_YAML_PARSER_AVAILABLE`
  - `YAML_PARSE_ERROR`
  - `JSON_PARSE_ERROR`
  - `POLICY_SCHEMA_MISSING`
  - `JSON_FULL_TEXT_PARSE_ERROR`
- In strict-mode JSON output, workflow summary now includes `layer_rules_preflight` with `source_*`, `resolved_path`, `parse_summary`, and `parse_events`.

### 4.5 Strict and relaxed execution

`strict-layer` is disabled by default (report-only). Use strict mode when you want hard failure on missing/violated rules:

Strict mode (hard fail):

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir "<abs-feature-path>" --strict-layer --strict-naming --json
```
In strict mode, workflow fails when parser metadata indicates malformed/ambiguous YAML/JSON input (`parse_summary.failed > 0`) or unavailable parser dependency (`parse_summary.blocked_by_parser_missing > 0`).

Relaxed mode (warn/report only):

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir "<abs-feature-path>" --no-strict-layer --json
```

Include `--setup-code` when you want template regeneration in the same pass:

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir "<abs-feature-path>" --json --setup-code
```

---

## 5) Script map used by layer governance

- `.specify/scripts/bash/load-layer-rules.sh`: resolve architecture/constitution -> merged policy -> contract
- `.specify/scripts/bash/bootstrap-layer-rules.sh`: initialize project-level rule baseline
- `.specify/scripts/bash/check-layer-compliance.sh`: validate generated code against rules
- `.specify/scripts/bash/run-feature-workflow-sequence.sh`: include policy validation in daily checks

---

## 6) Remove guide

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --prefix .
```

Check full removal:

```bash
[ ! -d .specify ] \
  && [ ! -d .claude/commands/specgate ] \
  && ( [ ! -f .claude/hooks/statusline.js ] || ! (grep -qF "# @specgate-managed:statusline" .claude/hooks/statusline.js || grep -qF "Claude Code Statusline - SpecGate Edition" .claude/hooks/statusline.js) ) \
  && [ ! -d .codex/skills/specgate ] \
  && [ ! -d .opencode/command ] \
  && [ ! -f docs/SPECGATE.md ] \
  && echo "SpecGate assets removed."
```

`statusline.js` is only removed when owned by SpecGate.
`--update` similarly updates it only when owned markers exist.

---

## 7) Installation troubleshooting

- If command output indicates incomplete install, run install with `--clean`.
- If statusline is unexpectedly changed by another tool, keep it and inspect marker checks.
- For Codex + home scope, uninstall separately with `--preset codex-home`.

When you need command reference details and examples for other platforms, refer to `README.md` and `README-ko.md`.
