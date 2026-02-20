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

## 1) 빠른 시작

SpecGate 설치:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude --prefix .
```

설치 확인:

```bash
ls -la .specify .claude
```

선택한 에이전트에 맞는 폴더가 보이면 설치가 완료된 것입니다.
Codex는 각 워크플로우를 `.codex/skills/specgate/<workflow>/SKILL.md`로 직접 실행합니다.  
워크플로우 진행 중 사용자 입력이 필요하면 `AskUserQuestion`이 아닌 채팅에서 직접 질문하고 답변을 기다리세요.

## 2) 설치 방식

### 원격 설치 (단일 에이전트)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude --prefix .
```

### 에이전트별 단일 설치 가이드

공통으로 먼저 실행할 내용 (한 번만):

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
```

1) Claude만 설치

```bash
bash /tmp/specgate-install.sh --ai claude --prefix .
```

2) Opencode만 설치

```bash
bash /tmp/specgate-install.sh --ai opencode --prefix .
```

3) Codex 프로젝트 스코프 설치(기본)

```bash
bash /tmp/specgate-install.sh --ai codex --codex-target project --prefix .
```

4) Codex 홈 스코프 설치(공유)

```bash
bash /tmp/specgate-install.sh --ai codex --codex-target home --prefix .
```

`--ai`와 `--agent`는 같은 옵션입니다.
지원 값: `all`, `claude`, `codex`, `opencode`.
(`--ai all`은 전체 설치이므로 단일 설치 가이드는 따로 안내되지 않습니다.)

### 설치 매핑 가이드 (단일 에이전트)

- Claude: `.claude/commands/specgate/*`
- Opencode: `.opencode/command/*`
- Codex + `--codex-target project`: `.codex/skills/specgate/*`
- Codex + `--codex-target home`: `~/.codex/skills/specgate/*`


### 로컬 클론에서 설치

```bash
/path/to/specgate/install.sh --ai claude --prefix .
```

## 3) 설치 옵션

```text
--prefix <경로>             설치 대상 디렉토리 (기본값: .)
--dry-run                   실행 계획만 출력, 실제 파일은 변경하지 않음
--force                     기존 파일 덮어쓰기 허용
--version <이름>            브랜치/태그 지정 (기본값: main)
--ai <목록>                 설치할 에이전트 범위
--agent <목록>              --ai 별칭
--codex-target <project|home> Codex Agent Skills 설치 위치 (기본값: project)
--uninstall                 설치 대신 제거 모드로 동작
```

### 예시

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --dry-run --ai codex --codex-target project --prefix .
```

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --version v0.0.0 --prefix .
```

## 4) 제거

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --prefix .
```

`--uninstall`에서 `--ai`를 생략하면 기본값 `all`로 모든 에이전트 항목을 제거합니다.
특정 에이전트만 제거:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --ai claude --prefix .
```

제거 확인(모든 SpecGate 자산):

```bash
[ ! -d .specify ] \
  && [ ! -d .claude/commands/specgate ] \
  && [ ! -f .claude/hooks/statusline.js ] \
  && [ ! -d .codex/skills/specgate ] \
  && [ ! -d .opencode/command ] \
  && [ ! -f docs/SPECGATE.md ] \
  && echo "SpecGate assets removed."
```

Codex 홈 스코프 설치를 해 둔 경우:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --ai codex --codex-target home --prefix .
```

```bash
[ ! -d ~/.codex/skills/specgate ] && echo "Codex home skills removed."
```

## 5) 설치 항목

- `.specify/*`
- `.claude/commands/specgate/*`
- `.claude/hooks/statusline.js`
- `.codex/skills/specgate/*` (프로젝트 설치: `.codex/skills/specgate`, 홈 설치: `~/.codex/skills/specgate`)
  - 워크플로우 전용 SKILL.md: `feature-set`, `specify`, `clarify`, `codify`, `checklist`, `analyze`, `test-specify`, `test-codify`, `taskstoissues`, `constitution`, `feature-done`
- `.opencode/command/*`
- `docs/SPECGATE.md`

참고: `--ai codex`, `--ai claude` 등 단일 에이전트 설치시에도 `.specify` 및 `docs/SPECGATE.md`는 항상 함께 설치됩니다.

## 6) 일일 점검 가이드 (smoke check 대체)

레포 루트에서 다음을 실행하면 기본 점검이 가능합니다.

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

`specgate-smoke-check.sh`는 설치 검증(예: 신규 환경 확인)용으로는 유지되지만, 일일 반복 점검용으로는 권장되지 않습니다.

자세한 운영 가이드는 `docs/SPECGATE.md`를 확인하세요.

## 영문 버전

- [README.md](./README.md)
