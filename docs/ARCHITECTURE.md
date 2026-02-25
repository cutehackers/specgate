---
# Architecture

## Overview

This architecture uses a feature-based Clean Architecture layout with Riverpod AsyncNotifier.
Dependencies flow inward: `Presentation -> Domain <- Data`.

## Architecture Layers

- Presentation: `lib/src/features/<feature>/presentation/`
- Domain: `lib/src/features/<feature>/domain/`
- Data: `lib/src/features/<feature>/data/`
- Core: `lib/src/core/`

## Presentation

### Naming

- Page: `{Feature}Page`
- Controller: `{Feature}Controller`
- Event: `{Feature}{Action}Event`
- State: `{Feature}State`

### Rules

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

## Domain

### Naming

- Entity: `{Name}Entity`
- UseCase: `{Action}UseCase`
- Repository interface: `{Feature}Repository`

### Rules

- Do not import Presentation.
- Do not import Data implementations.
- Do not import repository_impl into use cases.

### Behavior and Errors

- Return type must be explicit for `call`.
- StateError is forbidden in Domain.
- Avoid raw `Exception` in Domain use cases.

## Data

### Naming

- DTO: `{Name}Dto`
- Data source: `{Feature}{Type}DataSource`
- Repository implementation: `{Feature}RepositoryImpl`
- Provider: `{featureName}{Type}Provider`

### Rules

- Do not import Presentation.
- Do not import Domain entities.

```dart
// ❌ WRONG: Data importing presentation code
import 'package:app/features/auth/presentation/auth_page.dart';

// ❌ WRONG: Data importing domain entities directly
import 'package:app/features/auth/domain/entities/user_entity.dart';
```

## Cross-cutting / Folder Rules

- Core utilities and abstractions live in `lib/src/core/`.
- No nested feature folders under `data`, `domain`, `presentation`.
- Allowed subfolders:
  - `data/models/`
  - `domain/entities/`
  - `presentation/widgets/`
- Never create empty directories.

## Naming Conventions (Examples)

- `{name}_entity.dart`
- `{action}_use_case.dart`
- `{name}_dto.dart`
- `{feature}_repository.dart`
- `{feature}_repository_impl.dart`
- `{feature}_data_source.dart`
- `{feature}_event.dart`
- `{feature}_controller.dart`

Forbidden generic names:

- `utils.dart`, `helpers.dart`
- `Util`, `Helper`, `Manager`

## Event Model

- Events are sealed and end with `Event`.
- Controllers expose dispatch-only API.
- Private handlers should be `_on` prefixed.

## Error and Async State

- Use `AsyncValue` to represent loading, data, and error.
- Do not define extra loading states in custom state classes.

## Optional machine-readable block

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
        - Exception
      require_result_type: true

behavior:
  use_case:
    allow_direct_repository_implementation_use: false
```
