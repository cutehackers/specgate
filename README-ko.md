# SpecGate

SpecGate는 Spec-Driven Development(SDD)를 위한 가벼운 워크플로우 패키지입니다.  
Claude, OpenCode, Codex에서 사용할 수 있는 명령과 스크립트를 제공합니다.

이 저장소는 프로젝트에 클론 없이 바로 설치할 수 있습니다.

- 기본 설치 경로: 현재 디렉토리(`.`)
- 기본 설치 범위: 전체 에이전트(`claude`, `codex`, `opencode`)
- 실행 명령: `/feature-set`, `/specify`, `/clarify`, `/codify`, `/test-specify`, `/test-codify`, `/feature-done`

## 1) 빠른 시작

SpecGate 설치:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --prefix .
```

설치 확인:

```bash
ls -la .specify .claude .codex .opencode
```

선택한 에이전트에 맞는 폴더가 보이면 설치가 완료된 것입니다.

## 2) 설치 방식

### 기본 설치 (전체)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --prefix .
```

### 특정 에이전트 설치

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude --prefix .
```

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --ai claude,opencode --prefix .
```

`--ai`와 `--agent`는 같은 옵션입니다.  
지원 값: `all`, `claude`, `codex`, `opencode`.

### 로컬 클론에서 설치

```bash
/path/to/specgate/install.sh --prefix .
```

## 3) 설치 옵션

```text
--prefix <경로>     설치 대상 디렉토리 (기본값: .)
--dry-run           실행 계획만 출력, 실제 파일은 변경하지 않음
--force             기존 파일 덮어쓰기 허용
--version <이름>    브랜치/태그 지정 (기본값: main)
--ai <목록>         설치할 에이전트 범위
--agent <목록>      --ai 별칭
--uninstall         설치 대신 제거 모드로 동작
```

### 예시

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --dry-run --ai codex --prefix .
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

특정 에이전트만 제거:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh -o /tmp/specgate-install.sh
bash /tmp/specgate-install.sh --uninstall --ai claude --prefix .
```

## 5) 설치 항목

- `.specify/*`
- `.claude/commands/specgate/*`
- `.claude/hooks/statusline.js`
- `.codex/commands/specgate/*`
- `.opencode/command/*`
- `docs/SPECGATE.md`

## 6) 선택 점검

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
  .specify/scripts/bash/specgate-smoke-check.sh \
  .specify/scripts/bash/setup-code.sh \
  .specify/scripts/bash/setup-test-spec.sh

./.specify/scripts/bash/specgate-smoke-check.sh
```

자세한 운영 가이드는 `docs/SPECGATE.md`를 확인하세요.

## 영문 버전

- [README.md](./README.md)
