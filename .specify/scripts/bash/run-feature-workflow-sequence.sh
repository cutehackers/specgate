#!/usr/bin/env bash

set -euo pipefail

FEATURE_DIR_ARG=""
JSON_MODE=false
RUN_SETUP=false
STOP_ON_FAIL=true
STRICT_NAMING=true

usage() {
    cat <<'USAGE'
Usage: run-feature-workflow-sequence.sh --feature-dir <absolute-path> [options]

Options:
  --feature-dir <path>   Absolute path to feature folder (required)
  --setup-code           Run setup-code.sh at the end of the sequence
  --continue-on-failure   Continue after failed gate checks
  --strict-naming         Enforce strict JSON naming policy validation before code/spec gates (default)
  --no-strict-naming      Bypass strict naming policy validation
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
    python3 - "$FEATURE_DIR" "$SEQUENCE_SUMMARY" "$STOP_ON_FAIL" "$RUN_SETUP" "$exit_code" <<'PY'
import json
import sys
from pathlib import Path

feature_dir = sys.argv[1]
summary_path = Path(sys.argv[2])
stop_on_fail = sys.argv[3] == "true"
run_setup = sys.argv[4] == "true"
forced_exit_code = int(sys.argv[5])

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

print(json.dumps(result, ensure_ascii=False, indent=2))
sys.exit(forced_exit_code)
PY
}

SEQUENCE_FAILED=false

# Sequence
if ! run_or_abort "paths-only" \
    "$REPO_ROOT/.specify/scripts/bash/check-prerequisites.sh" \
    --feature-dir "$FEATURE_DIR" \
    --paths-only \
    --json; then
    SEQUENCE_FAILED=true
    if [[ "$STOP_ON_FAIL" == true ]]; then
        if [[ "$JSON_MODE" == true ]]; then
            emit_json_summary 1
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
                emit_json_summary 1
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
            emit_json_summary 1
        else
            printf '\nSequence stopped on failure: spec-prerequisites\n' >&2
            exit 1
        fi
    fi
fi

if ! run_or_abort "code-prerequisites" \
    "$REPO_ROOT/.specify/scripts/bash/check-code-prerequisites.sh" \
    --feature-dir "$FEATURE_DIR" \
    --json; then
    SEQUENCE_FAILED=true
    if [[ "$STOP_ON_FAIL" == true ]]; then
        if [[ "$JSON_MODE" == true ]]; then
            emit_json_summary 1
        else
            printf '\nSequence stopped on failure: code-prerequisites\n' >&2
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
                emit_json_summary 1
            else
                printf '\nSequence stopped on failure: setup-code\n' >&2
                exit 1
            fi
        fi
    fi
fi

if [[ "$JSON_MODE" == true ]]; then
    if [[ "$SEQUENCE_FAILED" == true ]]; then
        emit_json_summary 1
    else
        emit_json_summary 0
    fi
elif [[ "$SEQUENCE_FAILED" == true ]]; then
    printf '\nSequence completed with failures. Review failed steps above.\n' >&2
    exit 1
else
    echo "Sequence passed."
fi
