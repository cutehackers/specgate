# SpecGate README

## 한 줄 요약

`SpecGate`는 Flutter 프로젝트에서 Spec-Driven Development(SDD)용으로 설계된 **단일 흐름 워크플로우 엔진**입니다.

- 산출물: `spec.md -> clarify.md(선택) -> code.md -> test-spec.md`
- 포인터 FSM으로 단계/진행률 추적
- Claude / OpenCode / Codex 3개 에이전트에서 동일 규칙으로 동작
- 레거시 워크플로우(velospec/plan/tasks/tasks-test)는 **명령 표면 기준** 운영에서 제거됨
- Quick start: 아래 "30초 빠른 시작" 섹션을 참고하세요.

## 한눈에 보는 규칙

- 실행면에서 단일 네임스페이스: `SpecGate`
- 명령면에서 단일 흐름: `.claude/commands/specgate/*`, `.opencode/command/*`, `.codex/commands/specgate/*`
- 상태 추적: `specs/feature-stage.local.json` (초기 설치본은 미포함, 흐름 시작 시 생성/갱신됩니다)
- 진실원천: 구현 큐는 `code.md#code-tasks`, 테스트 큐는 `test-spec.md#test-code`

## 30초 빠른 시작

1. `/feature-set <feature-path>`
2. `/specify` (요구사항 작성)
3. `/clarify` (필요 시)
4. `/code` (실행/구현 큐 작성)
5. `/test-spec` (테스트 큐 작성)
6. `/test-write` (테스트 수행)
7. `/feature-done` (마무리)

단계 전/후에는 `specgate-sync-pointer.sh --preserve-stage` 또는 전환용 `--stage ...` 호출로 포인터를 동기화합니다.

`/specify` 재실행 시에도 기존 `spec.md`는 덮어쓰지 않고 idempotent하게 처리합니다.

## 실행자용 1페이지 가이드

### 0) 시작 전 확인
- `features/<feature>/specs` 또는 대상 feature 폴더로 이동한다.
- `.specify`가 있음을 확인한다.

### 1) 필수 실행 순서
1. `/feature-set <feature-path>`: 해당 feature를 포인터로 고정
2. `/specify`: `spec.md`/`quickstart.md`/체크리스트 뼈대 확보
3. `/clarify`: 모호성만 정제 (필요 시)
4. `/code`: `code.md` + `screen_abstraction.md` + P0/P1/P2 작업 정리
5. `/test-spec`: `test-spec.md`로 단일 실행 큐 구성
6. `/test-write`: `test-spec.md#test-code`만 실행 큐로 사용
7. `/feature-done`: 정리 항목(불필요 파일) 점검 후 완료

### 2) 각 단계 종료 규칙
- `/specify` 종료: `check-spec-prerequisites.sh` 통과
- `/code` 종료: P1 + `[P2][BLOCKING]` 모두 충족
- `/test-spec` 종료: 테스트 설계/매트릭스가 `test-spec.md`에 완성
- `/test-write` 종료: `/code` 파생 테스트를 실행 컨텍스트에 반영
- `/feature-done` 종료: 포인터 흐름상 마무리 상태

### 3) 즉시 실행해야 할 동기화
- 단계 경계 전/후: `specgate-sync-pointer.sh --preserve-stage --feature-dir "<abs path>"`
- 현재 단계 갱신만 필요한 경우: `specgate-sync-pointer.sh --feature-dir "<abs path>" --json`
- 상태 확인: `specgate-status.sh`

### 4) 실패/중단 시 복구
- `No SpecGate pointer found` 표시: `/feature-set`부터 다시 시작
- 포인터가 과거 단계로 보이면: 최근 단계 명령을 마지막으로 다시 실행하고 동기화를 재시도
- 중간 산출물 파손 의심 시: `/specify` → `spec.md` 재검토 후 `/code` 또는 `/test-spec` 재생성

### 5) 금지사항
- `legacy plan/tasks/tasks-test` 경로로의 명령 전환 금지
- `code.md`/`test-spec.md`에 구체 위젯 코드, 레이아웃, 애니메이션 지시 작성 금지
- `/feature-done` 전 임의 `clarify.md` 보강 금지(체크 대상만 관리)

## 포인터 동작 방식

포인터 파일: `specs/feature-stage.local.json`(초기 설치본은 미포함, `/feature-set` 실행 시 초기 생성됨)

```json
{
  "feature_dir": ".../lib/src/features/home",
  "feature_id": "plan_pal:lib/src/features/home",
  "status": "in_progress",
  "stage": "specifying|clarifying|coding|test_planning|test_writing|done|blocked",
  "current_doc": "spec.md|code.md|test-spec.md",
  "progress": {
    "code": { "done": 0, "total": 8 },
    "test": { "done": 0, "total": 4 }
  },
  "updated_at": "2026-02-18T11:53:08Z"
}
```

- `status`가 `done`이면 `done` 처리
- `code.md` 미완성(`done < total`)이면 `coding`
- `test-spec.md` 미완성이면 `test_writing`
- `code/test` 카운트는 `C###`, `TC###` 항목으로 계산해 동기화

---

## 설계 원칙

1. **단일진실원천(Single Source of Truth)**
   - 구현 큐: `code.md#code-tasks`
   - 테스트 큐: `test-spec.md#test-code`
   - 테스트 진행률: `test-spec.md#Execution Context`

2. **명확한 아티팩트 경계**
   - 항상 유지:
     - `spec.md`, `code.md`, `screen_abstraction.md`, `quickstart.md`, `checklists/*`
   - 조건부 유지:
     - `clarify.md`, `research.md`, `data-model.md`, `contracts/`, `test-spec.md`

3. **병렬 개발 우선 (Parallel Development)**
   - `contracts/`가 생성되면 `code.md`에 **Parallel Development & Mock Strategy**를 반드시 작성
   - mock 실행 명령, 계약 커버리지, 소비자 검증 경로를 명시해 백엔드 완료 전 병렬 구현 가능 상태를 보장

4. **Flutter/UI 정책(엄격)**
   - `code.md`와 `test-spec.md`에는 **구체 위젯/레이아웃/스타일/애니메이션 명령**을 작성하지 않음
   - 화면은 화면 계약 단에서만 다루고, 구현은 화면 상태/이벤트/결과(도메인 계약)로 제한

5. **명시적 네이밍 정책**
 - 모호한 명칭은 금지: `utils.dart`, `helpers.dart`, `Util`, `Helper`, `Manager`
 - 산출물(`spec.md`, `code.md`, `screen_abstraction.md`, `quickstart.md`)은
   `docs/ARCHITECTURE.md`의 네이밍 및 `Code Organization (Feature-First Structure)` 규칙을 준수해야 함
 - `Architecture Compliance`는 `docs/ARCHITECTURE.md`를 단일 진실원천(SSOT)으로 두고, feature
   폴더 구조 및 공통 제약(예: 금지명, 빈 디렉터리 금지, 최대 파일 길이)을 반영해야 함

6. **우선순위 규칙 (P1/P2/P3)**
   - `P1`: 핵심 필수 항목. 기본 가치 전달에 필요한 최소 기능.
   - `P2`: 출시 품질/운영 안정성에 필요한 주요 항목.
     - `P2-BLOCKING`: `P2` 중 다음 단계 이동을 막는 항목 (예: 저장 안정성, 권한/파손 회귀, 핵심 동기화/정합성 이슈).
     - `P2` 중에서 `P2-BLOCKING`이 아닌 항목은 backlog로 이관 가능.
   - `P3`: 선택 개선 항목. 기본 완료 조건에서 제외하고 요청 또는 여유가 있을 때 처리.

7. **완료 조건**
  - `/code` 완료: 모든 P1 완료 + 모든 `P2-BLOCKING` 완료.
    - `P2`(비차단) 항목은 요청/여유가 있을 때 남겨둘 수 있음.
  - 차단성은 `code.md` task line에서 `[P2][BLOCKING]` 패턴으로 명시.
  - `/test-write` 완료: `/code` 완료 파생 테스트와 블로킹 리스크 보정 반영.

8. **자동 추적 우선**
   - 단계 전이는 명령 실행 직전/직후 `specgate-sync-pointer.sh --preserve-stage`로 동기화
   - 작업 중단 시 다음 재개 지점이 즉시 복원되도록 유지

---

## 운영 명령(호출 순서)

Flat 명령형(짧은 명령)으로 통일합니다.

1. `/feature-set`
2. `/specify`
3. `/clarify` (선택)
4. `/code`
5. `/test-spec`
6. `/test-write`
7. `/feature-done`

> 실행 전제: 대상 feature는 pointer(`specs/feature-stage.local.json`) 기준으로 고정하고, 각 단계 전환 전/후에 포인터 동기화를 수행합니다.

### Phase-by-Phase 핵심 체크포인트

- **/specify**
  - `spec.md` 템플릿 충족 검사: `check-spec-prerequisites.sh`
  - `Feature ID`, `Architecture Compliance`, US/FR/AC/SC 완성성 확인
  - 동일 feature 재실행 시 `spec.md`는 덮어쓰지 않고 기존 내용을 보존

- **/clarify (선택)**
  - `spec.md#Clarifications`와 `clarify.md`(임시) 동기화
  - 질문 정책:
    - `/specify`: 사전 차단 이슈만 최대 3개까지 배치 질문
    - `/clarify`: 고영향 모호성 최대 5개까지 순차 질문(필요 시 반복 실행)

- **/code**
  - `code.md` 생성/갱신 후 `check-code-prerequisites.sh`
  - `screen_abstraction.md` 필수(필수 산출물 체크)
  - `contracts/` 존재 시 mock-server 전략(`## Parallel Development & Mock Strategy`)과 mock/contract 작업 항목 필수

- **/test-spec**
  - `test-spec.md`에서 테스트 매트릭스/컴포넌트 인벤토리/실행 큐 생성
  - `/code` 완료 조건: `check-implementation-readiness.sh`로 P1/P2-BLOCKING 충족 확인 후 전이
  - `check-test-prerequisites.sh`로 스키마 유효성 검증

- **/test-write**
  - `test-spec.md#test-code` 단일 큐 기반 실행
  - 테스트 진행률은 오직 `Execution Context`에 기록

- **/feature-done**
  - `clarify.md`, `research.md` 등의 삭제 후보 점검 후 마무리

---

## 포인터 FSM(자동 동기화)

포인터 파일: `specs/feature-stage.local.json`(초기 설치본은 미포함, `/feature-set` 실행 시 초기 생성됨)

```json
{
  "feature_dir": ".../lib/src/features/home",
  "stage": "specifying|clarifying|coding|test_planning|test_writing|done|blocked",
  "current_doc": "spec.md|code.md|test-spec.md",
  "progress": {
    "code": { "done": 0, "total": 8 },
    "test": { "done": 0, "total": 4 }
  }
}
```

### 사용 규칙

- 기본 규칙: 단계 전환은 명령 단계 경계에서 명시적으로 수행
  - 예: `/test-spec` 완료 후 `--stage test_planning`
- 일반 진행중 보조 확인은 `--preserve-stage --json`으로 progress 재계산
- 실패/중단 상황에서 다시 시작 시, pointer 값으로 다음 작업 문서와 미완료 task를 바로 찾음

### 상태 표시

- Claude: `/.claude/hooks/statusline.js`가 포인터를 읽어 모델 바에 `stage/current_doc` + `Cdone/total Tdone/total` 표시
- CLI: `.specify/scripts/bash/specgate-status.sh`

---

## 품질 게이트(권장 순서)

1. `check-spec-prerequisites.sh`
2. `check-code-prerequisites.sh`
3. `check-implementation-readiness.sh`
4. `check-implementation-quality.sh`
5. `check-test-prerequisites.sh`
6. `check-test-coverage-targets.sh`
7. `specgate-smoke-check.sh`

### 게이트 요약

- `check-spec-prerequisites.sh`
  - `spec.md` 섹션 존재/내용 유효성, edge case 개수, UI 구체 용어 탐지
- `check-code-prerequisites.sh`
  - `code.md` 필수 섹션 + concrete UI 금지 규칙 + contracts 존재 시 mock 전략/작업 강제
- `check-implementation-readiness.sh`
  - `code.md` 구현 큐(P1/P2/P2-BLOCKING) 완성 상태
- `check-test-prerequisites.sh`
  - `test-spec.md` 단일 큐 구조 확인
- `check-test-coverage-targets.sh`
  - `--allow-missing-lcov` 옵션 사용 시 초반 미측정 허용(경고 상태)으로 연속 작업 가능

---

## 운영 신뢰도(최신 상태)

- 레거시 명칭/아티팩트는 명령 표면에서 제거되어 오직 `SpecGate` 단일 흐름만 허용됩니다.
- test-spec 문서는 테스트 작업의 단일 소스(`test-spec.md#test-code`)로 정렬
- smoke-check 통과: 필수 파일, sync hook, 문법, 레거시 제거까지 점검
- 실행 권한/캐시 제약이 있는 환경에서는 `check-implementation-quality.sh --allow-tool-fallback` 사용 가능

---

## 신규 팀원을 위한 3분 진입

1. `/feature-set`로 feature 선정
2. `/specify`로 `spec.md` 기본체 작성
3. `/code`로 `code.md`+`screen_abstraction.md` 생성
4. `/test-spec`로 `test-spec.md` 생성
5. `/test-write`로 테스트 구현 시작

---

## 별도 저장소 분리(확장 계획 요약)

해당 분리 계획 문서는 설치형 레포에서는 제거되었으며, 설치 패키지는
`install.sh`와 설치 아티팩트만으로 운영됩니다.
