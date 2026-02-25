# Code Specification: [FEATURE NAME]

## Metadata

- **Feature Directory**: `/path/to/feature`
- **Feature ID**: `package_name:relative/feature/path`
- **Created**: [DATE]
- **Updated**: [DATE]
- **Spec Source**: `<feature_dir>/docs/spec.md`
- **Architecture Baseline**: `docs/ARCHITECTURE.md`
- **Naming Source**: `<resolved docs/ARCHITECTURE.md or constitution path>`
- **Layer Rules Source**: {{LAYER_RULES_SOURCE}}
- **Naming Policy Rules**: <{{NAMING_RULES}}>
- **Layer Rules Source Kind**: {{LAYER_RULES_SOURCE_KIND}}
- **Layer Rules Source File**: {{LAYER_RULES_SOURCE_FILE}}
- **Layer Rules Source Reason**: {{LAYER_RULES_SOURCE_REASON}}
- **Layer Rules Resolved Path**: {{LAYER_RULES_RESOLVED_PATH}}
- **Layer Rules Present**: {{LAYER_RULES_HAS_LAYER_RULES}}
- **Layer Rules Summary**:
{{LAYER_RULES_SUMMARY}}

> Use `NAMING_SOURCE_FILE` from a machine-readable `json` code block in
> `docs/ARCHITECTURE.md`/`docs/architecture.md` or constitution.

## Summary

[One paragraph: what will be implemented and why.]

## Technical Context

- **Language/Version**: [Dart/Flutter version]
- **Primary Dependencies**: [riverpod, drift, etc.]
- **Storage**: [local-first persistence strategy]
- **Testing Baseline**: `docs/TESTING_STANDARDS.md` or `.specify/memory/constitution.md`
- **Constraints**: [performance/privacy/platform constraints]

## Architecture Compliance

| Check | Status (PASS/OPEN) | Notes |
|------|---------------------|-------|
| Clean architecture dependency direction | [PASS/OPEN] | [note] |
| Domain framework-agnostic | [PASS/OPEN] | [note] |
| Riverpod state boundary clarity | [PASS/OPEN] | [note] |
| Presentation abstraction-only policy | [PASS/OPEN] | [note] |
| `layer_rules` policy source present and valid | [PASS/OPEN] | [note] |
| Entity naming rule from resolved naming source (`{{ENTITY_SUFFIX}}`) | [PASS/OPEN] | [note] |
| DTO naming rule from resolved naming source (`{{DTO_SUFFIX}}`) | [PASS/OPEN] | [note] |
| Use Case naming rule from resolved naming source (`{{USE_CASE_SUFFIX}}`) | [PASS/OPEN] | [note] |
| Repository naming rule from resolved naming source (`{{REPOSITORY_SUFFIX}}`) | [PASS/OPEN] | [note] |
| Repository Impl naming rule from resolved naming source (`{{REPOSITORY_IMPL_SUFFIX}}`) | [PASS/OPEN] | [note] |
| Event naming rule from resolved naming source (`{{EVENT_SUFFIX}}`) | [PASS/OPEN] | [note] |
| Controller naming rule from resolved naming source (`{{CONTROLLER_SUFFIX}}`) | [PASS/OPEN] | [note] |
| Data Source naming rule from resolved naming source (`{{DATA_SOURCE_SUFFIX}}`) | [PASS/OPEN] | [note] |
| Provider naming rule from resolved naming source (`{{PROVIDER_SUFFIX}}`) | [PASS/OPEN] | [note] |
| Generic naming ambiguity policy (`utils.dart`, `helpers.dart`, `Util`, `Helper`, `Manager`) | [PASS/OPEN] | [note] |

## Screen Abstraction Contract

> This section is mandatory. Screen/page concrete implementation details are forbidden.

### Contract Rules

- Define only `input`, `event`, `ui_state`, `output`, `error_state`.
- Do not include concrete layout, styling, animation, or widget-tree instructions.
- Keep `presentation/screens` and `presentation/widgets` at state-manager binding level only.

### Screen Map

| Screen ID | Story IDs | Inputs | Events | UI States | Outputs | Error States |
|-----------|-----------|--------|--------|-----------|---------|--------------|
| [SCREEN_ID] | [US-001] | [inputs] | [events] | [states] | [outputs] | [errors] |

## Artifacts

- `screen_abstraction.md`
- `quickstart.md`
- `data-model.md`
- `contracts/` (if applicable)
- `contracts/mock/` or equivalent mock definition (required when `contracts/` exists)
- `test-spec.md` (if test planning is required)

## Parallel Development & Mock Strategy

- **Contracts Present**: [YES/NO]
- **Mock Server Approach**: [tooling/runner or internal adapter strategy]
- **Startup Command**: [command or N/A]
- **Contract Coverage**: [which contract files/endpoints are mocked]
- **Consumer Validation Plan**: [how clients validate against mock before backend integration]
- **Handoff Criteria**: [conditions to replace mock with real integration]

## code-tasks

> Single execution queue for implementation.
>
> Required format:
> - `- [ ] C### [P1|P2|P3] [story-or-layer] [scope] Description`
> - For blocking P2 tasks, append `[BLOCKING]` after priority: `[P2][BLOCKING]`.
> - Example: `- [ ] C001 [P2][BLOCKING] [Presentation] [US-001] [NEW] ...`

- [ ] C001 [P1] [Domain] [US-001] [NEW] [path]
- [ ] C002 [P1] [Data] [US-001] [NEW] [path]
- [ ] C003 [P1] [Presentation] [US-001] [NEW] [path]
- [ ] C004 [P1] [Contracts] [US-001] [NEW] Define contract-backed mock workflow and startup command
- [ ] C005 [P2][BLOCKING] [Validation] [VERIFY] Run `.specify/scripts/bash/check-implementation-quality.sh --feature-dir "<abs path>" --json`

## Execution Context

- **Total**: [N]
- **Pending**: [N]  <!-- count excludes Blocked -->
- **In Progress**: [N]
- **Done**: [N]
- **Blocked**: [N]
- **Next Task**: [C###]
- **Last Updated**: [UTC timestamp]

## Validation Commands

```bash
dart format --output=none --set-exit-if-changed lib/src/features/<feature>
flutter analyze
flutter test --no-pub
flutter test --coverage --no-pub
.specify/scripts/bash/check-implementation-quality.sh --feature-dir "<abs path>" --json
```

## Cleanup Policy

- Keep: `spec.md`, `tasks.md`, `screen_abstraction.md`, `quickstart.md`, `checklists/*`, `test-spec.md` (if exists)
- Removable at `feature-done`: `clarify.md`, `research.md`, temporary analysis notes
