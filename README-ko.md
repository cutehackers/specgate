# SpecGate

SpecGate는 Spec-Driven Development(SDD)용으로 사용할 수 있는 가볍고 독립적인 워크플로우 패키지입니다.  
Claude / OpenCode / Codex에서 공통으로 사용할 수 있는 명령 세트와 스크립트를 제공합니다.

이 저장소는 **클론 없이 바로 설치**하도록 설계되어 있으며, 프로젝트 루트에 바로 적용할 수 있습니다.

- 기본 설치 범위: `claude`, `codex`, `opencode` 모두
- 설치 기본 위치: 현재 프로젝트 루트(`.`)
- 제공되는 명령: `/feature-set`, `/specify`, `/clarify`, `/code`, `/test-spec`, `/test-write`, `/feature-done`

## 1) 빠른 시작

한 줄로 설치:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --prefix .
```

설치 확인:

```bash
ls -la .specify .claude .codex .opencode
```

선택한 에이전트에 맞는 폴더가 보이면 설치가 완료된 상태입니다.

## 2) 설치 방식 (원격)

모든 명령은 프로젝트 루트에서 실행하세요.

### 전체 설치 (기본)

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --prefix .
```

### 특정 에이전트만 설치

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --ai claude --prefix .
```

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --ai claude,opencode --prefix .
```

`--ai`와 `--agent`는 동일한 옵션입니다.  
지원 값: `all`, `claude`, `codex`, `opencode`.

### 로컬 클론에서 설치

```bash
/path/to/specgate/install.sh --prefix .
```

## 3) 설치 옵션

```text
--prefix <경로>    설치 대상 디렉토리 (기본값: .)
--dry-run          실행 계획만 출력, 실제 파일은 변경하지 않음
--force            기존 파일을 덮어쓰기 허용
--version <이름>   브랜치/태그 지정 (기본값: main)
--ai <목록>        설치할 에이전트 범위 지정
--agent <목록>     --ai의 별칭
--uninstall        제거 모드(설치가 아닌 삭제 수행)
```

예시:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --dry-run --ai codex --prefix .
```

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --version v0.0.0 --prefix .
```

## 4) 제거

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --uninstall --prefix .
```

특정 에이전트만 제거:

```bash
curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
  | bash -s -- --uninstall --ai claude --prefix .
```

## 5) 설치되는 파일

- `.specify/*`
- `.claude/commands/specgate/*`
- `.claude/hooks/statusline.js`
- `.codex/commands/specgate/*`
- `.opencode/command/*`
- `docs/SPECGATE.md`

## 6) 선택 실행 점검 (선택)

레포 루트에서 다음을 실행해 스크립트 문법과 기본 smoke check를 점검할 수 있습니다.

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

자세한 운영 방법은 `docs/SPECGATE.md`를 참고하세요.

## 영어 버전

- [README.md](./README.md)
