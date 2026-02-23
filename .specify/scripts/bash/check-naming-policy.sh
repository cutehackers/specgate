#!/usr/bin/env bash

set -euo pipefail

FEATURE_DIR_ARG=""
JSON_MODE=false
STRICT_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature-dir)
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --strict-naming)
            STRICT_MODE=true
            shift
            ;;
        --json)
            JSON_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: check-naming-policy.sh --feature-dir <path> [--strict-naming] [--json]"
            echo "  --feature-dir   Absolute feature directory path (required)"
            echo "  --strict-naming Enforce machine-readable policy in a JSON code block from source file"
            echo "  --json          Output JSON result"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option '$1'." >&2
            exit 1
            ;;
    esac
done

if [[ -z "$FEATURE_DIR_ARG" ]]; then
    echo "ERROR: --feature-dir is required." >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

eval $(get_feature_paths "$FEATURE_DIR_ARG") || exit 1

if [[ -z "$FEATURE_DIR" ]]; then
    echo "ERROR: Failed to resolve feature directory." >&2
    exit 1
fi

python3 - "$NAMING_SOURCE_KIND" "$NAMING_SOURCE_FILE" "$NAMING_POLICY_JSON" "$STRICT_MODE" "$JSON_MODE" <<'PY'
import json
import re
import sys
from pathlib import Path

source_kind = sys.argv[1]
source_file = (sys.argv[2] or "").strip()
policy_text = sys.argv[3] if len(sys.argv) > 3 else "{}"
strict_mode = sys.argv[4] == "true"
json_mode = sys.argv[5] == "true"


required = (
    "entity",
    "dto",
    "use_case",
    "repository",
    "repository_impl",
    "event",
    "controller",
    "data_source",
    "provider",
)
allowed = {
    "entity",
    "dto",
    "use_case",
    "repository",
    "repository_impl",
    "event",
    "controller",
    "data_source",
    "provider",
    "feature",
    "naming",
}


def to_policy(raw_rules):
    if not isinstance(raw_rules, dict):
        return {}
    merged = dict(raw_rules)
    naming_nested = merged.get("naming")
    if isinstance(naming_nested, dict):
        merged = {**merged, **naming_nested}
    return {
        str(key).strip().lower().replace("-", "_"): str(value).strip()
        for key, value in merged.items()
        if key != "naming" and isinstance(value, str) and str(value).strip()
    }


def json_blocks(text: str):
    if not text:
        return []
    pattern = re.compile(
        r"(?ms)(^|\n)\s*```(?P<lang>[A-Za-z0-9_+#-]+)?\s*\n(?P<body>.*?)\n```(?:\s*$|\s*\n)",
    )
    blocks = []
    for match in pattern.finditer(text):
        lang = (match.group("lang") or "").strip().lower()
        if not lang:
            continue
        body = match.group("body").strip()
        if not body:
            continue
        if lang == "json":
            try:
                parsed = json.loads(body)
            except Exception:
                continue
            if isinstance(parsed, dict):
                blocks.append(parsed)
    return blocks


def parse_file_rules(path):
    if not path:
        return {}, []
    p = Path(path)
    if not p.exists():
        return {}, [f"Naming source file not found: {path}"]

    text = p.read_text(encoding="utf-8", errors="ignore")
    parsed = None
    parsed_sources = []
    for parsed_candidate in json_blocks(text):
        parsed_sources.append("json-code-fence")
        candidate = to_policy(parsed_candidate)
        if candidate:
            parsed = candidate
            break

    return parsed, parsed_sources


def parse_policy_text(raw: str):
    try:
        policy = json.loads(raw)
    except Exception:
        return {}
    return to_policy(policy)


policy = to_policy(parse_policy_text(policy_text))
file_policy = {}
file_policy_sources = []
if source_file:
    file_policy, file_policy_sources = parse_file_rules(source_file)

errors = []
warnings = []
strict_block_detected = False
used_policy = policy
used_by = "in-memory"

if strict_mode:
    if source_kind == "DEFAULT" and not source_file:
        errors.append("No resolved naming source file; strict mode requires ARCHITECTURE or CONSTITUTION source.")
    if not source_file:
        errors.append("No naming source file resolved for strict naming mode.")

    if source_file and file_policy:
        strict_block_detected = True
        used_policy = file_policy
        used_by = "source_file"
    elif source_file:
        errors.append("Resolved naming source file does not expose a valid JSON naming block.")
        used_by = "missing_source_block"
        used_policy = {}

    if file_policy_sources:
        seen_blocks = ", ".join(file_policy_sources)
        warnings.append(f"Detected naming block sources: {seen_blocks}")


if not strict_mode and source_file and not file_policy:
    warnings.append(
        "Resolved naming source file does not expose a valid JSON naming block. "
        "Current checks will rely on parser fallback."
    )

if policy == {} and file_policy == {}:
    warnings.append("No naming policy was resolved from source artifacts.")

for required_key in required:
    if required_key not in used_policy:
        if strict_mode:
            errors.append(
                f"Missing required naming rule in strict mode: {required_key}"
            )
        else:
            warnings.append(
                f"Strict-naming baseline rule missing: {required_key}. "
                "Consider adding it to naming policy."
            )

for key in used_policy:
    if key not in allowed:
        warnings.append(f"Unknown naming key '{key}' in resolved policy.")

if strict_mode:
    resolved_ok = not errors
else:
    resolved_ok = not bool(errors)

result = {
    "ok": resolved_ok,
    "strict": strict_mode,
    "source": {
        "kind": source_kind,
        "file": source_file,
        "used_by": used_by,
    },
    "strict_block_detected": strict_block_detected,
    "required_rules": list(required),
    "resolved_policy": used_policy,
    "errors": errors,
    "warnings": warnings,
}

if not json_mode:
    if resolved_ok:
        print(
            f"OK: naming policy resolved from {used_by} "
            f"(kind={source_kind}, source_file={source_file})"
        )
        if warnings:
            print("WARNINGS:")
            for issue in warnings:
                print(f"  - {issue}")
        if policy:
            print("RULES:")
            for key in sorted(used_policy):
                print(f"  - {key}: {used_policy[key]}")
    else:
        print("ERROR: naming policy validation failed:", file=sys.stderr)
        for issue in errors:
            print(f"  - {issue}", file=sys.stderr)
        if warnings:
            print("WARNINGS:", file=sys.stderr)
            for issue in warnings:
                print(f"  - {issue}", file=sys.stderr)
        sys.exit(1)
else:
    print(json.dumps(result, ensure_ascii=False))
    if not resolved_ok:
        sys.exit(1)
