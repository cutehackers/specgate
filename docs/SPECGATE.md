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

`load-layer-rules.sh` uses machine-readable payload extraction first (`yaml`/`json` blocks), then falls back to prose inference from:

- `docs/ARCHITECTURE.md`
- `docs/constitution.md`
- `constitution.md`

Inference follows safe defaults and can still produce contract output when no block exists. Parser dependencies still improve deterministic extraction when YAML blocks are present.

`PyYAML`(권장) 또는 `ruamel.yaml`은 YAML 블록 파싱 안정성을 위해 사용됩니다.

```bash
python3 -m pip install PyYAML
# 또는
python3 -m pip install ruamel.yaml
```

Compatibility form:

```bash
bash .specify/scripts/bash/load-layer-rules.sh --feature-dir "<abs-feature-path>" --repo-root . --json
```

##### Merge sources

### 4.3.1 Architecture template for inference-ready docs

[`docs/architecture-template.md`](../docs/architecture-template.md) 를 사용자용 템플릿으로 공개했습니다. 프로젝트에서 바로 복사해 시작하세요.

`load-layer-rules.sh`는 prose inference를 지원하므로, 다음 템플릿으로 `docs/ARCHITECTURE.md`를 쉽게 만들 수 있습니다.

```bash
mkdir -p "<abs-feature-path>/docs"
cp docs/architecture-template.md "<abs-feature-path>/docs/ARCHITECTURE.md"
cp .specify/templates/architecture-template.md "<abs-feature-path>/docs/ARCHITECTURE.md"
```

참조:
- 설치/런타임 템플릿: [`../.specify/templates/architecture-template.md`](../.specify/templates/architecture-template.md)
- 사용자 가이드용 템플릿: [`architecture-template.md`](architecture-template.md)

권장 작성 순서:

1. 프로젝트 도메인에 맞춰 개요와 레이어/디렉터리 예시를 채웁니다.
2. `Layer Rules`의 `Do not import ...` 문장을 실제 규칙으로 정확히 적습니다.
3. 필요하면 `Behavior / Error Handling` 섹션을 추가해 정책 구체화합니다.
4. 가장 결정적인 부분은 아래처럼 machine-readable block을 넣어 정밀 파싱을 보장하는 것입니다.

```layer_rules
kind: layer_rules
version: "1"
naming:
  entity: "{Name}Entity"
  dto: "{Name}Dto"
  use_case: "{Action}UseCase"
  repository: "{Feature}Repository"
  repository_impl: "{Feature}RepositoryImpl"
  event: "{Feature}{Action}Event"
  controller: "{Feature}Controller"
  data_source: "{Feature}{Type}DataSource"
  provider: "{featureName}{Type}Provider"

layer_rules:
  domain:
    forbid_import_patterns: []
  data:
    forbid_import_patterns: []
  presentation:
    forbid_import_patterns: []

errors:
  policy:
    domain_layer:
      forbid_exceptions: [StateError]
      require_result_type: true

behavior:
  use_case:
    allow_direct_repository_implementation_use: false
```

코드 블록 타입은 `layer_rules`(또는 `yaml`)를 사용하면 좋고, 스크립트는 일반 문장 기반 추론도 함께 수행합니다.

- `cp`로 복사 뒤 바로 추론 대상이 되므로 최초 작성 진입장벽이 낮아집니다.
- 템플릿을 사용자 정의하면 규칙 가독성은 유지하면서도 정책 정확도를 높일 수 있습니다.

### 4.3.2 기존 `ARCHITECTURE.md` 마이그레이션(실무 체크리스트)

기존 문서가 이미 있는 경우, 아래 6단계로 템플릿 기준 신호를 보강하면 됩니다.

1. 백업
```bash
cp "<feature-path>/docs/ARCHITECTURE.md" "<feature-path>/docs/ARCHITECTURE.md.bak"
```

2. 필수 섹션 정렬 (기존 내용은 삭제하지 말고 재배치)
- `## Presentation`
- `## Domain`
- `## Data`
- `## Cross-cutting` 또는 `## Naming`(선택)

3. 각 섹션에 최소 1개 이상의 명시 규칙 추가
- Presentation: `Do not import Data layer types in Presentation.`
- Domain: `Do not import Presentation.` 또는 `Do not import Data layer types in Domain.`
- Data: `Do not import Presentation.`
- Errors: `Domain use case return type must be explicit.`
- Behavior: `UI must call controller dispatch only (via RefEventDispatcherX).`

4. 1개 이상 bad-import 예시 추가 (정확도 상승)
- 코드블록 안에서:
```dart
// ❌ WRONG: Presentation importing DTO
import 'package:app/features/auth/data/models/login_dto.dart';
```

5. 선택: deterministic 추출을 위해 machine-readable 블록 추가 (`layer_rules` 또는 `yaml`).

6. 즉시 검증
```bash
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "<feature-path>/docs" \
  --repo-root . \
  --write-contract \
  --json
```

검증 포인트:
- `source_mode`:
  - 블록이 없으면 `INFERRED`
  - 블록이 있으면 `PARSED`
- `inference.confidence`가 가능하면 `0.75+`
- `inference.evidence`에 layer/errors/behavior 근거가 기록됨
- `policy.layer_rules`가 비어 있지 않음
- 실패 시 `parse_summary`와 `parse_events`의 오류 코드 확인 (`NO_POLICY_FOUND`, `YAML_PARSE_ERROR` 등)

- `docs/architecture-template.md`의 체크리스트를 기준으로 반복 정합성 점검하면 매번 동일한 규칙 품질로 정렬할 수 있습니다.


- `.specify/layer_rules/contract.yaml` (global baseline)
- `.specify/layer_rules/overrides/<feature-id>.yaml` (feature override, if exists)
- `<feature>/docs/ARCHITECTURE.md` (canonical machine policy source)
- `<feature>/docs/constitution.md`
- `<feature>/constitution.md`

For deterministic extraction, place the machine-readable layer policy in this one block:

```layer_rules
kind: layer_rules
version: "1"
naming:
  entity: "{Name}Entity"
  dto: "{Name}Dto"
  use_case: "{Action}UseCase"
  repository: "{Feature}Repository"
  repository_impl: "{Feature}RepositoryImpl"
  event: "{Feature}{Action}Event"
  controller: "{Feature}Controller"
  data_source: "{Feature}{Type}DataSource"
  provider: "{featureName}{Type}Provider"

layer_rules:
  domain: {}
  data: {}
  presentation: {}

errors:
  policy:
    domain_layer:
      forbid_exceptions: []
      require_result_type: true

behavior:
  use_case:
    allow_direct_repository_implementation_use: false
```

Or use explicit markers: `<!-- layer-rules:start --> ... <!-- layer-rules:end -->`.

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
- `source_mode`: resolution mode (`PARSED`, `INFERRED`, `DEFAULT`)
- `source_file`: resolved source filename
- `source_reason`: why that source was chosen
- `has_layer_rules`: must be `true` under strict mode
- `applied_sources`: merge history list
- `resolved_path`: resolved JSON path
- `contract_path`: path where merged contract was written
- `contract_written`: boolean for `--write-contract` success
- `inference.confidence`: score for deterministic inference decisions (`0.0`~`1.0`)
- `inference.rules_extracted`: count of inferred actionable rules
- `inference.fallback_applied`: `true` when inferred rules were merged
- `inference.evidence`: line/pattern/rule evidence list used by inference
- `parse_events`: ordered parser event log (attempt/fail/success) for YAML/JSON candidate extraction
- `parse_summary`: aggregate counters for parser outcomes (`total`, `success`, `failed`, `schema_mismatch`, etc.)
- For `source_mode=INFERRED` strict mode uses `inference.confidence`:
  - `< 0.5`: hard fail
  - `0.5 ~ 0.75`: warning/allowed
  - `>= 0.75`: pass (unless no layer_rules or parser hard errors)
- parser status codes to check in `parse_events`:
  - `NO_YAML_PARSER_AVAILABLE`
  - `YAML_PARSE_ERROR`
  - `JSON_PARSE_ERROR`
  - `POLICY_SCHEMA_MISSING`
  - `JSON_FULL_TEXT_PARSE_ERROR` (legacy; not emitted for Markdown in the current parser flow)
- In strict-mode JSON output, workflow summary now includes `layer_rules_preflight` with `source_*`, `resolved_path`, `parse_summary`, and `parse_events`.

### 4.5 Strict and relaxed execution

`strict-layer` is disabled by default (report-only). Use strict mode when you want hard failure on missing/violated rules:

Strict mode (hard fail):

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir "<abs-feature-path>" --strict-layer --strict-naming --json
```
In strict mode:

- `source_mode=PARSED` requires resolved policy with no hard parser errors (`parse_summary.failed == 0`, `parse_summary.blocked_by_parser_missing == 0`).
- `source_mode=INFERRED` applies confidence thresholds:
  - `< 0.5` fails (hard block)
  - `0.5 ~ 0.75` warns (non-blocking in strict mode)
  - `>= 0.75` continues to enforcement
- `source_mode=DEFAULT` still requires a usable `layer_rules` section.

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
