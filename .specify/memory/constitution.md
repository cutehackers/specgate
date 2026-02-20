<!--
SYNC IMPACT REPORT
==================
Version Change: 1.0.0 → 1.1.0
Rationale: Align constitution with PlanPal architecture standards from docs/ARCHITECTURE.md and CLAUDE.md. Refocus principles on cognitive clarity, clean architecture rigor, and feature-driven development.

Modified Principles:
- I. Code Quality & Standards → Updated to emphasize Clean Architecture, Feature-First structure, and Riverpod patterns
- II. Testing Discipline → Refined for Riverpod/AsyncNotifier testing patterns
- III. User Experience Consistency → Renamed from generic to reflect PlanPal's "Cognitive Calm" mission
- IV. Performance Requirements → Updated baseline (60fps for "Cognitive Calm")
- V. Flutter Architecture Standards → Completely revised to mandate event-driven AsyncNotifier, sealed events, and strict layer separation
- VI. Internationalization & Accessibility → Removed (out of scope for PlanPal Phase 1-3)

Added Sections:
- I.5 Clean Architecture Layer Compliance (new requirement)
- I.6 Riverpod Code Generation (new requirement)
- V.4 Event-Driven State Management (new requirement)
- Core Integrity Gates (new quality gate)

Removed Sections:
- VI. Internationalization & Accessibility (Phase 1 doesn't require i18n)

Templates Status:
- ✅ code-template.md - Reviewed, aligns with PlanPal architecture requirements
- ✅ spec-template.md - Reviewed, feature specs will follow Clean Architecture decomposition
- ℹ️  No command files found in .specify/templates/commands/

Follow-up TODOs:
- None
-->

# PlanPal Constitution

**Mission**: A cognitive safeguard designed to protect focus, respect energy, and turn chaotic to-dos into a Feasible Day.

## Core Principles

### I. Code Quality & Standards

All code MUST adhere to Dart/Flutter best practices and maintain consistent quality aligned with Clean Architecture principles:

1. **Static Analysis Compliance**
   - All code MUST pass `flutter analyze --fatal-infos` with zero issues
   - Code MUST NOT suppress lints without documented justification in Git history
   - Generated files (`*.g.dart`, `*.freezed.dart`, `*.gen.dart`) are exempt from analysis
   - Dart 3.x syntax required; prefer sealed classes, records, and extensions

2. **Dart Language Standards**
   - Use Dart 3.x syntax and features appropriately
   - Prefer `const` constructors wherever possible
   - Follow effective Dart guidelines: https://dart.dev/guides/language/effective-dart
   - Use null safety features correctly - no null assertions (!) without clear justification
   - Prefer composition over inheritance; use sealed classes for type-safe pattern matching

3. **Code Organization (Feature-First Structure)**
   - Follow feature-based folder structure: `lib/src/features/<feature>/{data,domain,presentation}/`
   - No nested feature folders under `data/`, `domain/`, or `presentation/`
   - Only allowed subfolders: `data/models/`, `domain/entities/`, `presentation/widgets/`
   - Never create empty directories; only create folders when files will occupy them
   - Maximum file length: 500 lines (split if exceeded; State exceeds 100 lines → separate file)
   - File naming: `snake_case.dart`; class naming: `PascalCase`

4. **Dependencies**
   - All dependencies declared in `pubspec.yaml` with version constraints
   - Document rationale for each direct dependency in pubspec comments
   - Prefer official Flutter packages over third-party alternatives
   - Future dependencies require architecture review (e.g., state management changes)

5. **Clean Architecture Layer Compliance**
   - Strict dependency inversion: dependencies flow inward (Presentation → Domain ← Data)
   - **Presentation** MUST NOT import from Data layer (DTOs, DataSources, RepositoryImpl)
   - **Domain** MUST NOT import Flutter UI packages, Data implementations, or Presentation
   - **Data** MUST NOT import Presentation layer
   - Core layer (`lib/src/core/`) contains shared utilities, base abstractions, and infrastructure only
   - Violations require explicit written justification in PR description with architectural rationale

6. **Riverpod Code Generation**
   - All providers MUST use `@riverpod` annotation (no manual `Provider` declarations)
   - All async operations MUST use Riverpod's `AsyncValue` (AsyncLoading, AsyncData, AsyncError)
   - Controllers MUST extend `EventControllerNotifier` from `lib/src/core/arch/event_controller.dart`
   - Code generation required: `dart run build_runner build --delete-conflicting-outputs`
   - PR description MUST note if `build_runner` changes are needed

**Rationale**: Clean Architecture with strict layer separation reduces bugs, improves testability, and enables safe refactoring. Riverpod's generated code ensures type safety and eliminates manual provider boilerplate. Feature-First organization scales naturally as PlanPal grows.

---

### II. Testing Discipline

Testing is NON-OPTIONAL for business logic and critical user flows:

1. **Test Coverage Requirements**
   - Unit tests REQUIRED for: business logic, use cases, repositories, state transformations
   - Widget tests REQUIRED for: custom widgets, complex UI interactions, page flows
   - Integration tests REQUIRED for: complete user journeys, data layer operations, voice processing
   - Minimum 70% code coverage for domain layer (business logic)
   - Use `flutter test --coverage` to verify; generate reports with `lcov`

2. **Test Structure & Patterns**
   - Place tests in `test/` directory mirroring `lib/src/` structure
   - Use `melos run test` for single package, `melos run test:all` for all
   - Use descriptive test names: `describeWhat_itShould_expectation` (e.g., `createTodo_withValidInput_returnsNewTodo`)
   - Follow AAA pattern: Arrange, Act, Assert
   - Mock external dependencies using `mocktail` or `mockito`

3. **Testing AsyncNotifier & Events**
   - Test event handlers by dispatching events and asserting state changes via `AsyncValue`
   - Verify initial state, loading state (AsyncLoading), success state (AsyncData), error state (AsyncError)
   - Use `AsyncValue.guard` in tests to catch exceptions properly
   - Mock repositories and use cases; inject via Riverpod `overrideWithValue`

4. **Test Data & Mocks**
   - Use mock data in `test/features/[feature]/mocks/` for complex test scenarios
   - Create factory functions or builders for common test objects (e.g., `createTestUser()`)
   - Avoid fragile selectors in widget tests; prefer `find.byKey`, `find.byType`, `find.text`
   - Use `mocktail` to mock Riverpod providers

**Rationale**: Flutter's hot reload enables rapid development, making tests crucial for preventing regressions. Riverpod tests verify both state transitions and event routing. High coverage in domain layer ensures business rules (energy-aware scheduling, anti-shame buffers) work correctly.

---

### III. Cognitive Clarity & User Experience

All features MUST deliver a cohesive, responsive user experience aligned with PlanPal's core mission: "Cognitive Calm":

1. **Cognitive Load Minimization**
   - Every feature MUST reduce user friction, not add to it
   - UI MUST provide immediate feedback (haptic or visual) for user actions
   - Voice interactions: no more than 3-step flows before actionable result
   - Loading indicators required for operations >300ms
   - Error messages MUST be actionable and empathetic (avoid technical jargon)

2. **Voice-First Design**
   - Voice entry interface MUST be screen-minimal (no-look capture capability)
   - Speech-to-text processing happens off-main-thread
   - Haptic feedback on voice start/stop/confirmation
   - Fallback to text entry always available but not primary
   - Voice retention: NEVER store raw audio longer than processing time

3. **Energy-Aware Scheduling** (Core to PlanPal)
   - Implement "Anti-Shame Buffers" for realistic time estimates (e.g., +15% buffer)
   - Scheduling MUST account for user energy patterns
   - Feature decisions document buffer logic with comments explaining scheduling rationale
   - UI shows feasibility warnings when overloaded (cognitive safeguard)

4. **Responsive & Accessible Design**
   - Support multiple screen sizes (phone, tablet)
   - Minimum touch target: 48x48dp
   - Test on smallest target device (iPhone SE size)
   - Semantic labels on all interactive widgets
   - Handle keyboard appearance gracefully (don't hide input fields)

5. **Visual Consistency**
   - Use shared theme configuration centrally
   - Spacing uses standardized padding/margin constants
   - Follow Material Design 3 guidelines for Flutter
   - Confirm destructive actions with dialogs

**Rationale**: PlanPal's mission is cognitive protection. Every design decision must reduce cognitive load and respect user attention. Voice-first reduces friction for busy professionals. Energy-aware scheduling prevents the planning fallacy. Accessibility ensures all users can benefit from cognitive safeguards.

---

### IV. Performance Requirements

Performance is a feature. The baseline is 60 FPS (required for "Cognitive Calm"):

1. **Frame Rate & Jank**
   - Maintain 60 FPS on mid-range devices (Android: Snapdragon 695+, iOS: A13+)
   - Eliminate jank in critical animations (e.g., voice input feedback, task transitions)
   - Use Flutter DevTools Performance overlay to identify issues before merging
   - Profile before optimizing; capture baseline metrics

2. **App Size**
   - Monitor app size impact for new dependencies
   - Use code splitting (defer loading) for non-critical features
   - Compress assets appropriately (images: WebP, fonts: WOFF2)
   - Remove unused assets and code before release

3. **Memory Management**
   - Dispose controllers, listeners, and subscriptions properly
   - Use `const` constructors to reduce widget tree rebuilds
   - Avoid memory leaks in StatefulWidget (use Riverpod instead for complex state)
   - Profile memory usage with DevTools Memory view
   - Monitor Drift database queries for N+1 problems

4. **Startup Time**
   - App first frame MUST render within 3 seconds on mid-range device
   - Minimize work in `main()` and `initState()`
   - Use lazy loading for non-critical features
   - Defer heavy computation (NLP parsing) until after first frame
   - Local database warm-up in background after first frame

5. **Voice Processing**
   - Speech-to-text processing happens off-main-thread
   - NLP parsing (if local) deferred with progress callback
   - UI remains responsive during voice capture and processing
   - Timeout audio recording after 60 seconds (configurable)

**Rationale**: Performance directly impacts user retention and cognitive experience. Slow, janky apps frustrate users and contradict the mission of "Cognitive Calm." These requirements ensure PlanPal feels responsive and professional.

---

### V. Clean Architecture & Event-Driven State Management

Follow established patterns for maintainable, testable architecture:

1. **Layer Responsibilities (Strict Separation)**
   - **Presentation**: Widgets, AsyncNotifier controllers, sealed events, providers; MUST NOT contain business logic
   - **Domain**: Entities, repository interfaces, use cases; pure Dart, framework-independent
   - **Data**: DTOs, data sources (remote/local), repository implementations; MUST NOT import Presentation
   - **Core**: Shared utilities (`EventControllerNotifier`, error handling, validators, networking)

2. **Event-Driven State Management (AsyncNotifier Pattern)**
   - Controllers extend `EventControllerNotifier<State, Event>` (from `lib/src/core/arch/event_controller.dart`)
   - Events are `sealed class`, named `{Feature}{Action}Event` (e.g., `AuthSignInEvent`, `TodoCreateEvent`)
   - Event handling via `onEvent(event) => switch(event) { ... }` with private `_on{Action}` handlers
   - UI dispatches events via `RefEventDispatcherX` extension: `ref.dispatch(provider, event)`
   - State updates via `AsyncValue.guard()` or explicit `AsyncLoading` → `AsyncData`/`AsyncError`
   - Never call controller methods directly from UI; always dispatch events

3. **Use Cases & Repository Pattern**
   - One action per use case file (`{action}_use_case.dart`)
   - Use case `call()` method receives typed params (use `Freezed` or value objects)
   - Repositories: interfaces in domain, implementations in data
   - Repository implementations orchestrate data sources and map DTO ↔ Entity
   - Use `Result<T>` or sealed types for error handling (no exceptions for domain errors)

4. **DTO ↔ Entity Mapping**
   - Conversion methods in DTO: `toEntity()` (DTO → Entity) and `fromEntity()` factory (Entity → DTO)
   - Entities MUST NOT import or know about DTOs
   - Mapping happens only in data layer (repository implementations)

5. **Naming Conventions (File & Class)**
   - Entities: `{Name}Entity` (e.g., `UserEntity`, `TodoEntity`)
   - DTOs: `{Name}Dto` (e.g., `UserDto`, `LoginResponseDto`)
   - Use Cases: `{Action}UseCase` (e.g., `LoginUseCase`, `CreateTodoUseCase`)
   - Repositories: `{Feature}Repository` (interface), `{Feature}RepositoryImpl` (implementation)
   - Controllers: `{Feature}Controller` (e.g., `AuthController`, `TodoController`)
   - Events: `{Feature}{Action}Event` (e.g., `AuthSignInEvent`, `TodoCreateEvent`)
   - Data Sources: `{Feature}{Type}DataSource` (e.g., `AuthRemoteDataSource`, `TodoLocalDataSource`)
   - Providers: Follow `@riverpod` naming: `{featureName}{Type}Provider` (auto-generated)

6. **Dependency Injection**
   - Use `@riverpod` for all providers (no manual Provider declarations)
   - Inject dependencies through provider graph (constructor injection via Riverpod)
   - Avoid singleton patterns except for app-level services (Dio, Drift database)
   - Make dependencies explicit and testable; mock via `overrideWithValue`

**Rationale**: Event-driven AsyncNotifier pattern with sealed events enables type-safe, traceable state changes. Strict layer separation keeps domain logic framework-independent and testable. Riverpod's code generation eliminates manual boilerplate and ensures type safety.

---

### VI. Naming & Code Documentation

Meaningful, explicit naming is a code quality requirement:

1. **Variable & Parameter Naming**
   - Be specific: `authenticatedUser` (not `user`), `activeTodoList` (not `list`)
   - No abbreviations unless universally known (e.g., `id`, `url`)
   - Boolean variables start with `is`, `has`, `can` (e.g., `isCompleted`, `hasError`)
   - Descriptive event field names: `todoTitle`, `todoDescription` (not `title`, `desc`)

2. **Generic Names Prohibited**
   - ❌ Avoid: `utils.dart`, `helpers.dart`, `Util`, `Helper`, `Manager`
   - ✅ Use: `email_validator.dart`, `date_formatter.dart`, `network_error_handler.dart`

3. **Documentation & Comments**
   - Public APIs MUST have dartdoc comments (three slashes: `///`)
   - Code comments explain _why_, not _what_ (e.g., "Added 15% buffer to prevent scheduling conflicts")
   - Complex logic MUST include cognitive load comments explaining design decisions
   - Document non-obvious Riverpod patterns (e.g., why a provider uses `.family` or `.keepAlive`)

**Rationale**: Clear naming reduces cognitive load and makes code self-documenting. PlanPal's mission is cognitive clarity; this extends to code clarity. Well-named variables and functions are easier to test, refactor, and onboard new developers.

---

## Quality Gates

All features MUST pass these gates before merging:

1. **Architecture Gate**
   - No layer boundary violations (Presentation importing Data, Domain importing UI, etc.)
   - All providers use `@riverpod` annotation
   - All state changes flow through events and AsyncNotifier
   - Use case parameters are typed (no `Map<String, dynamic>`)
   - Clean separation: DTO ↔ Entity mapping in data layer only

2. **Code Review Gate**
   - At least one approval required
   - All constitution checks must pass (documented in PR template)
   - No unresolved conversations
   - PR description references feature spec and architectural decisions (if non-obvious)
   - `build_runner` changes noted if code generation was needed

3. **Testing Gate**
   - All new tests pass
   - No regressions in existing tests
   - Coverage ≥70% for domain layer (business logic)
   - Event handlers tested by dispatching and asserting state changes
   - Integration tests pass for critical user flows

4. **Performance Gate**
   - No new performance regressions (60 FPS baseline)
   - DevTools shows smooth animations in critical flows
   - App startup time within acceptable limits (<3s first frame)
   - Memory usage stable (no leaks); Drift queries optimized

5. **UX Consistency Gate**
   - Voice interactions are screen-minimal (where applicable)
   - Loading/error states handled (AsyncLoading, AsyncError displayed)
   - Haptic feedback for user actions
   - Responsive design tested on multiple screen sizes
   - Accessibility: 48x48dp touch targets, semantic labels present

---

## Development Workflow

1. **Feature Development**
   - Create feature branch from `main` following pattern: `<phase>-<feature-name>` (e.g., `001-ai-daily-briefing`)
   - Implement using clean architecture; test-driven approach when feasible
   - Run `flutter analyze --fatal-infos` and `flutter test` before committing
   - Commit messages describe _why_, not _what_ (e.g., "Add energy-aware scheduling to respect user capacity")

2. **Code Review Process**
   - Self-review: verify architecture compliance, naming conventions, test coverage
   - Request review from team; address all feedback
   - Squash commits to logical units (one feature = one logical commit)
   - Document non-obvious architectural decisions in PR

3. **Build & Release**
   - Development: `flutter run -d <device>`
   - Release build: `flutter build apk/ios --release`
   - Test app startup time, memory, and 60 FPS performance before release
   - Monitor Drift database performance in production

4. **Code Generation**
   - Run `dart run build_runner build --delete-conflicting-outputs` after:
     - Adding new `@riverpod` providers
     - Modifying `@freezed` classes
     - Updating `@JsonSerializable` DTOs
   - Commit generated files (`.g.dart`, `.freezed.dart`)
   - PR must note if code generation is needed

---

## SpecGate Workflow Governance

Spec-driven delivery in this repository MUST follow the `SpecGate` workflow:

1. **Workflow Identity & Command Model**
   - Official workflow name is `SpecGate`.
   - Flat command UX is required: `/specify -> /clarify -> /codify -> /test-specify -> /test-codify`.
   - Compatibility aliases are not allowed in operational flow; use `SpecGate` only.

   2. **Required Feature Maintenance Artifacts**
   - Mandatory artifacts for each feature:
     - `spec.md`, `research.md`, `screen_abstraction.md`, `data-model.md`, `quickstart.md`, `tasks.md`, `checklists/*`
   - Conditional artifacts must be created when applicable:
     - `contracts/`, `test-spec.md`

3. **Spec/Test Schema Gates**
   - Planning must not proceed if required `spec.md` sections are missing.
   - Test execution must not proceed if required `test-spec.md` sections are missing.
   - Required test execution interfaces are:
     - `test-spec.md#test-code`
     - `test-spec.md#Execution Context`

4. **Test Tracking Source of Truth**
   - `test-spec.md` is the single source of truth for test execution order and progress.
- Standalone test task artifact files are removed; only `test-spec.md` is required for active
  test execution.

5. **Testing Standards Fallback**
   - Primary testing policy source: `docs/TESTING_STANDARDS.md`.
   - If unavailable, enforce testing rules from this constitution until standards doc is present.

6. **Feature Completion Cleanup**
   - Preserve mandatory maintenance artifacts at feature completion.
   - Temporary intermediate docs may be archived or removed with explicit note in `feature-done` output.

---

## Governance

### Amendment Process

1. Proposals MUST include rationale and impact analysis
2. Team discussion and consensus required
3. Update version following semantic versioning
4. Update all dependent templates (`spec-template.md`, `clarify-template.md`, `code-template.md`, `test-spec-template.md`, and related checklists/screen abstraction templates)
5. Communicate changes to team

### Versioning

- **MAJOR**: Principle removal or backward-incompatible architectural changes
- **MINOR**: New principle/section added or materially expanded guidance
- **PATCH**: Clarification, typo fixes, non-semantic changes

### Compliance

- All PRs MUST verify constitution compliance
- Architecture violations require explicit justification with rationale
- Use this constitution as the source of truth for disputes
- Regular review cadence: quarterly or after major architectural additions

### Living Document

This constitution evolves with PlanPal. It reflects the current phase and may be amended as the project grows. Suggestions welcome via team discussion.

---

**Version**: 1.2.0 | **Ratified**: 2026-01-29 | **Last Amended**: 2026-02-18
