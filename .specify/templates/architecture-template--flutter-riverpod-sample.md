# Flutter Clean Architecture (Inference-Ready Sample)

## Overview

This document is a template-compatible sample architecture for strict layer governance.

- Architecture follows `lib/src/features/<feature>/` feature-first structure.
- Dependency direction is inward: `Presentation -> Domain -> Data`.
- Naming and import restrictions are written in explicit prose so inference can extract them.

## Architecture Layers

- Presentation Layer (`lib/src/features/<feature>/presentation/`)
- Domain Layer (`lib/src/features/<feature>/domain/`)
- Data Layer (`lib/src/features/<feature>/data/`)
- Cross-cutting (`lib/src/core/`)

## Presentation Layer

### Naming

- Feature page: `{Feature}Page`
- Feature controller: `{Feature}Controller`
- Feature event: `{Feature}{Action}Event`
- Feature state: `{Feature}State`

### Layer rules

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

- Domain entity: `{Name}Entity`
- Use case: `{Action}UseCase`
- Repository interface: `{Feature}Repository`

### Layer rules

- Do not import Presentation.
- Do not import Data implementation.
- Do not import `repository_impl` into use cases.

### Behavior and errors

- Use case `call` methods must be explicit and typed.
- Avoid returning raw `Exception` in Domain.
- StateError is forbidden in Domain.

## Data Layer

### Naming

- DTO: `{Name}Dto`
- Data source: `{Feature}{Type}DataSource`
- Repository implementation: `{Feature}RepositoryImpl`
- Provider: `{featureName}{Type}Provider`

### Layer rules

- Do not import Presentation.
- Do not import Domain entities.
- Repository implementation should orchestrate DataSource + DTO mapping.

```dart
// ❌ WRONG: Data importing presentation code
import 'package:app/features/auth/presentation/auth_page.dart';

// ❌ WRONG: Data importing domain entities directly
import 'package:app/features/auth/domain/entities/user_entity.dart';
```

## Cross-cutting and folder rules

- Core code belongs under `lib/src/core/`.
- Do not create nested feature folders under `data`, `domain`, `presentation`.
- Allowed subfolders: `data/models`, `domain/entities`, `presentation/widgets`.

## Naming conventions

- File naming:
  - `{name}_entity.dart`
  - `{action}_use_case.dart`
  - `{name}_dto.dart`
  - `{feature}_repository.dart`
  - `{feature}_repository_impl.dart`
  - `{feature}_data_source.dart`
  - `{feature}_event.dart`
  - `{feature}_controller.dart`
- Forbidden generic naming: `utils.dart`, `helpers.dart`, `Util`, `Helper`, `Manager`.

## Event model

- Events are `sealed` and end with `Event`.
- Naming pattern: `{Feature}{Action}Event`.
- Controller public API should be `dispatch` only.
- Event handlers should be private `_on...` methods.

## Error and state handling

- Use `AsyncValue` transitions for async state.
- Do not mutate state outside controller boundary.

## Optional machine-readable block

```yaml
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
      - "^package:.*\\/data"
      - "^package:.*\\/presentation"
  data:
    forbid_import_patterns:
      - "^package:.*\\/presentation"
  presentation:
    forbid_import_patterns:
      - "^package:.*\\/data/.+_(dto|data_source|datasource|repository_impl)"
      - "^package:.*\\/domain/.+_(dto|entity)"

behavior:
  use_case:
    allow_direct_repository_implementation_use: false

errors:
  policy:
    domain_layer:
      forbid_exceptions:
        - StateError
        - Exception
      require_result_type: true
```
