#!/usr/bin/env bash

set -euo pipefail

FEATURE_DIR_ARG=""
JSON_MODE=false
RUN_SETUP=false
STOP_ON_FAIL=true
STRICT_NAMING=true
STRICT_LAYER=false

usage() {
    cat <<'USAGE'
Usage: run-feature-workflow-sequence.sh --feature-dir <absolute-path> [options]

Options:
  --feature-dir <path>   Absolute path to feature folder (required)
  --setup-code           Run setup-code.sh at the end of the sequence
  --continue-on-failure   Continue after failed gate checks
  --strict-naming         Enforce strict JSON naming policy validation before code/spec gates (default)
  --no-strict-naming      Bypass strict naming policy validation
  --strict-layer          Enable strict layer policy validation in implementation quality gate
  --no-strict-layer       Disable strict layer policy validation in implementation quality gate
  --json                 Emit JSON status per step
  --help                 Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature-dir)
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --setup-code)
            RUN_SETUP=true
            shift
            ;;
        --continue-on-failure)
            STOP_ON_FAIL=false
            shift
            ;;
        --strict-naming)
            STRICT_NAMING=true
            shift
            ;;
        --no-strict-naming)
            STRICT_NAMING=false
            shift
            ;;
        --strict-layer)
            STRICT_LAYER=true
            shift
            ;;
        --no-strict-layer)
            STRICT_LAYER=false
            shift
            ;;
        --json)
            JSON_MODE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option '$1'." >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$FEATURE_DIR_ARG" ]]; then
    echo "ERROR: --feature-dir is required." >&2
    usage >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

eval $(get_feature_paths "$FEATURE_DIR_ARG") || exit 1

SEQUENCE_SUMMARY="$(mktemp)"
cleanup() {
    rm -f "$SEQUENCE_SUMMARY"
}
trap cleanup EXIT

LAST_PATHS_ONLY_PARSE_SUMMARY="{}"
LAST_PATHS_ONLY_PARSE_BLOCKED=0
LAST_PATHS_ONLY_PARSE_FAILED=0
LAST_PATHS_ONLY_PARSE_SCHEMA_MISMATCH=0
LAST_PATHS_ONLY_PARSE_GATE_REASON=""
LAST_PATHS_ONLY_PARSE_ACTION="ok"

check_paths_only_parse_gate() {
    local output="$1"
    local strict="$2"

    LAST_PATHS_ONLY_PARSE_SUMMARY="{}"
    LAST_PATHS_ONLY_PARSE_BLOCKED=0
    LAST_PATHS_ONLY_PARSE_FAILED=0
    LAST_PATHS_ONLY_PARSE_SCHEMA_MISMATCH=0
    LAST_PATHS_ONLY_PARSE_GATE_REASON=""
    LAST_PATHS_ONLY_PARSE_ACTION="ok"

    local metric
    metric="$(printf '%s' "$output" | python3 - "$strict" <<'PY'
import json
import sys

raw = sys.stdin.read().strip()
strict = (len(sys.argv) > 1 and str(sys.argv[1]).lower() == "true")

print("gate_failed=0")
print("blocked_by_parser_missing=0")
print("parse_failed=0")
print("schema_mismatch=0")
print("parse_summary={}")
print("parse_total=0")

if not raw:
    if strict:
        print("gate_failed=1")
        print("reason=paths-only output was empty; parser summary unavailable.")
    raise SystemExit(0)

try:
    payload = json.loads(raw)
except Exception:
    if strict:
        print("gate_failed=1")
        print("reason=paths-only output is not valid JSON.")
    raise SystemExit(0)

summary = payload.get("LAYER_RULES_PARSE_SUMMARY", {})
if isinstance(summary, str):
    try:
        summary = json.loads(summary)
    except Exception:
        summary = {}

if not isinstance(summary, dict):
    summary = {}

blocked = int(summary.get("blocked_by_parser_missing", 0) or 0)
failed = int(summary.get("failed", 0) or 0)
schema_mismatch = int(summary.get("schema_mismatch", 0) or 0)
total = int(summary.get("total", 0) or 0)

print(f"blocked_by_parser_missing={blocked}")
print(f"parse_failed={failed}")
print(f"schema_mismatch={schema_mismatch}")
print(f"parse_total={total}")
print("parse_summary=" + json.dumps(summary, ensure_ascii=False, separators=(",", ":")))

if strict and (blocked > 0 or failed > 0):
    print("parse_action=fail")
elif failed > 0 or blocked > 0 or schema_mismatch > 0:
    print("parse_action=warn")
else:
    print("parse_action=ok")

if strict and (blocked > 0 or failed > 0):
    print("gate_failed=1")
    print(
        f"reason=strict-layer parse gate failed: "
        f"blocked_by_parser_missing={blocked}, parse_failed={failed}, schema_mismatch={schema_mismatch}"
    )
PY
)"

    while IFS='=' read -r key value; do
        case "$key" in
            parse_summary)
                LAST_PATHS_ONLY_PARSE_SUMMARY="${value}"
                ;;
            blocked_by_parser_missing)
                LAST_PATHS_ONLY_PARSE_BLOCKED="${value}"
                ;;
            parse_failed)
                LAST_PATHS_ONLY_PARSE_FAILED="${value}"
                ;;
            parse_action)
                LAST_PATHS_ONLY_PARSE_ACTION="${value}"
                ;;
            schema_mismatch)
                LAST_PATHS_ONLY_PARSE_SCHEMA_MISMATCH="${value}"
                ;;
            reason)
                LAST_PATHS_ONLY_PARSE_GATE_REASON="${value}"
                ;;
            gate_failed)
                if [[ "$value" == "1" ]]; then
                    return 1
                fi
                ;;
        esac
    done <<< "$metric"

    return 0
}

add_step_summary() {
    local label="$1"
    local command="$2"
    local exit_code="$3"
    local ok="$4"
    local output="$5"

    python3 - "$label" "$command" "$exit_code" "$ok" "$output" <<'PY'
import json
import sys

label = sys.argv[1]
command = sys.argv[2]
exit_code = int(sys.argv[3])
ok = sys.argv[4] == "true"
output = sys.argv[5]

print(
    json.dumps(
        {
            "step": label,
            "command": command,
            "exit_code": exit_code,
            "ok": ok,
            "raw_output": output,
        },
        ensure_ascii=False,
    )
)
PY
}

run_step() {
    local label="$1"
    shift
    local command_line="$*"
    local tmp
    tmp="$(mktemp)"
    local rc=0
    local ok=false
    local output

    set +e
    "$@" > "$tmp" 2>&1
    rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
        ok=true
    fi

    if [[ -f "$tmp" ]] && grep -q '"ok":false' "$tmp"; then
        ok=false
    fi

    output="$(cat "$tmp")"

    if [[ "$label" == "paths-only" ]]; then
        if ! check_paths_only_parse_gate "$output" "$STRICT_LAYER"; then
            ok=false
            output="${output}"$'\n'"- strict-layer parse gate: ${LAST_PATHS_ONLY_PARSE_GATE_REASON}"
        elif [[ "$STRICT_LAYER" == false ]]; then
            local parse_warning=""
            if [[ "$LAST_PATHS_ONLY_PARSE_FAILED" -gt 0 || "$LAST_PATHS_ONLY_PARSE_BLOCKED" -gt 0 || "$LAST_PATHS_ONLY_PARSE_SCHEMA_MISMATCH" -gt 0 ]]; then
                parse_warning="- paths-only parser warning: parse_summary failed=${LAST_PATHS_ONLY_PARSE_FAILED}, blocked_by_parser_missing=${LAST_PATHS_ONLY_PARSE_BLOCKED}, schema_mismatch=${LAST_PATHS_ONLY_PARSE_SCHEMA_MISMATCH}"
                output="${output}"$'\n'"${parse_warning}"
            fi
        fi

        output="${output}"$'\n'"LAYER_RULES_PARSE_SUMMARY=${LAST_PATHS_ONLY_PARSE_SUMMARY}"
        output="${output}"$'\n'"LAYER_RULES_PARSE_ACTION=${LAST_PATHS_ONLY_PARSE_ACTION}"
        output="${output}"$'\n'"LAYER_RULES_PARSE_FAILED=${LAST_PATHS_ONLY_PARSE_FAILED}"
        output="${output}"$'\n'"LAYER_RULES_PARSE_BLOCKED=${LAST_PATHS_ONLY_PARSE_BLOCKED}"
        output="${output}"$'\n'"LAYER_RULES_PARSE_SCHEMA_MISMATCH=${LAST_PATHS_ONLY_PARSE_SCHEMA_MISMATCH}"
    fi

    printf '%s\n' "$(add_step_summary "$label" "$command_line" "$rc" "$ok" "$output")" >> "$SEQUENCE_SUMMARY"

    if [[ "$JSON_MODE" == false ]]; then
        echo "==> $label"
        echo "$output"
        echo
    fi

    rm -f "$tmp"

    if [[ "$ok" != "true" ]]; then
        return 1
    fi
    return 0
}

run_or_abort() {
    local label="$1"
    shift

    if ! run_step "$label" "$@"; then
        return 1
    fi
    return 0
}

emit_json_summary() {
    local exit_code="$1"
    local strict_layer="$2"
    python3 - "$FEATURE_DIR" "$SEQUENCE_SUMMARY" "$STOP_ON_FAIL" "$RUN_SETUP" "$strict_layer" "$exit_code" <<'PY'
import json
import sys
from pathlib import Path

feature_dir = sys.argv[1]
summary_path = Path(sys.argv[2])
stop_on_fail = sys.argv[3] == "true"
run_setup = sys.argv[4] == "true"
strict_layer = sys.argv[5] == "true"
forced_exit_code = int(sys.argv[6])

steps = []
with summary_path.open(encoding="utf-8") as fp:
    for raw in fp:
        raw = raw.strip()
        if not raw:
            continue
        try:
            step = json.loads(raw)
        except Exception:
            step = {
                "step": "unknown",
                "command": "",
                "exit_code": 1,
                "ok": False,
                "raw_output": raw,
            }
        steps.append(step)

result = {
    "feature_dir": feature_dir,
    "sequence_completed": all(step.get("ok") for step in steps),
    "stop_on_failure": stop_on_fail,
    "setup_code_included": run_setup,
    "step_count": len(steps),
    "steps": steps,
}

failed = [step for step in steps if not step.get("ok")]
if failed:
    result["status"] = "failed"
    result["failed_steps"] = [{"step": s["step"], "command": s["command"], "exit_code": s["exit_code"]} for s in failed]
else:
    result["status"] = "passed"

layer_rules_preflight = {}
for step in steps:
    if step.get("step") != "paths-only":
        continue

    raw_output = str(step.get("raw_output", "")).strip()
    payload = None
    if raw_output:
        first_line = raw_output.splitlines()[0].strip()
        if first_line:
            try:
                payload = json.loads(first_line)
            except Exception:
                payload = None

    if payload is None:
        break

    parse_summary = payload.get("LAYER_RULES_PARSE_SUMMARY", {})
    if isinstance(parse_summary, str):
        try:
            parse_summary = json.loads(parse_summary)
        except Exception:
            parse_summary = {}
    if not isinstance(parse_summary, dict):
        parse_summary = {}

    parse_events = payload.get("LAYER_RULES_PARSE_EVENTS", [])
    if isinstance(parse_events, str):
        try:
            parse_events = json.loads(parse_events)
        except Exception:
            parse_events = []
    if not isinstance(parse_events, list):
        parse_events = []

    has_layer_rules = str(payload.get("LAYER_RULES_HAS_LAYER_RULES", "false")).lower() == "true"
    blocked = int(parse_summary.get("blocked_by_parser_missing", 0) or 0)
    failed = int(parse_summary.get("failed", 0) or 0)
    schema_mismatch = int(parse_summary.get("schema_mismatch", 0) or 0)
    parse_action = "ok"
    if strict_layer and (blocked > 0 or failed > 0):
        parse_action = "fail"
    elif failed > 0 or blocked > 0 or schema_mismatch > 0:
        parse_action = "warn"

    layer_rules_preflight = {
        "source_kind": payload.get("LAYER_RULES_SOURCE_KIND", "DEFAULT"),
        "source_file": payload.get("LAYER_RULES_SOURCE_FILE", ""),
        "source_reason": payload.get("LAYER_RULES_SOURCE_REASON", ""),
        "resolved_path": payload.get("LAYER_RULES_RESOLVED_PATH", ""),
        "has_layer_rules": has_layer_rules,
        "parse_summary": parse_summary,
        "parse_events": parse_events,
        "parse_events_count": len(parse_events),
        "strict_layer": strict_layer,
        "strict_parse_blocked": bool(strict_layer and (blocked > 0 or failed > 0)),
        "parse_policy_action": parse_action,
    }
    break

if layer_rules_preflight:
    result["layer_rules_preflight"] = layer_rules_preflight

print(json.dumps(result, ensure_ascii=False, indent=2))
sys.exit(forced_exit_code)
PY
}

SEQUENCE_FAILED=false
STRICT_LAYER_FLAGS=()
if [[ "$STRICT_LAYER" == true ]]; then
    STRICT_LAYER_FLAGS=(--strict-layer)
fi

# Sequence
if ! run_or_abort "paths-only" \
    "$REPO_ROOT/.specify/scripts/bash/check-prerequisites.sh" \
    --feature-dir "$FEATURE_DIR" \
    --paths-only \
    --json; then
    SEQUENCE_FAILED=true
    if [[ "$STOP_ON_FAIL" == true ]]; then
        if [[ "$JSON_MODE" == true ]]; then
            emit_json_summary 1 "$STRICT_LAYER"
        else
            printf '\nSequence stopped on failure: paths-only\n' >&2
            exit 1
        fi
    fi
fi

if $STRICT_NAMING; then
    if ! run_or_abort "naming-policy" \
        "$REPO_ROOT/.specify/scripts/bash/check-naming-policy.sh" \
        --feature-dir "$FEATURE_DIR" \
        --strict-naming \
        --json; then
        SEQUENCE_FAILED=true
        if [[ "$STOP_ON_FAIL" == true ]]; then
            if [[ "$JSON_MODE" == true ]]; then
                emit_json_summary 1 "$STRICT_LAYER"
            else
                printf '\nSequence stopped on failure: naming-policy\n' >&2
                exit 1
            fi
        fi
    fi
fi

if ! run_or_abort "spec-prerequisites" \
    "$REPO_ROOT/.specify/scripts/bash/check-spec-prerequisites.sh" \
    --feature-dir "$FEATURE_DIR" \
    --json; then
    SEQUENCE_FAILED=true
    if [[ "$STOP_ON_FAIL" == true ]]; then
        if [[ "$JSON_MODE" == true ]]; then
            emit_json_summary 1 "$STRICT_LAYER"
        else
            printf '\nSequence stopped on failure: spec-prerequisites\n' >&2
            exit 1
        fi
    fi
fi

if ! run_or_abort "code-prerequisites" \
    "$REPO_ROOT/.specify/scripts/bash/check-code-prerequisites.sh" \
    --feature-dir "$FEATURE_DIR" \
    --json \
    "${STRICT_LAYER_FLAGS[@]}"; then
    SEQUENCE_FAILED=true
    if [[ "$STOP_ON_FAIL" == true ]]; then
        if [[ "$JSON_MODE" == true ]]; then
            emit_json_summary 1 "$STRICT_LAYER"
        else
            printf '\nSequence stopped on failure: code-prerequisites\n' >&2
            exit 1
        fi
    fi
fi

if ! run_or_abort "implementation-quality" \
    "$REPO_ROOT/.specify/scripts/bash/check-implementation-quality.sh" \
    --feature-dir "$FEATURE_DIR" \
    --json \
    "${STRICT_LAYER_FLAGS[@]}"; then
    SEQUENCE_FAILED=true
    if [[ "$STOP_ON_FAIL" == true ]]; then
        if [[ "$JSON_MODE" == true ]]; then
            emit_json_summary 1 "$STRICT_LAYER"
        else
            printf '\nSequence stopped on failure: implementation-quality\n' >&2
            exit 1
        fi
    fi
fi

if $RUN_SETUP; then
    if ! run_or_abort "setup-code" \
        "$REPO_ROOT/.specify/scripts/bash/setup-code.sh" \
        --feature-dir "$FEATURE_DIR" \
        --json; then
        SEQUENCE_FAILED=true
        if [[ "$STOP_ON_FAIL" == true ]]; then
            if [[ "$JSON_MODE" == true ]]; then
                emit_json_summary 1 "$STRICT_LAYER"
            else
                printf '\nSequence stopped on failure: setup-code\n' >&2
                exit 1
            fi
        fi
    fi
fi

if [[ "$JSON_MODE" == true ]]; then
    if [[ "$SEQUENCE_FAILED" == true ]]; then
        emit_json_summary 1 "$STRICT_LAYER"
    else
        emit_json_summary 0 "$STRICT_LAYER"
    fi
elif [[ "$SEQUENCE_FAILED" == true ]]; then
    printf '\nSequence completed with failures. Review failed steps above.\n' >&2
    exit 1
else
    echo "Sequence passed."
fi
