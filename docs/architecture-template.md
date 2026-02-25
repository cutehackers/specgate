# Architecture Template (Inference-Ready)

이 문서는 `docs/ARCHITECTURE.md` 작성용 템플릿입니다.
다음 규칙을 지키면 `load-layer-rules.sh`가 인간이 읽기 좋은 문서에서 바로 정책을 추론합니다.

## 사용자 작성 가이드 (인퍼런스 신뢰도 최적화)

목표: 인퍼런스가 안정적으로 동작하도록 `source_mode=INFERRED`로도 `confidence >= 0.75`을 얻는 것.

### Step 1) 레이어 섹션을 명확히 나누기

- 최상단에 `## Presentation layer`, `## Domain layer`, `## Data layer`를 분리해 작성
- 각 섹션 안에서 해당 레이어의 위반 규칙을 명시
- 같은 의미를 반복할 필요가 없을 경우, 이미 명확한 핵심 규칙만 1~2개 정도 작성

권장 형식:

```markdown
## Domain layer

- Do not import presentation layer.
- Do not import data layer.
- Do not import repository_impl.
```

### Step 2) 신호(정확도 가중치)가 높은 문장을 사용

- `Do not import ...` 형태의 명시적 문장을 1개 이상 넣으세요.
- 코드 블록에서 잘못된 예시를 함께 넣으면 정확도가 더 높습니다.
- 네이밍 규칙은 백틱 텍스트를 사용해 적어 주세요.
- 에러/행동 제약도 텍스트로 함께 넣으면 추가 근거가 쌓입니다.

신뢰도 가중치(추천 기준):

- `Do not import ...` : +0.25
- `bad import "... import ..."` / `WRONG` 예시 : +0.15
- 네이밍 힌트 : +0.10

### Step 3) 인퍼런스용 최소 샘플 패턴

- 레이어 금지 규칙(각 레이어 최소 1개)
  - `- Do not import data layer.`
  - `- Do not import presentation layer.`
- 명시적 bad import 예시(권장)

```markdown
- bad import "import 'package:app/features/auth/data/models/user_dto.dart'"
```

또는 코드 블록 안에서:

```dart
// ❌ WRONG
import 'package:app/features/auth/data/models/user_dto.dart';
```

- 네이밍/동작 규칙

```markdown
- Use case naming rule: `{Action}UseCase`
- Domain return type must be explicit.
- UI events are `sealed` and end with `Event`.
```

### Step 4) 신뢰도가 낮을 때 자동 대응

- 하나의 규칙 문구만 있고 근거가 적으면 낮은 신뢰도로 계산되어 strict에서 경고/실패할 수 있습니다.
- 아래 보강하면 자동 파싱 실패를 피합니다.
  - 레이어별 2개 이상 `Do not import ...` 문장
  - bad import 예시 1개 이상
  - errors/behavior 텍스트 1개 이상
  - 가능하면 Optional `layer_rules` 블록도 함께 추가

### 인퍼런스 최종점검 체크리스트

- [ ] `docs/ARCHITECTURE.md`에 Presentation/Domain/Data 섹션이 있음
- [ ] 각 섹션에 1개 이상 `Do not import ...` 규칙이 있음
- [ ] `bad import` 또는 `WRONG` 예시가 있음
- [ ] 네이밍 힌트(예: `{Action}UseCase`)가 1개 이상 있음
- [ ] `AsyncValue`, `sealed Event`, `dispatch` 관련 행동 규칙이 명시됨
- [ ] Optional machine-readable 블록이 있거나 문장 기반 규칙이 충분히 있음

## 핵심 원칙

- Feature-first 구조: `lib/src/features/<feature>/`
- 레이어 방향: `Presentation -> Domain -> Data`
- 코어 공용 코드는 `lib/src/core/`

## Layer Overview

- Presentation: `lib/src/features/<feature>/presentation/`
- Domain: `lib/src/features/<feature>/domain/`
- Data: `lib/src/features/<feature>/data/`

## Presentation Layer

### Naming

- `{Feature}Page`
- `{Feature}Controller`
- `{Feature}{Action}Event`
- `{Feature}State`

### Layer Rules

- Do not import Data layer types in Presentation.
- Do not import Domain entities in Presentation.
- Do not import repository implementations in Presentation.
- Do not import DTOs directly from Data.

```dart
// ❌ WRONG: Presentation importing Data DTO
import 'package:app/features/auth/data/models/login_dto.dart';

// ❌ WRONG: Presentation importing repository implementation
import 'package:app/features/auth/data/auth_repository_impl.dart';
```

## Domain Layer

### Naming

- `{Name}Entity`
- `{Action}UseCase`
- `{Feature}Repository`

### Layer Rules

- Do not import Presentation.
- Do not import Data implementations.
- Do not import repository implementations into use cases.

### Errors / Behavior

- Domain use case return type must be explicit.
- `StateError` must not be used.
- Avoid returning raw `Exception` in Domain.

## Data Layer

### Naming

- `{Name}Dto`
- `{Feature}{Type}DataSource`
- `{Feature}RepositoryImpl`
- `{featureName}{Type}Provider`

### Layer Rules

- Do not import Presentation.
- Do not import Domain entities.

```dart
// ❌ WRONG: Data importing presentation code
import 'package:app/features/auth/presentation/auth_page.dart';

// ❌ WRONG: Data importing domain entities directly
import 'package:app/features/auth/domain/entities/user_entity.dart';
```

## Cross-cutting & Folder Rules

- Core shared code: `lib/src/core/`
- Do not create nested feature folders inside `data/`, `domain/`, `presentation/`.
- Allowed subfolders: `data/models/`, `domain/entities/`, `presentation/widgets/`.

## Name Conventions

- `{name}_entity.dart`
- `{action}_use_case.dart`
- `{name}_dto.dart`
- `{feature}_repository.dart`
- `{feature}_repository_impl.dart`
- `{feature}_data_source.dart`
- `{feature}_event.dart`
- `{feature}_controller.dart`

## Behavior

- 이벤트는 `sealed`로 정의하고 이름은 `...Event`로 끝냅니다.
- 컨트롤러는 `dispatch` API를 통해서만 바깥에서 호출되며 핸들러는 `_on...` 형태를 사용합니다.

## Optional Block (recommended)

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
    forbid_import_patterns:
      - "^package:.*\/data\/"
      - "^package:.*\/presentation\/"
  data:
    forbid_import_patterns:
      - "^package:.*\/presentation\/"
  presentation:
    forbid_import_patterns:
      - "^package:.*\/data\/.+(dto|entity|data_source|datasource|repository_impl)"
      - "^package:.*\/domain\/.+(dto|entity)"

errors:
  policy:
    domain_layer:
      forbid_exceptions:
        - StateError
      require_result_type: true

behavior:
  use_case:
    allow_direct_repository_implementation_use: false
```
