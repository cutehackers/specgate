# Test Spec: [FEATURE NAME]

## Metadata

- **Feature Directory**: `/path/to/feature`
- **Feature ID**: `package_name:relative/feature/path`
- **Created**: [DATE]
- **Updated**: [DATE]
- **Spec**: `<feature_dir>/docs/spec.md`
- **Code Spec**: `<feature_dir>/docs/code.md`
- **Architecture Baseline**: `docs/ARCHITECTURE.md`
- **Testing Baseline**: `docs/TESTING_STANDARDS.md` (fallback: `.specify/memory/constitution.md`)

## Summary

[Summarize core testing goals and scope for this feature.]

## Test Strategy

- **Primary Focus**: [risk-first test strategy]
- **Test Types**: [unit/widget/integration]
- **Execution Scope**: [full feature or delta mode]
- **Coverage Policy Source**: [standards/constitution]

## Test Component Inventory

| Test ID | Component | Layer | Source File | Test File | Coverage Target | Existing Status | Change Status | Dependencies |
|---------|-----------|-------|-------------|-----------|-----------------|-----------------|---------------|--------------|
| TC001 | [component] | Domain | lib/... | test/... | 100% | MISSING/PARTIAL/COMPLETE/LEGACY | NEW/MODIFIED/UNCHANGED | [ids] |
| TC002 | [component] | Data | lib/... | test/... | 95% | MISSING/PARTIAL/COMPLETE/LEGACY | NEW/MODIFIED/UNCHANGED | [ids] |
| TC003 | [component] | Presentation | lib/... | test/... | 80% | MISSING/PARTIAL/COMPLETE/LEGACY | NEW/MODIFIED/UNCHANGED | [ids] |

## Test Matrix

| Story | Scenario | Components | Test IDs | Priority |
|------|----------|------------|----------|----------|
| US-001 | [happy path] | [component list] | [TC001, TC002] | P1 |
| US-001 | [error/recovery] | [component list] | [TC003] | P1 |
| US-002 | [alternate path] | [component list] | [TC004] | P2 |

## test-code

> This section is the single execution source for `/test-codify`.

### Phase 0: Infrastructure

- [ ] TC001 [Infra] [NEW] Create/refresh co-located `mocks.dart` for [component] at `test/.../mocks.dart`
- [ ] TC002 [Infra] [NEW] Create/refresh co-located `test_data.dart` for [component] at `test/.../test_data.dart`
- [ ] TC003 [Infra] [VERIFY] Run mock generation command for affected package roots

### Phase 1: Domain

- [ ] TC101 [Domain] [NEW] Add tests for [entity/use case] in `test/...`
- [ ] TC102 [Domain] [UPDATE] Add edge/error path tests for [entity/use case] in `test/...`

### Phase 2: Data

- [ ] TC201 [Data] [NEW] Add repository/data-source tests for [component] in `test/...`
- [ ] TC202 [Data] [REGRESSION] Verify mapping and failure handling for [component] in `test/...`

### Phase 3: Presentation

- [ ] TC301 [Presentation] [NEW] Add controller state transition tests for [component] in `test/...`
- [ ] TC302 [Presentation] [UPDATE] Add recovery/offline/error path tests for [component] in `test/...`

### Phase 4: Integration

- [ ] TC401 [Integration] [NEW] Add critical flow test for [flow] in `test/integration/...`
- [ ] TC402 [Integration] [REGRESSION] Validate modified flow behavior for [flow] in `test/integration/...`

### Phase 5: Validation

- [ ] TC501 [Validation] [VERIFY] Run scoped test suite for affected packages
- [ ] TC502 [Validation] [VERIFY] Run coverage and check layer targets

## Execution Context

- **Total**: [N]
- **Pending**: [N]  <!-- count excludes Blocked -->
- **In Progress**: [N]
- **Done**: [N]
- **Blocked**: [N]
- **Next Task**: [TC###]
- **Last Updated**: [UTC timestamp]

## Validation Commands

```bash
flutter test --no-pub
flutter test --coverage --no-pub
dart run build_runner build --delete-conflicting-outputs
.specify/scripts/bash/check-test-coverage-targets.sh --feature-dir "<abs path>" --lcov coverage/lcov.info --allow-missing-lcov --json
```

## Coverage/Risk Notes

- [Coverage gap notes]
- [High-risk component notes]
- [Mitigation notes]

## Change Log

- [YYYY-MM-DD] [what changed in this test spec]

## Guardrails

- `test-spec.md` is the single source of truth for test execution order and tracking.
- Do not generate or depend on separate standalone test task artifacts.
- Keep tests in the same package and mirrored path as source files.
