# Architecture Template (Inference-Ready)

Use this file as a starting point for:
- `docs/ARCHITECTURE.md`
- `docs/architecture.md`
- `docs/constitution.md`
- `constitution.md`

This format is human-readable and optimized for inference by `load-layer-rules.sh`.

Write concrete project details in each section. Keep `Do not import ...` sentences explicit.

## Authoring guide for deterministic inference

Goal: make prose-only documents produce useful inference with `source_mode=INFERRED` and stable confidence.

### Step 1: Separate by layer first

- Keep clear sections such as `## Presentation layer`, `## Domain layer`, `## Data layer`.
- Put only layer-relevant rules under each section.

Recommended minimal shape:

```markdown
## Domain layer

- Do not import presentation layer.
- Do not import data layer.
```

### Step 2: Use high-signal phrases

- Use explicit prohibition sentences (`Do not import ...`) first; these give the strongest signal.
- Include bad examples with `bad import` / `WRONG` / `❌` markers for additional evidence.
- Add naming hints in backticks where possible.
- Add behavior/error constraints in plain text too (e.g., return type requirements).

Suggested confidence hints:

- Explicit prohibition sentence: `+0.25`
- Bad import example: `+0.15`
- Naming hint line: `+0.10`

### Step 3: Minimum inference set

- Per layer, include at least one prohibition for forbidden imports.
- Add at least one bad example line:

```markdown
- bad import "import 'package:app/features/auth/data/models/user_dto.dart'"
```

or

```dart
// ❌ WRONG
import 'package:app/features/auth/data/models/user_dto.dart';
```

- Add at least one behavior/error line:

```markdown
- Use case return type must be explicit.
- Controller events are `sealed` and dispatched via `dispatch`.
```

### Step 4: If confidence is low

If inference confidence drops below stable mode, strict-mode checks may warn or fail.
Improve by:

- adding more explicit section-level rules
- adding a few concrete bad examples
- adding errors/behavior notes
- optionally adding the optional `layer_rules` block

### Inference readiness checklist

- [ ] `Presentation`, `Domain`, `Data` sections exist
- [ ] At least one `Do not import ...` line per section
- [ ] At least one explicit bad import example (`bad import` / `WRONG` / `❌`)
- [ ] At least one naming hint (`{Action}UseCase`, `{Name}Entity`, etc.)
- [ ] At least one behavior/error sentence
- [ ] Optional machine-readable `layer_rules` block is added if you want deterministic parsing

## Overview

- Project structure: `lib/src/features/<feature>/` (feature-first)
- Layer dependency direction: `Presentation -> Domain -> Data`
- Keep shared infrastructure in `lib/src/core/`
- Keep layer boundaries explicit and small

## Architecture Layers

- **Presentation**: `lib/src/features/<feature>/presentation/`
- **Domain**: `lib/src/features/<feature>/domain/`
- **Data**: `lib/src/features/<feature>/data/`
- **Cross-cutting**: `lib/src/core/`

## Presentation Layer

### Naming

- Page: `{Feature}Page`
- Controller: `{Feature}Controller`
- Event: `{Feature}{Action}Event`
- State: `{Feature}State`
- Provider file: `{Feature}Providers`

### Layer Rules

- Do not import Data layer types in Presentation.
- Do not import Domain entities in Presentation.
- Do not import repository implementations in Presentation.
- Do not import DTOs directly from Data.

```dart
// ❌ WRONG: Presentation importing DTO
import 'package:app/features/auth/data/models/login_dto.dart';

// ❌ WRONG: Presentation importing repository implementation
import 'package:app/features/auth/data/auth_repository_impl.dart';
```

## Domain Layer

### Naming

- Entity: `{Name}Entity`
- UseCase: `{Action}UseCase`
- Repository interface: `{Feature}Repository`

### Layer Rules

- Do not import Presentation.
- Do not import Data implementation.
- Do not import repository implementations into Domain use cases.

### Errors and Behavior

- Use case return type must be explicit on call method.
- Avoid returning raw `Exception` in Domain.
- `StateError` is forbidden in Domain.

## Data Layer

### Naming

- DTO: `{Name}Dto`
- Data Source: `{Feature}{Type}DataSource`
- Repository implementation: `{Feature}RepositoryImpl`
- Provider: `{featureName}{Type}Provider`

### Layer Rules

- Do not import Presentation.
- Do not import Domain entities.
- Repository implementation must orchestrate DataSources and DTO ↔ Entity mapping.

```dart
// ❌ WRONG: Data importing presentation code
import 'package:app/features/auth/presentation/auth_page.dart';

// ❌ WRONG: Data importing domain entities directly
import 'package:app/features/auth/domain/entities/user_entity.dart';
```

## Cross-cutting and Folder Rules

- Core shared code lives under `lib/src/core/`.
- Do not create nested feature folders under `data/`, `domain/`, `presentation/`.
- Allowed subfolders only:
  - `data/models/`
  - `domain/entities/`
  - `presentation/widgets/`
- Never create empty directories.

## Naming Conventions

Use explicit names:

- `{name}_entity.dart`
- `{action}_use_case.dart`
- `{name}_dto.dart`
- `{feature}_repository.dart`
- `{feature}_repository_impl.dart`
- `{feature}_data_source.dart`
- `{feature}_event.dart`
- `{feature}_controller.dart`

Avoid generic names and aliases:

- `utils.dart`, `helpers.dart`
- `Util`, `Helper`, `Manager`
- vague abbreviations like `data`, `result` as standalone identifiers

## Errors and State Handling (Behavior)

### Async state

- Use `AsyncValue` transitions for async state management.
- Do not add custom loading states in custom state objects.

### Dispatch flow

- UI must call controller `dispatch`.
- Controllers expose private event handlers (e.g., `_onSignIn`) only.
- Events are `sealed` and end with `Event`.

## Optional Machine-Readable Block

If you want deterministic parsing, add this block (or equivalent) anywhere in this doc:

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
      - "^package:.*\\/data\\/"
      - "^package:.*\/presentation\/"
  data:
    forbid_import_patterns:
      - "^package:.*\/presentation\/"
  presentation:
    forbid_import_patterns:
      - "^package:.*\/data\/.+(dto|data_source|datasource|repository_impl)"
      - "^package:.*\/domain\/.+(dto|entity)"

errors:
  policy:
    domain_layer:
      forbid_exceptions:
        - StateError
        - Exception
      require_result_type: true

behavior:
  use_case:
    allow_direct_repository_implementation_use: false
```
