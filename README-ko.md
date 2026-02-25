# SpecGate

SpecGate는 Spec-Driven Development(SDD)를 위한 가벼운 워크플로우 패키지입니다.
Claude, OpenCode, Codex에서 사용할 수 있는 명령과 스크립트를 제공합니다.

이 저장소는 프로젝트에 클론 없이 바로 설치할 수 있습니다.

- 기본 설치 경로: 현재 디렉토리(`.`)
- 기본 설치 범위: 전체 에이전트(`all` 기본값). 기본 문서는 단일 에이전트 설치 예시로 안내합니다.
- 실행 명령:
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

## 기본 피처 운영 흐름

- `/specify -> /clarify -> /codify -> /test-specify -> /test-codify`
- `/specify`은 `spec.md`, `research.md`를 생성/갱신합니다.
- `/clarify`는 반드시 `data-model.md`, `screen_abstraction.md`, `quickstart.md`, `tasks.md`를 생성하고 갱신합니다.
- `/codify`는 `/clarify` 산출물과 `tasks.md` 기반으로 구현만 수행해야 합니다.
- `/test-specify`와 `/test-codify`는 `test-spec.md`를 각각 생성/실행합니다.
- `specs/feature-stage.local.json`은 로컬 실행 상태 포인터입니다.
  - 소비자 프로젝트에서 `/feature-set` 실행 시 생성됩니다.
  - 패키지 배포본에는 포함하지 않습니다.

## 1) 초보자용 빠른 설치 (권장)

### 옵션 A) 단일 에이전트 설치

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --preset [claude|opencode|codex|codex-home] --prefix .
```

에이전트 하나를 선택해 아래 중 하나 실행:

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

- Codex(프로젝트 스코프):

  ```bash
  curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
    | bash -s -- --preset codex --prefix .
  ```

- Codex(홈 스코프):

  ```bash
  curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
    | bash -s -- --preset codex-home --prefix .
  ```

### 옵션 B) 여러 에이전트를 함께 설치

`--ai`에 쉼표로 여러 에이전트를 지정하세요.

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --ai claude,opencode --prefix .

curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --ai claude,opencode,codex --prefix .

curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --ai claude,opencode,codex --codex-target home --prefix .
```

단일 preset 값:

```text
claude, opencode, codex, codex-home, all
```

### 1.3 업데이트 / 삭제

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --update --preset claude --prefix .

curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --uninstall --preset claude --prefix .
```

### 1.4 설치 확인

```bash
ls -la .specify .claude .codex .opencode
```

설치가 깨졌거나 잘 안될 때:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --dry-run --preset claude --prefix .

curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --clean --preset claude --prefix .
```

로컬 레포에서 실행할 때:

```bash
bash /path/to/specgate/install.sh --preset claude --prefix .
```

선택한 에이전트의 폴더가 보이면 설치가 완료된 것입니다.
Codex는 각 워크플로우를 `.codex/skills/specgate/<workflow>/SKILL.md`로 직접 실행합니다.
워크플로우 진행 중 사용자 입력이 필요하면 `AskUserQuestion`이 아닌 채팅에서 직접 질문하고 답변을 기다리세요.

## 2) 고급: 에이전트별 사용법 참조

에이전트 유형을 먼저 정한 뒤, 아래 3단계만 기억하면 됩니다. (설치|업데이트|삭제)

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

### Codex (프로젝트 스코프, 기본값)

`--preset codex`는 프로젝트 스코프(설치경로) 기준입니다.

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --preset codex --prefix .

bash /tmp/specgate-install.sh --update --preset codex --prefix .

bash /tmp/specgate-install.sh --uninstall --preset codex --prefix .
```

### Codex (홈 스코프, 공유)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --preset codex-home --prefix .

bash /tmp/specgate-install.sh --update --preset codex-home --prefix .

bash /tmp/specgate-install.sh --uninstall --preset codex-home --prefix .
```

## 3) 고급 설치 방식

### 원격 설치 (단일 에이전트)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --preset claude --prefix .
```

### 에이전트 조합 설치 가이드

여러 에이전트를 한 번에 설치하려면 다음처럼 `--ai`로 묶어 쓰면 됩니다.

1. Claude + Opencode

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode --prefix .
```

2. Claude + Opencode + Codex (프로젝트 스코프)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode,codex --prefix .
```

3. Claude + Opencode + Codex (홈 스코프)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode,codex --codex-target home --prefix .
```

4. 전체 설치

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai all --prefix .
```

동일한 조합에서 업데이트/제거는 `--update`/`--uninstall`을 붙이면 됩니다.

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --update --ai claude,opencode --prefix .
bash /tmp/specgate-install.sh --uninstall --ai claude,opencode --prefix .
```

`--ai`와 `--agent`는 같은 옵션입니다.
지원 값: `all`, `claude`, `codex`, `opencode`.
(`--ai all`은 전체 에이전트 자산 전체를 설치합니다.)

### 설치 매핑 가이드

- Claude: `.claude/commands/specgate/*`
- Opencode: `.opencode/command/*`
- Codex + `--codex-target project`: `.codex/skills/specgate/*` (프로젝트 스코프)
- Codex + `--codex-target home`: `~/.codex/skills/specgate/*` (공유 스코프)
- `--ai claude,opencode`는 Claude와 Opencode 대상이 모두 설치됩니다.
- `--ai claude,opencode,codex`는 선택된 에이전트 대상이 모두 합쳐집니다.

### 로컬 클론에서 설치

```bash
/path/to/specgate/install.sh --preset claude --prefix .
```

## 4) 설치 옵션

```text
--prefix <경로>             설치 대상 디렉토리 (기본값: .)
--dry-run                   실행 계획만 출력, 실제 파일은 변경하지 않음
--force                     기존 파일 덮어쓰기 허용 (백업 파일 생성 없음)
--update                    변경된 파일만 갱신 (백업 파일 생성 없음)
--clean                     기존 SpecGate 설치 자산을 삭제하고 재설치
--version <이름>            브랜치/태그 지정 (기본값: main)
--preset <이름>             사전 정의된 설치 프리셋: claude | opencode | codex | codex-home | all
--ai <목록>                 설치할 에이전트 범위
--agent <목록>              --ai 별칭
--codex-target <project|home> Codex Agent Skills 설치 위치 (기본값: project)
--uninstall                 설치 대신 제거 모드로 동작
```

참고:

- install, uninstall, clean, update 동작 모두 백업 파일을 생성하지 않습니다.
- `--update`는 반복 실행해도 안전합니다. 변경되지 않은 파일은 건너뛰고 변경된 파일만 갱신됩니다.

### 예시

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --dry-run --preset codex --prefix .
```

```bash
# 깨진/일부로 남은 기존 설치를 초기 상태로 재설치
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --clean --preset claude --prefix .
```

```bash
# 변경 파일만 덮어쓰기
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --update --preset claude --prefix .
```

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --version v0.0.0 --prefix .
```

## 5) 제거

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --prefix .
```

`--uninstall`에서 `--ai` 또는 `--preset`를 생략하면 기본값 `all`로 모든 에이전트 항목을 제거합니다.
특정 에이전트만 제거:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --preset claude --prefix .
```

제거 확인(모든 SpecGate 자산):

```bash
[ ! -d .specify ] \
  && [ ! -d .claude/commands/specgate ] \
  && ( [ ! -f .claude/hooks/statusline.js ] || ! (grep -qF "# @specgate-managed:statusline" .claude/hooks/statusline.js || grep -qF "Claude Code Statusline - SpecGate Edition" .claude/hooks/statusline.js) ) \
  && [ ! -d .codex/skills/specgate ] \
  && [ ! -d .opencode/command ] \
  && [ ! -f docs/SPECGATE.md ] \
  && echo "SpecGate assets removed."
```

`statusline.js`는 다른 도구의 커스텀 스크립트일 수 있으므로, SpecGate가 설치한 파일로 판별되는 경우에만 삭제합니다.
`--update`도 `statusline.js`에 대해 SpecGate 소유 마커가 있는 경우에만 갱신합니다.

Codex 홈 스코프 설치를 해 둔 경우:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --preset codex-home --prefix .
```

```bash
[ ! -d ~/.codex/skills/specgate ] && echo "Codex home skills removed."
```

## 6) 설치 항목

- `.specify/*`
- `.claude/commands/specgate/*`
- `.claude/hooks/statusline.js`
- `.codex/skills/specgate/*` (프로젝트 설치: `.codex/skills/specgate`, 홈 설치: `~/.codex/skills/specgate`)
  - 워크플로우 전용 SKILL.md: `feature-set`, `specify`, `clarify`, `codify`, `checklist`, `analyze`, `test-specify`, `test-codify`, `taskstoissues`, `constitution`, `feature-done`
- `.opencode/command/*`
- `docs/SPECGATE.md`
- `.specify/scripts/bash/check-naming-policy.sh`
- `.specify/scripts/bash/run-feature-workflow-sequence.sh`

참고: `--ai codex`, `--ai claude` 등 단일 에이전트 설치 시(`--preset` 동등값: `codex`, `claude`)에도 `.specify` 및 `docs/SPECGATE.md`는 항상 함께 설치됩니다.

## 6) 일일 점검 가이드 (smoke check 대체)

운영 시 특성 기준 점검은 레포 루트에서 아래 시퀀스를 실행하세요.

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> --json
```

strict naming은 기본값입니다. 레거시 산출물 상태에서 임시로 우회하려면 다음을 사용하세요.

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> --json --no-strict-naming
```

## 6.1) 소비자 프로젝트 레벨 layer 정책 운영 (strict-layer 토글)

소비자 프로젝트에서 layer 규칙은 소비자 저장소 내부 `.specify/layer_rules`에서 해석됩니다.

- `.specify/layer_rules/contract.yaml`
- `.specify/layer_rules/overrides/<feature-id>.yaml` (필요 시)

첫 strict 실행 전 정책 파일을 초기화/동기화하세요.

```bash
bash .specify/scripts/bash/bootstrap-layer-rules.sh --repo-root . --feature-dir "<abs-feature-path>" --json
```

게이트 실행 전에 적용 정책을 먼저 확인하세요.

```bash
bash .specify/scripts/bash/load-layer-rules.sh --source-dir "<feature-path-or-file>" --json
```

`load-layer-rules.sh`는 YAML 블록 파싱을 위해 `PyYAML`(권장) 또는 `ruamel.yaml`이 Python 환경에 설치되어 있어야 하며, 둘 다 없으면 정책 파싱이 비신뢰 상태로 표시됩니다.

초기 실행 전 설치:

```bash
python3 -m pip install PyYAML
# 또는
python3 -m pip install ruamel.yaml
```

### `load-layer-rules.sh` 사용법

이 명령은 아래 소스의 layer 정책을 병합해 해석합니다.

- `.specify/layer_rules/contract.yaml` (전역)
- `.specify/layer_rules/overrides/<feature-id>.yaml` (feature override)
- `<feature>/docs/ARCHITECTURE.md`
- `<feature>/docs/architecture.md`
- `<feature>/docs/constitution.md`
- `<feature>/constitution.md`

`--source-dir`는 폴더와 파일 경로를 모두 받을 수 있습니다.

폴더를 넘기는 경우 아래 고정 파일만 확인하며 재귀 탐색하지 않습니다.

- `<source-dir>/docs/ARCHITECTURE.md`
- `<source-dir>/docs/architecture.md`
- `<source-dir>/docs/constitution.md`
- `<source-dir>/constitution.md`

파일을 넘기는 경우 해당 파일을 정책 소스로 직접 파싱합니다(예: `docs/ARCHITECTURE.md`).

`--repo-root`는 생략 가능하며, 생략 시 프로젝트 루트를 기본값으로 사용합니다.

`--source-dir`는 `architecture.md`/`constitution.md`를 읽을 정책 소스 경로이고, `--feature-id`는 오버라이드/캐시 파일명(`.specify/layer_rules/overrides/<feature-id>.yaml`, `.specify/layer_rules/resolved/<feature-id>.json`)에만 사용됩니다.

```bash
# 병합 정책 확인
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "<feature-path-or-file>" \
  --json

# 정책을 contract.yaml로 동기화
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "<feature-path-or-file>" \
  --write-contract \
  --json

# 기존 contract.yaml 강제 덮어쓰기
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "<feature-path-or-file>" \
  --write-contract \
  --force-contract \
  --json
```

필요한 경우 문서 기반 정책을 `contract.yaml`로 동기화하세요.

```bash
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "<feature-path-or-file>" \
  --write-contract \
  --json
```

직접 경로를 넣은 샘플:

```bash
bash .specify/scripts/bash/load-layer-rules.sh \
  --source-dir "./lib/src/features/home/docs/ARCHITECTURE.md" \
  --write-contract \
  --force-contract \
  --json
```

기존 문법(`--feature-dir`)도 호환되어 그대로 사용할 수 있습니다.

```bash
bash .specify/scripts/bash/load-layer-rules.sh --feature-dir "<feature-path-or-file>" --json
```

`contract.yaml`이 이미 존재하면 교체하려면 `--force-contract`를 추가하세요.

`load-layer-rules.sh`는 정책 조회/동기화 모두를 한 번에 처리하는 기본 경로입니다.
핵심 포인트:

- 병합 우선순위(contract/override/architecture/constitution) 확인 및 적용
- `--write-contract`로 병합 결과를 `contract.yaml` 동기화
- `--force-contract`로 기존 `contract.yaml` 갱신
- `contract_path` / `contract_written`로 실제 동기화 결과 확인

상세 사용법, 샘플 명령(architecture/feature 예시), 결과 필드 해석은
`docs/SPECGATE.md`의 `Layer governance` 섹션을 확인하세요.

- `source_kind` / `source_file` / `source_reason`: 최종 정책이 어디서 왔는지 확인
- `resolved_path`: 병합된 정책 JSON 경로
- `has_layer_rules`: strict 운영에서 `true`여야 함
- `applied_sources`: 계약/오버라이드/문서 기반 병합 이력
- `contract_path` / `contract_written`: `--write-contract`로 실제 저장된 경로/성공 여부
- `parse_events`: YAML/JSON 후보 파싱 시도/성공/실패의 머신 판독 이벤트
- `parse_summary`: 실패·성공·스키마 미스매치 카운트 집계
- `parse_summary`에서 `failed` 또는 `blocked_by_parser_missing` 값이 0보다 크면 strict 모드에서 하드 실패 게이트로 처리됩니다.

`source_kind` 예시:

- `CONTRACT`: 전역 contract.yaml 로드
- `OVERRIDE`: feature override 로드
- `CONSTITUTION` / `ARCHITECTURE`: feature 문서에서 추출
- `CONTRACT_GENERATED`: `--write-contract`로 병합 contract.yaml 생성
- `DEFAULT`: 사용 가능한 소스가 없어 기본값(권장: strict 모드에서 실패)

`strict-layer`는 기본적으로 비활성입니다(경고/리포트). 하드 실패가 필요하면 strict 모드로 실행하세요.

운영 모드(strict, 실패 강제 종료):

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir "<abs-feature-path>" --strict-layer --strict-naming --json
```

완화 모드(strict-layer 비활성, 위반은 경고/리포트만):

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir "<abs-feature-path>" --no-strict-layer --json
```

- `--strict-layer`: layer 규칙 미존재/위반 및 파서 실패가 하드 실패로 처리됩니다.
  - `parse_summary.failed > 0`, `parse_summary.blocked_by_parser_missing > 0` 조건이 해당됩니다.
- `--no-strict-layer`: layer 위반은 감지되더라도 시퀀스 자체는 통과합니다. 마이그레이션/레거시 정리 기간에만 임시 사용하세요.

코드 템플릿 재생성까지 같이 돌리려면 아래를 추가합니다.

```bash
bash .specify/scripts/bash/run-feature-workflow-sequence.sh --feature-dir <abs-feature-path> --json --setup-code
```

`specgate-smoke-check.sh`는 설치 검증(예: 신규 환경 확인)용으로는 유지되지만, 일일 반복 점검용으로는 권장되지 않습니다.

자세한 운영 가이드는 `docs/SPECGATE.md`를 확인하세요.

## 영문 버전

- [README.md](./README.md)
