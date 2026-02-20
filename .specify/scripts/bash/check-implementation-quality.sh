#!/usr/bin/env bash

set -euo pipefail

JSON_MODE=false
ALLOW_TOOL_FALLBACK=false
FEATURE_DIR_ARG=""
FULL_TEST_SUITE=false
DEGRADED=false

declare -a EXPLICIT_TEST_TARGETS=()
declare -a DEGRADED_CHECKS=()

usage() {
    cat <<'USAGE'
Usage: check-implementation-quality.sh --feature-dir <abs-path> [options]

Options:
  --feature-dir <abs-path>   Absolute path to feature directory (required)
  --test-target <path>       Additional impacted test target (repeatable)
  --full-test-suite          Force full flutter test run instead of scoped targets
  --allow-tool-fallback      Continue when flutter/dart tooling fails due local environment restrictions
  --json                     Print JSON output on success
  --help                     Show this message
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature-dir)
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --test-target)
            EXPLICIT_TEST_TARGETS+=("$2")
            shift 2
            ;;
        --full-test-suite)
            FULL_TEST_SUITE=true
            shift
            ;;
        --allow-tool-fallback)
            ALLOW_TOOL_FALLBACK=true
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

is_recoverable_tool_error() {
    local message="$1"
    local lower
    lower="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

    case "$lower" in
        *"operation not permitted"*) return 0 ;;
        *"permission denied"*) return 0 ;;
        *"read-only file system"*) return 0 ;;
        *"/cache/engine.stamp"*) return 0 ;;
        *) return 1 ;;
    esac
}

run_tool() {
    local label="$1"
    shift

    local output
    local rc

    set +e
    output="$("$@" 2>&1)"
    rc=$?
    set -e

    if ((rc == 0)); then
        [[ -n "$output" ]] && echo "$output"
        return 0
    fi

    if $ALLOW_TOOL_FALLBACK && is_recoverable_tool_error "$output"; then
        echo "WARN: skipping $label due environment-restricted tool failure (tool fallback mode)."
        DEGRADED=true
        DEGRADED_CHECKS+=("$label")
        return 0
    fi

    echo "$output" >&2
    return "$rc"
}

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

eval $(get_feature_paths "$FEATURE_DIR_ARG") || exit 1

if [[ ! -f "$CODE_DOC" ]]; then
    echo "ERROR: tasks.md not found: $CODE_DOC" >&2
    exit 1
fi

FEATURE_NAME="$(basename "$FEATURE_DIR")"
FEATURE_REL="${FEATURE_DIR#$REPO_ROOT/}"
if [[ "$FEATURE_REL" == "$FEATURE_DIR" ]]; then
    FEATURE_REL="$FEATURE_DIR"
fi

extract_test_targets_from_code_md() {
    local doc_path="$1"
    python3 - "$doc_path" <<'PY'
import re
import sys

code_doc_path = sys.argv[1]
text = open(code_doc_path, encoding="utf-8").read().replace("\r\n", "\n")

sections = {}
current = None
buffer = []
for line in text.splitlines():
    match = re.match(r"^##\s+(.+?)\s*$", line)
    if match:
        if current is not None:
            sections[current] = "\n".join(buffer)
        current = f"## {match.group(1).strip()}"
        buffer = []
        continue
    if current is not None:
        buffer.append(line)
if current is not None:
    sections[current] = "\n".join(buffer)

code_tasks = sections.get("## code-tasks", "")
if not code_tasks:
    raise SystemExit(0)

targets = set()
lines = [
    line
    for line in code_tasks.splitlines()
    if re.match(r"^\s*-\s*\[(?: |x|X)\]\s+.*$", line)
]

for line in lines:
    # 1) Prefer inline-code style paths: `test/...` or `test/.../foo.dart`
    for raw in re.findall(r"`([^`]+)`", line):
        token = raw.strip().strip("()[]")
        if not token.startswith("test/"):
            continue
        token = re.sub(r"^[\\\"'`]+|[\\\"'`,.;:)\\]]+$", "", token)
        if not token:
            continue
        if token not in targets and (token.endswith(".dart") or token.endswith("/")):
            targets.add(token)

    # 2) Catch bare test paths without inline code fences.
    for token in line.split():
        if not token.startswith("test/"):
            continue
        token = token.strip(".,;:()[]")
        if token.endswith(".dart") or token.endswith("/"):
            token = re.sub(r"[^A-Za-z0-9_./-]", "", token)
            if token:
                targets.add(token)

    # 3) Structured scan for inline path fragments.
    for match in re.finditer(r"\btest/[A-Za-z0-9_./-]+", line):
        token = match.group(0).rstrip(".,;:)[]")
        if token.endswith(".dart") or token.endswith("/"):
            targets.add(token)

for item in sorted(targets):
    print(item)
PY
}

DISCOVERED_TEST_TARGETS_RAW="$(extract_test_targets_from_code_md "$CODE_DOC")" || true

declare -a ALL_TEST_TARGETS=()
if [[ -n "$DISCOVERED_TEST_TARGETS_RAW" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ALL_TEST_TARGETS+=("$line")
    done <<< "$DISCOVERED_TEST_TARGETS_RAW"
fi

if ((${#EXPLICIT_TEST_TARGETS[@]} > 0)); then
    ALL_TEST_TARGETS+=("${EXPLICIT_TEST_TARGETS[@]}")
fi

# Conventional feature test paths for fallback discovery.
for candidate in \
    "test/unit/features/$FEATURE_NAME" \
    "test/widget/features/$FEATURE_NAME" \
    "test/integration/features/$FEATURE_NAME" \
    "test/features/$FEATURE_NAME" \
    "test/src/features/$FEATURE_NAME"; do
    if [[ -e "$REPO_ROOT/$candidate" ]]; then
        ALL_TEST_TARGETS+=("$candidate")
    fi
done

normalize_path() {
    local raw="$1"
    local cleaned="$raw"
    cleaned="${cleaned//$'\r'/}"
    cleaned="${cleaned#"${cleaned%%[![:space:]]*}"}"
    cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"
    if [[ -z "$cleaned" ]]; then
        return 1
    fi

    if [[ "$cleaned" == /* ]]; then
        if [[ "$cleaned" == "$REPO_ROOT"* ]]; then
            cleaned="${cleaned#$REPO_ROOT/}"
        fi
    fi

    printf '%s\n' "$cleaned"
}

declare -a UNIQUE_TEST_TARGETS=()
for candidate in "${ALL_TEST_TARGETS[@]+"${ALL_TEST_TARGETS[@]}"}"; do
    normalized="$(normalize_path "$candidate" || true)"
    [[ -z "$normalized" ]] && continue

    already=false
    for existing in "${UNIQUE_TEST_TARGETS[@]+"${UNIQUE_TEST_TARGETS[@]}"}"; do
        if [[ "$existing" == "$normalized" ]]; then
            already=true
            break
        fi
    done
    if ! $already; then
        UNIQUE_TEST_TARGETS+=("$normalized")
    fi
done

declare -a RESOLVED_TEST_TARGETS=()
for target in "${UNIQUE_TEST_TARGETS[@]+"${UNIQUE_TEST_TARGETS[@]}"}"; do
    if [[ -e "$REPO_ROOT/$target" ]]; then
        RESOLVED_TEST_TARGETS+=("$target")
    fi
done

declare -a FORMAT_TARGETS=()
if [[ "$FEATURE_REL" == /* ]]; then
    FORMAT_TARGETS+=("$FEATURE_REL")
else
    FORMAT_TARGETS+=("$FEATURE_REL")
fi
for target in "${RESOLVED_TEST_TARGETS[@]+"${RESOLVED_TEST_TARGETS[@]}"}"; do
    FORMAT_TARGETS+=("$target")
done

# Deduplicate format targets.
declare -a UNIQUE_FORMAT_TARGETS=()
for target in "${FORMAT_TARGETS[@]+"${FORMAT_TARGETS[@]}"}"; do
    already=false
    for existing in "${UNIQUE_FORMAT_TARGETS[@]+"${UNIQUE_FORMAT_TARGETS[@]}"}"; do
        if [[ "$existing" == "$target" ]]; then
            already=true
            break
        fi
    done
    if ! $already; then
        UNIQUE_FORMAT_TARGETS+=("$target")
    fi
done

if [[ ${#UNIQUE_FORMAT_TARGETS[@]} -eq 0 ]]; then
    UNIQUE_FORMAT_TARGETS+=("$FEATURE_REL")
fi

declare -a FORMAT_FILES=()
for target in "${UNIQUE_FORMAT_TARGETS[@]+"${UNIQUE_FORMAT_TARGETS[@]}"}"; do
    target_abs="$target"
    if [[ "$target_abs" != /* ]]; then
        target_abs="$REPO_ROOT/$target_abs"
    fi
    if [[ -f "$target_abs" ]]; then
        case "$target_abs" in
            *.g.dart|*.freezed.dart)
                continue
                ;;
            *.dart)
                rel="${target_abs#$REPO_ROOT/}"
                FORMAT_FILES+=("$rel")
                ;;
        esac
        continue
    fi
    if [[ -d "$target_abs" ]]; then
        while IFS= read -r file; do
            rel="${file#$REPO_ROOT/}"
            FORMAT_FILES+=("$rel")
        done < <(
            find "$target_abs" -type f -name "*.dart" \
                ! -name "*.g.dart" \
                ! -name "*.freezed.dart" \
                | sort -u
        )
    fi
done

declare -a UNIQUE_FORMAT_FILES=()
for file in "${FORMAT_FILES[@]+"${FORMAT_FILES[@]}"}"; do
    [[ -z "$file" ]] && continue
    already=false
    for existing in "${UNIQUE_FORMAT_FILES[@]+"${UNIQUE_FORMAT_FILES[@]}"}"; do
        if [[ "$existing" == "$file" ]]; then
            already=true
            break
        fi
    done
    if ! $already; then
        UNIQUE_FORMAT_FILES+=("$file")
    fi
done

if [[ ${#UNIQUE_FORMAT_FILES[@]} -eq 0 ]]; then
    echo "WARN: no non-generated Dart files found for format check; skipping dart format."
else
    run_tool "dart format" dart format --output=none --set-exit-if-changed "${UNIQUE_FORMAT_FILES[@]}"
fi

TEST_MODE="scoped"
if $FULL_TEST_SUITE || [[ ${#RESOLVED_TEST_TARGETS[@]} -eq 0 ]]; then
    TEST_MODE="full"
fi

cd "$REPO_ROOT"
if [[ -n "$FEATURE_REL" ]]; then
    run_tool "flutter analyze" flutter analyze "$FEATURE_REL"
fi

if [[ "$TEST_MODE" == "full" ]]; then
    run_tool "flutter test --no-pub" flutter test --no-pub
else
    for target in "${RESOLVED_TEST_TARGETS[@]+"${RESOLVED_TEST_TARGETS[@]}"}"; do
        run_tool "flutter test --no-pub ${target}" flutter test --no-pub "$target"
    done
fi

if $JSON_MODE; then
    if (( ${#DEGRADED_CHECKS[@]} > 0 )); then
        DEGRADED_CHECKS_PAYLOAD="$(printf '%s\n' "${DEGRADED_CHECKS[@]}")"
    else
        DEGRADED_CHECKS_PAYLOAD=""
    fi
    if (( ${#UNIQUE_FORMAT_FILES[@]} > 0 )); then
        UNIQUE_FORMAT_FILES_PAYLOAD="${UNIQUE_FORMAT_FILES[*]}"
    else
        UNIQUE_FORMAT_FILES_PAYLOAD=""
    fi
    if (( ${#RESOLVED_TEST_TARGETS[@]} > 0 )); then
        RESOLVED_TEST_TARGETS_PAYLOAD="${RESOLVED_TEST_TARGETS[*]}"
    else
        RESOLVED_TEST_TARGETS_PAYLOAD=""
    fi
    python3 - \
        "$FEATURE_DIR" \
        "$FEATURE_REL" \
        "$TEST_MODE" \
        "$UNIQUE_FORMAT_FILES_PAYLOAD" \
        "$RESOLVED_TEST_TARGETS_PAYLOAD" \
        "$DEGRADED" \
        "$DEGRADED_CHECKS_PAYLOAD" <<'PY'
import json
import sys

feature_dir = sys.argv[1]
feature_rel = sys.argv[2]
test_mode = sys.argv[3]
format_targets = [x for x in sys.argv[4].split() if x]
test_targets = [x for x in sys.argv[5].split() if x]
degraded = sys.argv[6].lower() == "true"
degraded_checks = [x for x in sys.argv[7].splitlines() if x.strip()]

print(json.dumps({
    "ok": True,
    "feature_dir": feature_dir,
    "analyze_target": feature_rel,
    "test_mode": test_mode,
    "format_targets": format_targets,
    "test_targets": test_targets,
    "degraded": degraded,
    "degraded_checks": degraded_checks,
}, ensure_ascii=False))
PY
else
    echo "OK: implementation quality gate passed"
    if $DEGRADED; then
        echo "WARN: quality gate executed in fallback mode."
        if (( ${#DEGRADED_CHECKS[@]} > 0 )); then
            echo "WARN: degraded_checks=${DEGRADED_CHECKS[*]}"
        fi
    fi
    echo "FEATURE_DIR: $FEATURE_DIR"
    echo "ANALYZE_TARGET: $FEATURE_REL"
    echo "TEST_MODE: $TEST_MODE"
fi
