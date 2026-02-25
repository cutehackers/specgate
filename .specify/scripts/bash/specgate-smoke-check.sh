#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

FAILED=0
TMP_OUTPUT="$(mktemp)"
trap 'rm -f "$TMP_OUTPUT"' EXIT

pass() {
    echo "OK: $1"
}

fail() {
    echo "ERROR: $1" >&2
    FAILED=$((FAILED + 1))
}

check_file_exists() {
    local rel="$1"
    local abs="$REPO_ROOT/$rel"
    if [[ -f "$abs" ]]; then
        pass "exists $rel"
    else
        fail "missing $rel"
    fi
}

echo "Running SpecGate smoke checks..."
echo "Repo root: $REPO_ROOT"

required_files=(
    ".claude/commands/specgate/feature-set.md"
    ".claude/commands/specgate/specify.md"
    ".claude/commands/specgate/clarify.md"
    ".claude/commands/specgate/codify.md"
    ".claude/commands/specgate/test-specify.md"
    ".claude/commands/specgate/test-codify.md"
    ".claude/commands/specgate/feature-done.md"
    ".opencode/command/feature-set.md"
    ".opencode/command/specify.md"
    ".opencode/command/clarify.md"
    ".opencode/command/codify.md"
    ".opencode/command/test-specify.md"
    ".opencode/command/test-codify.md"
    ".opencode/command/feature-done.md"
    ".opencode/command/README.md"
    ".codex/skills/specgate/feature-set/SKILL.md"
    ".codex/skills/specgate/specify/SKILL.md"
    ".codex/skills/specgate/clarify/SKILL.md"
    ".codex/skills/specgate/codify/SKILL.md"
    ".codex/skills/specgate/test-specify/SKILL.md"
    ".codex/skills/specgate/test-codify/SKILL.md"
    ".codex/skills/specgate/feature-done/SKILL.md"
    ".codex/skills/specgate/analyze/SKILL.md"
    ".codex/skills/specgate/checklist/SKILL.md"
    ".codex/skills/specgate/constitution/SKILL.md"
    ".codex/skills/specgate/taskstoissues/SKILL.md"
    ".claude/commands/specgate/README.md"
    ".specify/templates/spec-template.md"
    ".specify/templates/clarify-template.md"
    ".specify/templates/code-template.md"
    ".specify/templates/test-spec-template.md"
    ".specify/templates/quickstart-template.md"
    ".specify/templates/screen-abstraction-template.md"
    ".specify/templates/layer-rules-template.yaml"
    ".specify/scripts/bash/check-prerequisites.sh"
    ".specify/scripts/bash/check-spec-prerequisites.sh"
    ".specify/scripts/bash/check-code-prerequisites.sh"
    ".specify/scripts/bash/check-naming-policy.sh"
    ".specify/scripts/bash/check-test-prerequisites.sh"
    ".specify/scripts/bash/check-implementation-quality.sh"
    ".specify/scripts/bash/check-implementation-readiness.sh"
    ".specify/scripts/bash/check-layer-compliance.sh"
    ".specify/scripts/bash/bootstrap-layer-rules.sh"
    ".specify/scripts/bash/load-layer-rules.sh"
    ".specify/scripts/bash/check-test-coverage-targets.sh"
    ".specify/scripts/bash/specgate-sync-pointer.sh"
    ".specify/scripts/bash/specgate-status.sh"
    ".specify/scripts/bash/run-feature-workflow-sequence.sh"
    ".specify/scripts/bash/setup-code.sh"
    ".specify/scripts/bash/setup-test-spec.sh"
    ".claude/hooks/statusline.js"
    "docs/SPECGATE.md"
)

for file in "${required_files[@]}"; do
    check_file_exists "$file"
done

POINTER_FILE="$REPO_ROOT/specs/feature-stage.local.json"

if [[ -f "$POINTER_FILE" ]]; then
if python3 - <<'PY' "$POINTER_FILE" "$REPO_ROOT" >"$TMP_OUTPUT" 2>&1
import json
import sys
from pathlib import Path

pointer_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])

data = json.loads(pointer_path.read_text(encoding="utf-8"))
errors = []
warnings = []

feature_dir_raw = str(data.get("feature_dir", "")).strip()
status = str(data.get("status", "")).strip()
stage = str(data.get("stage", "")).strip()
current_doc = str(data.get("current_doc", "")).strip()
is_done_stage = status == "done"
valid_statuses = {"in_progress", "done", "blocked"}
valid_stages = {
    "specifying",
    "clarifying",
    "coding",
    "test_planning",
    "test_writing",
    "done",
    "blocked",
}
if status and status not in valid_statuses:
    errors.append(f"pointer has unsupported status: {status}")
if stage and stage not in valid_stages:
    errors.append(f"pointer has unsupported stage: {stage}")
if status == "done":
    if stage and stage != "done":
        errors.append("pointer status=done requires stage=done")
    if current_doc:
        errors.append("pointer status=done requires current_doc to be empty")

if not feature_dir_raw:
    errors.append("pointer missing feature_dir")
else:
    feature_dir = Path(feature_dir_raw).expanduser()
    if not feature_dir.is_absolute():
        feature_dir = (repo_root / feature_dir).resolve()
    if not feature_dir.is_dir():
        if str(feature_dir).startswith(f"{repo_root}"):
            if is_done_stage:
                warnings.extend(
                    [
                        f"pointer feature_dir missing for DONE state: {feature_dir}",
                        "This is usually a stale pointer; run /feature-set before starting a new flow.",
                    ]
                )
            else:
                errors.append(f"pointer feature_dir not found: {feature_dir}")
        else:
            warnings.append(
                f"pointer feature_dir points outside repo and is missing: {feature_dir}"
            )
    else:
        docs_dir = feature_dir / "docs"
        docs_are_bootstrap_candidates = (
            status == "in_progress"
            and stage == "specifying"
            and feature_dir.is_dir()
        )

        if not docs_dir.is_dir():
            if is_done_stage:
                warnings.append(f"pointer feature docs missing for DONE state: {docs_dir}")
            else:
                if str(docs_dir).startswith(f"{repo_root}"):
                    errors.append(f"feature docs directory missing: {docs_dir}")
                else:
                    warnings.append(
                        "active pointer references docs directory outside repo; run /feature-set or remove stale specs/feature-stage.local.json"
                    )
        else:
            has_docs_artifacts = any(p.is_file() for p in docs_dir.rglob("*"))
            if docs_are_bootstrap_candidates and not has_docs_artifacts:
                # Re-specify bootstrap mode: docs intentionally removed and regenerated through /specify.
                pass
            else:
                spec_path = docs_dir / "spec.md"
                if status != "done" and not spec_path.is_file():
                    errors.append(f"active feature missing spec.md: {spec_path}")

                if current_doc:
                    current_doc_path = docs_dir / current_doc
                    if not current_doc_path.is_file():
                        errors.append(
                            f"pointer current_doc does not exist: {current_doc_path}"
                        )

                stage_expected_doc = {
                    "specifying": "spec.md",
                    "clarifying": "spec.md",
                    "coding": "tasks.md",
                    "test_planning": "test-spec.md",
                    "test_writing": "test-spec.md",
                }
                if status != "done":
                    if not current_doc:
                        errors.append(f"pointer current_doc is empty for status '{status}'")

                if status != "done":
                    expected_doc = stage_expected_doc.get(stage)
                    if expected_doc and current_doc != expected_doc:
                        errors.append(
                            "pointer stage/current_doc mismatch: "
                            f"stage '{stage}' expects '{expected_doc}', got '{current_doc}'"
                        )

if errors:
    for item in errors:
        print(item)
    raise SystemExit(1)
if warnings:
    for item in warnings:
        print(f"WARN: {item}")
PY
then
    pass "active pointer feature docs integrity is valid"
else
    fail "active pointer feature docs integrity check failed"
    cat "$TMP_OUTPUT" >&2
fi
else
    pass "active pointer file intentionally omitted in fresh install (specs/feature-stage.local.json)"
fi

legacy_paths=(
    ".claude/commands/specgate/plan.md"
    ".claude/commands/specgate/tasks.md"
    ".claude/commands/specgate/tasks-test.md"
    ".claude/commands/specgate/implement.md"
    ".opencode/command/plan.md"
    ".opencode/command/tasks.md"
    ".opencode/command/tasks-test.md"
    ".opencode/command/implement.md"
)

for rel in "${legacy_paths[@]}"; do
    if [[ -e "$REPO_ROOT/$rel" ]]; then
        fail "legacy artifact exists in active surface: $rel"
    else
        pass "legacy artifact absent: $rel"
    fi
done

legacy_scripts=(
    ".specify/scripts/bash/setup-plan.sh"
    ".specify/scripts/bash/setup-plan-test.sh"
)

for rel in "${legacy_scripts[@]}"; do
    if [[ -e "$REPO_ROOT/$rel" ]]; then
        fail "legacy setup script exists in active surface: $rel"
    else
        pass "legacy setup script absent: $rel"
    fi
done

legacy_templates=(
    ".specify/templates/plan-test-template.md"
)

for rel in "${legacy_templates[@]}"; do
    if [[ -e "$REPO_ROOT/$rel" ]]; then
        fail "legacy template exists in active surface: $rel"
    else
        pass "legacy template absent: $rel"
    fi
done

if rg -n "velospec" \
    "$REPO_ROOT/.claude/commands/specgate" \
    "$REPO_ROOT/.opencode/command" \
    "$REPO_ROOT/.codex/skills/specgate" >"$TMP_OUTPUT"; then
    fail "found 'velospec' reference in active SpecGate surfaces"
    cat "$TMP_OUTPUT" >&2
else
    pass "no 'velospec' references in active SpecGate surfaces"
fi

if rg -n "agent:\\s*plan\\b" \
    "$REPO_ROOT/.claude/commands/specgate" \
    "$REPO_ROOT/.opencode/command" \
    "$REPO_ROOT/.codex/skills/specgate" >"$TMP_OUTPUT"; then
    fail "found deprecated plan handoff in active SpecGate command surfaces"
    cat "$TMP_OUTPUT" >&2
else
    pass "no deprecated plan handoffs in active SpecGate command surfaces"
fi

if rg -n "/specgate/(feature-set|specify|clarify|codify|test-specify|test-codify|feature-done)\b" \
    "$REPO_ROOT/docs/SPECGATE.md" \
    "$REPO_ROOT/.claude/commands/specgate" \
    "$REPO_ROOT/.opencode/command" \
    "$REPO_ROOT/.codex/skills/specgate" >"$TMP_OUTPUT"; then
    fail "found mixed command invocation style (/specgate/...) in active docs"
    cat "$TMP_OUTPUT" >&2
else
    pass "flat command invocation style is consistent in active docs"
fi

sync_required=(
    ".claude/commands/specgate/feature-set.md"
    ".claude/commands/specgate/specify.md"
    ".claude/commands/specgate/clarify.md"
    ".claude/commands/specgate/codify.md"
    ".claude/commands/specgate/test-specify.md"
    ".claude/commands/specgate/test-codify.md"
    ".claude/commands/specgate/feature-done.md"
    ".opencode/command/feature-set.md"
    ".opencode/command/specify.md"
    ".opencode/command/clarify.md"
    ".opencode/command/codify.md"
    ".opencode/command/test-specify.md"
    ".opencode/command/test-codify.md"
    ".opencode/command/feature-done.md"
)

for rel in "${sync_required[@]}"; do
    abs="$REPO_ROOT/$rel"
    if rg -q "specgate-sync-pointer.sh" "$abs"; then
        pass "sync hook present: $rel"
    else
        fail "sync hook missing: $rel"
    fi
done

if rg -n "\"feature_dir\": \"/absolute/path/to/feature\"" \
    "$REPO_ROOT/.claude/commands/specgate" \
    "$REPO_ROOT/.opencode/command" \
    "$REPO_ROOT/.codex/skills/specgate" >"$TMP_OUTPUT"; then
    fail "manual pointer json example still present in active command surfaces"
    cat "$TMP_OUTPUT" >&2
else
    pass "manual pointer json examples removed from active command surfaces"
fi

if rg -n "specgate-sync-pointer\\.sh --feature-dir \"<abs path>\" --json" \
    "$REPO_ROOT/.claude/commands/specgate" \
    "$REPO_ROOT/.opencode/command" \
    "$REPO_ROOT/.codex/skills/specgate" >"$TMP_OUTPUT"; then
    fail "pre-step sync must preserve phase (missing --preserve-stage)"
    cat "$TMP_OUTPUT" >&2
else
    pass "pre-step sync preserves phase with --preserve-stage"
fi

supporting_sync_safe=(
    ".claude/commands/specgate/checklist.md"
    ".claude/commands/specgate/taskstoissues.md"
    ".opencode/command/checklist.md"
    ".opencode/command/taskstoissues.md"
)

for rel in "${supporting_sync_safe[@]}"; do
    abs="$REPO_ROOT/$rel"
    if ! rg -q "specgate-sync-pointer\\.sh" "$abs"; then
        fail "supporting command missing sync call: $rel"
        continue
    fi
    if ! rg -q -- "--preserve-stage" "$abs"; then
        fail "supporting command must use --preserve-stage: $rel"
        continue
    fi
    if rg -q -- "--stage\\s+" "$abs"; then
        fail "supporting command must not force stage transitions: $rel"
    else
        pass "supporting command sync is phase-safe: $rel"
    fi
done

for script in \
    "$REPO_ROOT/.specify/scripts/bash/check-prerequisites.sh" \
    "$REPO_ROOT/.specify/scripts/bash/check-spec-prerequisites.sh" \
    "$REPO_ROOT/.specify/scripts/bash/check-code-prerequisites.sh" \
    "$REPO_ROOT/.specify/scripts/bash/check-naming-policy.sh" \
    "$REPO_ROOT/.specify/scripts/bash/run-feature-workflow-sequence.sh" \
    "$REPO_ROOT/.specify/scripts/bash/check-test-prerequisites.sh" \
    "$REPO_ROOT/.specify/scripts/bash/check-implementation-quality.sh" \
    "$REPO_ROOT/.specify/scripts/bash/check-implementation-readiness.sh" \
    "$REPO_ROOT/.specify/scripts/bash/check-test-coverage-targets.sh" \
    "$REPO_ROOT/.specify/scripts/bash/specgate-sync-pointer.sh" \
    "$REPO_ROOT/.specify/scripts/bash/specgate-status.sh" \
    "$REPO_ROOT/.specify/scripts/bash/setup-code.sh" \
    "$REPO_ROOT/.specify/scripts/bash/specgate-smoke-check.sh"; do
    if bash -n "$script"; then
        pass "bash syntax ok: ${script#$REPO_ROOT/}"
    else
        fail "bash syntax failed: ${script#$REPO_ROOT/}"
    fi
done

if command -v node >/dev/null 2>&1; then
    if node -c "$REPO_ROOT/.claude/hooks/statusline.js" >/dev/null 2>&1; then
        pass "node syntax ok: .claude/hooks/statusline.js"
    else
        fail "node syntax failed: .claude/hooks/statusline.js"
    fi
else
    fail "node is not available for statusline syntax check"
fi

LAYER_SMOKE_ROOT="$(mktemp -d)"
LAYER_SMOKE_FEATURE="$LAYER_SMOKE_ROOT/features/home"
LAYER_SMOKE_OUTPUT="$(mktemp)"
LAYER_SMOKE_SOURCE_DIR="$LAYER_SMOKE_FEATURE/docs"
REPO_CONTRACT_BACKUP="$(mktemp)"
if cp "$REPO_ROOT/.specify/layer_rules/contract.yaml" "$REPO_CONTRACT_BACKUP"; then
    :
else
    : >"$REPO_CONTRACT_BACKUP"
fi

mkdir -p "$LAYER_SMOKE_ROOT/.specify/layer_rules"
mkdir -p "$LAYER_SMOKE_FEATURE/docs"

cat >"$LAYER_SMOKE_ROOT/.specify/layer_rules/contract.yaml" <<'EOF'
layer_rules:
  presentation:
    forbid_import_patterns:
      - '^package:legacy/data/'
  domain:
    forbid_import_patterns:
      - '^package:legacy/data/.*'
EOF

cat >"$LAYER_SMOKE_SOURCE_DIR/ARCHITECTURE.md" <<'EOF'
# Home

```yaml
layer_rules:
  presentation:
    forbid_import_patterns:
      - '^package:legacy/data/'
```
EOF

if bash "$REPO_ROOT/.specify/scripts/bash/load-layer-rules.sh" \
    --source-dir "$LAYER_SMOKE_SOURCE_DIR" \
    --repo-root "$LAYER_SMOKE_ROOT" \
    --no-write-resolved \
    --json > "$LAYER_SMOKE_OUTPUT" 2>&1; then
    if python3 - "$LAYER_SMOKE_OUTPUT" <<'PY'
import json
import sys

raw = open(sys.argv[1], encoding="utf-8").read()
try:
    payload = json.loads(raw)
except Exception as err:
    raise SystemExit(f"load-layer-rules output is not valid JSON: {err}")

if not isinstance(payload, dict):
    raise SystemExit("load-layer-rules payload is not a JSON object")

errors = payload.get("errors", [])
if errors:
    raise SystemExit(f"load-layer-rules reported parse failures: {errors!r}")

if not bool(payload.get("has_layer_rules")):
    raise SystemExit("load-layer-rules fixture did not resolve layer_rules")
PY
    then
        pass "load-layer-rules parser smoke check passed with valid policy input"
    else
        fail "load-layer-rules parser smoke check failed: output validation failed"
        cat "$LAYER_SMOKE_OUTPUT" >&2
    fi
else
    fail "load-layer-rules parser smoke check failed to execute"
    cat "$LAYER_SMOKE_OUTPUT" >&2
fi

rm -f "$LAYER_SMOKE_ROOT/.specify/layer_rules/contract.yaml"

cat >"$LAYER_SMOKE_SOURCE_DIR/ARCHITECTURE.md" <<'EOF'
# Home

## Domain layer

- Do not import presentation layer.
- Do not import data layer.
- Do not import repository_impl.
- Do not import ui components.

## Data layer

- Do not import presentation layer.

## Presentation layer

- Do not import data layer.

EOF

if bash "$REPO_ROOT/.specify/scripts/bash/load-layer-rules.sh" \
    --source-dir "$LAYER_SMOKE_SOURCE_DIR" \
    --repo-root "$LAYER_SMOKE_ROOT" \
    --no-write-resolved \
    --json > "$LAYER_SMOKE_OUTPUT" 2>&1; then
    if python3 - "$LAYER_SMOKE_OUTPUT" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
if payload.get("source_mode") != "INFERRED":
    raise SystemExit(f"expected source_mode=INFERRED, got {payload.get('source_mode')!r}")
if not bool(payload.get("has_layer_rules")):
    raise SystemExit("inference-only load-layer-rules did not resolve layer_rules")

inference = payload.get("inference", {})
confidence = float(inference.get("confidence", 0) or 0)
if confidence < 0.75:
    raise SystemExit(f"inference confidence too low for deterministic prose-only case: {confidence}")
if not bool(inference.get("fallback_applied", False)):
    raise SystemExit("inference fallback_applied flag was false")
PY
    then
        pass "load-layer-rules produced deterministic inference from prose-only architecture docs"
    else
        fail "load-layer-rules inference smoke check failed"
        cat "$LAYER_SMOKE_OUTPUT" >&2
    fi
else
    fail "load-layer-rules inference smoke check failed to execute"
    cat "$LAYER_SMOKE_OUTPUT" >&2
fi

LAYER_SMOKE_LOWCONF_FEATURE="$LAYER_SMOKE_ROOT/features/low-confidence"
mkdir -p "$LAYER_SMOKE_LOWCONF_FEATURE/docs"
cat >"$LAYER_SMOKE_LOWCONF_FEATURE/docs/ARCHITECTURE.md" <<'EOF'
# Low confidence test

## Domain layer

- Do not import data layer.

Use case should follow pattern {Action}UseCase.
EOF

rm -f "$REPO_ROOT/.specify/layer_rules/contract.yaml"

if bash "$REPO_ROOT/.specify/scripts/bash/check-layer-compliance.sh" \
    --feature-dir "$LAYER_SMOKE_LOWCONF_FEATURE" \
    --strict-layer \
    --json > "$LAYER_SMOKE_OUTPUT" 2>&1; then
    fail "low-confidence strict-layer check unexpectedly passed"
    cat "$LAYER_SMOKE_OUTPUT" >&2
else
    if python3 - "$LAYER_SMOKE_OUTPUT" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("source_mode") != "INFERRED":
    raise SystemExit(f"expected source_mode=INFERRED, got {payload.get('source_mode')!r}")
if payload.get("parse_policy_action") != "fail":
    raise SystemExit(f"expected parse_policy_action='fail', got {payload.get('parse_policy_action')!r}")
inference = payload.get("inference", {})
if float(inference.get("confidence", 0) or 0) >= 0.5:
    raise SystemExit(f"expected low-confidence (<0.5) strict failure, got {inference.get('confidence')!r}")
PY
    then
        pass "low-confidence inference strict-layer path now fails as expected"
    else
        fail "low-confidence strict-layer inference smoke validation failed"
        cat "$LAYER_SMOKE_OUTPUT" >&2
    fi
fi

if ! cp "$REPO_CONTRACT_BACKUP" "$REPO_ROOT/.specify/layer_rules/contract.yaml"; then
    fail "smoke setup: failed to restore repository contract after low-confidence strict-layer smoke"
fi

cat >"$LAYER_SMOKE_ROOT/.specify/layer_rules/contract.yaml" <<'EOF'
layer_rules:
  presentation
    forbid_import_patterns:
      - '^package:legacy/data/'
EOF

cat >"$LAYER_SMOKE_SOURCE_DIR/ARCHITECTURE.md" <<'EOF'
# Home

```yaml
layer_rules:
  presentation:
    forbid_import_patterns:
      - '^package:legacy/data/'
```
EOF

if bash "$REPO_ROOT/.specify/scripts/bash/load-layer-rules.sh" \
    --source-dir "$LAYER_SMOKE_SOURCE_DIR" \
    --repo-root "$LAYER_SMOKE_ROOT" \
    --no-write-resolved \
    --json > "$LAYER_SMOKE_OUTPUT" 2>&1; then
    if python3 - "$LAYER_SMOKE_OUTPUT" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
errors = payload.get("errors", [])
if not errors:
    raise SystemExit("malformed architecture input did not produce parse errors")
PY
    then
        pass "load-layer-rules parser smoke check flagged malformed YAML as expected"
    else
        fail "load-layer-rules malformed input smoke check failed"
        cat "$LAYER_SMOKE_OUTPUT" >&2
    fi
else
    fail "load-layer-rules malformed input smoke command failed unexpectedly"
    cat "$LAYER_SMOKE_OUTPUT" >&2
fi

cat >"$LAYER_SMOKE_ROOT/.specify/layer_rules/contract.yaml" <<'EOF'
foo: bar
EOF

cat >"$LAYER_SMOKE_SOURCE_DIR/ARCHITECTURE.md" <<'EOF'
# Home

```yaml
layer_rules:
  presentation:
    forbid_import_patterns:
      - '^package:legacy/data/'
```
EOF

if bash "$REPO_ROOT/.specify/scripts/bash/load-layer-rules.sh" \
    --source-dir "$LAYER_SMOKE_SOURCE_DIR" \
    --repo-root "$LAYER_SMOKE_ROOT" \
    --no-write-resolved \
    --json > "$LAYER_SMOKE_OUTPUT" 2>&1; then
    if python3 - "$LAYER_SMOKE_OUTPUT" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
parse_summary = payload.get("parse_summary", {})
if isinstance(parse_summary, str):
    parse_summary = json.loads(parse_summary)
if int(parse_summary.get("schema_mismatch", 0) or 0) <= 0:
    raise SystemExit("schema_mismatch counter did not increase for non-policy candidate")

if not bool(payload.get("has_layer_rules")):
    raise SystemExit("schema mismatch preflight did not resolve valid architecture layer_rules")
PY
    then
        pass "load-layer-rules parser smoke check captured schema mismatch while resolving fallback layer_rules"
    else
        fail "load-layer-rules schema mismatch smoke check failed"
        cat "$LAYER_SMOKE_OUTPUT" >&2
    fi
else
    fail "load-layer-rules schema mismatch smoke command failed"
    cat "$LAYER_SMOKE_OUTPUT" >&2
fi

cat >"$LAYER_SMOKE_ROOT/.specify/layer_rules/contract.yaml" <<'EOF'
'foo': bar
EOF

cat >"$LAYER_SMOKE_SOURCE_DIR/ARCHITECTURE.md" <<'EOF'
# Home

```yaml
layer_rules:
  presentation:
    forbid_import_patterns:
      - '^package:legacy/data/'
```
EOF

if bash "$REPO_ROOT/.specify/scripts/bash/load-layer-rules.sh" \
    --source-dir "$LAYER_SMOKE_SOURCE_DIR" \
    --repo-root "$LAYER_SMOKE_ROOT" \
    --no-write-resolved \
    --json > "$LAYER_SMOKE_OUTPUT" 2>&1; then
    if python3 - "$LAYER_SMOKE_OUTPUT" <<'PY'
import json
import sys

payload = json.loads(open(sys.argv[1], encoding="utf-8").read())
parse_events = payload.get("parse_events", [])
if not isinstance(parse_events, list):
    raise SystemExit("parse_events is missing or not a list")

if not any(event.get("code") == "JSON_PARSE_ERROR" for event in parse_events):
    raise SystemExit("parser did not record JSON_PARSE_ERROR for non-standard json policy input")

parse_summary = payload.get("parse_summary", {})
if isinstance(parse_summary, str):
    parse_summary = json.loads(parse_summary)
if int(parse_summary.get("failed", 0) or 0) <= 0:
    raise SystemExit("parser did not count failed JSON parse events")
PY
    then
        pass "load-layer-rules parser smoke check reported JSON_PARSE_ERROR path as expected"
    else
        fail "load-layer-rules JSON parse smoke check failed"
        cat "$LAYER_SMOKE_OUTPUT" >&2
    fi
else
    fail "load-layer-rules JSON parse smoke command failed"
    cat "$LAYER_SMOKE_OUTPUT" >&2
fi

LAYER_SMOKE_SEQUENCE_FEATURE="$LAYER_SMOKE_ROOT/features/workflow-sequence"
LAYER_SMOKE_SEQUENCE_CONTRACT_BACKUP="$(mktemp)"
mkdir -p "$LAYER_SMOKE_SEQUENCE_FEATURE/docs"
cat >"$LAYER_SMOKE_SEQUENCE_FEATURE/docs/ARCHITECTURE.md" <<'EOF'
# Sequence

```yaml
layer_rules:
  presentation:
    forbid_import_patterns:
      - '^package:legacy/data/'
```
EOF
cat >"$LAYER_SMOKE_SEQUENCE_FEATURE/docs/spec.md" <<'EOF'
# Sequence feature
EOF

if cp "$REPO_ROOT/.specify/layer_rules/contract.yaml" "$LAYER_SMOKE_SEQUENCE_CONTRACT_BACKUP"; then
    cat >"$REPO_ROOT/.specify/layer_rules/contract.yaml" <<'EOF'
layer_rules
  presentation:
    forbid_import_patterns:
      - '^package:legacy/data/'
EOF

    if bash "$REPO_ROOT/.specify/scripts/bash/run-feature-workflow-sequence.sh" \
        --feature-dir "$LAYER_SMOKE_SEQUENCE_FEATURE" \
        --strict-layer \
        --json \
        --continue-on-failure > "$LAYER_SMOKE_OUTPUT" 2>&1; then
        fail "run-feature-workflow strict-layer unexpectedly passed with malformed layer contract"
    else
        if python3 - "$LAYER_SMOKE_OUTPUT" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("status") != "failed":
    raise SystemExit(f"workflow status expected failed, got {payload.get('status')!r}")

preflight = payload.get("layer_rules_preflight")
if not isinstance(preflight, dict):
    raise SystemExit("layer_rules_preflight missing from strict workflow output")

if not bool(preflight.get("strict_layer", False)):
    raise SystemExit("strict_layer flag was not propagated into preflight")
if not bool(preflight.get("strict_parse_blocked", False)):
    raise SystemExit("strict_parse_blocked should be true for malformed policy")

parse_summary = preflight.get("parse_summary", {})
if not isinstance(parse_summary, dict):
    raise SystemExit("parse_summary missing or invalid in preflight")
if int(parse_summary.get("failed", 0) or 0) <= 0 and int(parse_summary.get("blocked_by_parser_missing", 0) or 0) <= 0:
    raise SystemExit("preflight parse_summary did not record failing parser counters")

failed_steps = payload.get("failed_steps", [])
if not any(isinstance(item, dict) and item.get("step") == "paths-only" for item in failed_steps):
    raise SystemExit("paths-only failure missing from failed_steps")
PY
        then
            pass "run-feature-workflow strict-layer parse gate failed as expected with contract parse errors"
        else
            fail "run-feature-workflow strict-layer smoke check failed"
            cat "$LAYER_SMOKE_OUTPUT" >&2
        fi
    fi

    if ! cp "$LAYER_SMOKE_SEQUENCE_CONTRACT_BACKUP" "$REPO_ROOT/.specify/layer_rules/contract.yaml"; then
        fail "failed to restore layer contract.yaml after strict-mode sequence smoke check"
    fi
else
    fail "could not backup layer contract.yaml for strict-mode sequence smoke check"
fi

rm -f "$LAYER_SMOKE_SEQUENCE_CONTRACT_BACKUP"

if bash "$REPO_ROOT/.specify/scripts/bash/run-feature-workflow-sequence.sh" \
    --feature-dir "$LAYER_SMOKE_SEQUENCE_FEATURE" \
    --json \
    --continue-on-failure \
    --no-strict-layer \
    --no-strict-naming > "$LAYER_SMOKE_OUTPUT" 2>&1; then
    :
fi

if python3 - "$LAYER_SMOKE_OUTPUT" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
preflight = payload.get("layer_rules_preflight")
if not isinstance(preflight, dict):
    raise SystemExit("layer_rules_preflight missing from workflow output")

required = {
    "source_kind",
    "source_file",
    "source_reason",
    "resolved_path",
    "has_layer_rules",
    "parse_summary",
    "parse_events",
    "parse_events_count",
    "strict_layer",
    "strict_parse_blocked",
    "parse_policy_action",
}
missing = sorted(key for key in required if key not in preflight)
if missing:
    raise SystemExit(f"layer_rules_preflight missing required keys: {missing}")

parse_events = preflight.get("parse_events", [])
if not isinstance(parse_events, list):
    raise SystemExit("parse_events is missing or not a list")
if preflight.get("parse_events_count") != len(parse_events):
    raise SystemExit("parse_events_count does not match parse_events length")

parse_summary = preflight.get("parse_summary", {})
if not isinstance(parse_summary, dict):
    raise SystemExit("parse_summary is missing or not a dict")
PY
then
    pass "run-feature-workflow layer_rules_preflight schema includes required machine-readable fields"
else
    fail "run-feature-workflow layer_rules_preflight schema validation failed"
    cat "$LAYER_SMOKE_OUTPUT" >&2
fi

rm -f "$LAYER_SMOKE_OUTPUT"
rm -f "$LAYER_SMOKE_SEQUENCE_CONTRACT_BACKUP"
rm -f "$REPO_CONTRACT_BACKUP"
rm -rf "$LAYER_SMOKE_ROOT"

if [[ "$FAILED" -gt 0 ]]; then
    echo
    echo "SpecGate smoke check failed ($FAILED issue(s))." >&2
    exit 1
fi

echo
echo "SpecGate smoke check passed."
