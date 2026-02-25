#!/usr/bin/env bash

set -e

JSON_MODE=false
FEATURE_DIR_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --feature-dir)
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 --feature-dir <path> [--json]"
            echo "  --feature-dir  Absolute path to the feature folder (required)"
            echo "  --json         Output results in JSON format"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option '$1'." >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

eval $(get_feature_paths "$FEATURE_DIR_ARG") || exit 1

mkdir -p "$FEATURE_DIR" "$FEATURE_DOCS_DIR"

TEMPLATE="$REPO_ROOT/.specify/templates/code-template.md"

if [[ ! -f "$CODE_DOC" && -f "$TEMPLATE" ]]; then
    cp "$TEMPLATE" "$CODE_DOC"
    naming_source_value="$NAMING_SOURCE_KIND"
    if [[ -n "$NAMING_SOURCE_FILE" ]]; then
        naming_source_value+=": ${NAMING_SOURCE_FILE}"
    else
        naming_source_value+=": repository default naming guardrails"
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$CODE_DOC" \
            "$naming_source_value" \
            "$NAMING_POLICY_JSON" \
            "$LAYER_RULES_SOURCE_KIND" \
            "$LAYER_RULES_SOURCE_MODE" \
            "$LAYER_RULES_SOURCE_FILE" \
            "$LAYER_RULES_SOURCE_REASON" \
            "$LAYER_RULES_INFERENCE_CONFIDENCE" \
            "$LAYER_RULES_INFERENCE_RULES_EXTRACTED" \
            "$LAYER_RULES_INFERENCE_FALLBACK" \
            "$LAYER_RULES_POLICY_JSON" \
            "$LAYER_RULES_RESOLVED_PATH" \
            "$LAYER_RULES_HAS_LAYER_RULES" \
            <<'PY'
import json
import re
import sys
from pathlib import Path
from typing import Dict, List

path = Path(sys.argv[1])
target = sys.argv[2]

try:
    raw_rules = json.loads(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] else {}
except Exception:
    raw_rules = {}

layer_rules_source_kind = sys.argv[4] if len(sys.argv) > 4 else "DEFAULT"
layer_rules_source_mode = sys.argv[5] if len(sys.argv) > 5 else layer_rules_source_kind
layer_rules_source_file = sys.argv[6] if len(sys.argv) > 6 else ""
layer_rules_source_reason = sys.argv[7] if len(sys.argv) > 7 else ""
try:
    inference_confidence = float(sys.argv[8] if len(sys.argv) > 8 else 0.0)
except Exception:
    inference_confidence = 0.0
try:
    inference_rules_extracted = int(sys.argv[9] if len(sys.argv) > 9 else 0)
except Exception:
    inference_rules_extracted = 0
inference_fallback_applied = parse_bool(sys.argv[10]) if len(sys.argv) > 10 else False
try:
    layer_rules_policy = json.loads(sys.argv[11]) if len(sys.argv) > 11 and sys.argv[11] else {}
except Exception:
    layer_rules_policy = {}

layer_rules_resolved_path = sys.argv[12] if len(sys.argv) > 12 else ""
layer_rules_has_layer_rules = (sys.argv[13].lower() == "true") if len(sys.argv) > 13 else False

if not isinstance(layer_rules_policy, dict):
    layer_rules_policy = {}

nested = raw_rules.get("naming") if isinstance(raw_rules, dict) else None
if isinstance(nested, dict):
    merged = {**raw_rules, **nested}
else:
    merged = raw_rules if isinstance(raw_rules, dict) else {}

policy_rules: Dict[str, str] = {
    str(key).lower().replace("-", "_"): str(value).strip()
    for key, value in merged.items()
    if isinstance(value, str) and key != "naming"
}


def naming_suffix(pattern: str) -> str:
    if not isinstance(pattern, str):
        return ""
    return re.sub(r"\{[^{}]+\}", "", pattern).strip()


def naming_suffix_or_missing(pattern: str, key: str) -> str:
    suffix = naming_suffix(pattern)
    if suffix:
        return suffix
    return f"<MISSING:{key.upper()}>"


def to_list(value) -> List[str]:
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def bulletize(value: str) -> str:
    return f"`{value}`"


def parse_bool(value: str) -> bool:
    if isinstance(value, bool):
        return value
    if not isinstance(value, str):
        return False
    return value.strip().lower() in {"true", "1", "yes", "y"}


naming_rules_text = (
    ", ".join(f"{k}={v}" for k, v in sorted(policy_rules.items()))
    if policy_rules
    else "No machine-readable naming policy resolved."
)
entity_suffix = policy_rules.get("entity", "{Name}Entity")
dto_suffix = naming_suffix_or_missing(policy_rules.get("dto", ""), "dto")
use_case_suffix = naming_suffix_or_missing(policy_rules.get("use_case", ""), "use_case")
repository_suffix = naming_suffix_or_missing(policy_rules.get("repository", ""), "repository")
repository_impl_suffix = naming_suffix_or_missing(
    policy_rules.get("repository_impl", ""), "repository_impl"
)
event_suffix = naming_suffix_or_missing(policy_rules.get("event", ""), "event")
controller_suffix = naming_suffix_or_missing(
    policy_rules.get("controller", ""), "controller"
)
data_source_suffix = naming_suffix_or_missing(
    policy_rules.get("data_source", ""), "data_source"
)
provider_suffix = naming_suffix_or_missing(policy_rules.get("provider", ""), "provider")

layer_rules = layer_rules_policy.get("layer_rules", {})
errors_policy = layer_rules_policy.get("errors", {})
behavior_policy = layer_rules_policy.get("behavior", {})

layer_policy_lines = []

if isinstance(layer_rules, dict):
    for layer_name in ("domain", "data", "presentation"):
        block = layer_rules.get(layer_name)
        if not isinstance(block, dict):
            continue
        forbid_imports = to_list(block.get("forbid_import_patterns"))
        if forbid_imports:
            layer_policy_lines.append(
                f"- {layer_name}: forbid_import_patterns="
                + ", ".join(bulletize(item) for item in forbid_imports)
            )

domain_policy = {}
if isinstance(errors_policy, dict):
    domain_policy = errors_policy.get("policy", {}).get("domain_layer", {})

if isinstance(domain_policy, dict):
    forbidden_exceptions = to_list(domain_policy.get("forbid_exceptions"))
    if forbidden_exceptions:
        layer_policy_lines.append(
            "- domain_layer: forbid_exceptions="
            + ", ".join(bulletize(item) for item in forbidden_exceptions)
        )
    if parse_bool(domain_policy.get("require_result_type")):
        layer_policy_lines.append(
            "- domain_layer: require explicit return types for use-case call methods"
        )

use_case_policy = {}
if isinstance(behavior_policy, dict):
    use_case_policy = behavior_policy.get("use_case", {})

if isinstance(use_case_policy, dict):
    if parse_bool(use_case_policy.get("allow_direct_repository_implementation_use")) is False:
        layer_policy_lines.append(
            "- behavior/use_case: repository_impl direct import in use_case is forbidden"
        )

if not layer_policy_lines:
    layer_policy_lines = ["- No actionable layer policy was resolved."]

layer_rules_summary = "\n".join(layer_policy_lines)

layer_rules_source_line = (
    f"{layer_rules_source_kind}: {layer_rules_source_file}"
    if layer_rules_source_file
    else f"{layer_rules_source_kind}: {layer_rules_source_reason}"
)

text = path.read_text(encoding="utf-8")
lines = text.splitlines()
for i, line in enumerate(lines):
    if line.startswith("- **Naming Source**:"):
        lines[i] = f"- **Naming Source**: {target}"
        continue
    if line.startswith("- **Naming Policy Rules**:"):
        lines[i] = f"- **Naming Policy Rules**: {naming_rules_text}"
    if line.startswith("- **Layer Rules Source**:"):
        lines[i] = f"- **Layer Rules Source**: {layer_rules_source_line}"

text = "\n".join(lines) + ("\n" if text.endswith("\n") else "")
text = text.replace("{{NAMING_RULES}}", naming_rules_text)
text = text.replace("{{ENTITY_SUFFIX}}", entity_suffix)
text = text.replace("{{DTO_SUFFIX}}", dto_suffix)
text = text.replace("{{USE_CASE_SUFFIX}}", use_case_suffix)
text = text.replace("{{REPOSITORY_SUFFIX}}", repository_suffix)
text = text.replace("{{REPOSITORY_IMPL_SUFFIX}}", repository_impl_suffix)
text = text.replace("{{EVENT_SUFFIX}}", event_suffix)
text = text.replace("{{CONTROLLER_SUFFIX}}", controller_suffix)
text = text.replace("{{DATA_SOURCE_SUFFIX}}", data_source_suffix)
text = text.replace("{{PROVIDER_SUFFIX}}", provider_suffix)
text = text.replace("{{LAYER_RULES_SOURCE_KIND}}", layer_rules_source_kind)
text = text.replace("{{LAYER_RULES_SOURCE_FILE}}", layer_rules_source_file)
text = text.replace("{{LAYER_RULES_SOURCE_REASON}}", layer_rules_source_reason)
text = text.replace("{{LAYER_RULES_SOURCE_MODE}}", layer_rules_source_mode)
text = text.replace("{{LAYER_RULES_INFERENCE_CONFIDENCE}}", f"{inference_confidence:.2f}")
text = text.replace("{{LAYER_RULES_INFERENCE_RULES_EXTRACTED}}", str(inference_rules_extracted))
text = text.replace("{{LAYER_RULES_INFERENCE_FALLBACK}}", str(bool(inference_fallback_applied)).lower())
text = text.replace("{{LAYER_RULES_RESOLVED_PATH}}", layer_rules_resolved_path)
text = text.replace(
    "{{LAYER_RULES_HAS_LAYER_RULES}}", "true" if layer_rules_has_layer_rules else "false"
)
text = text.replace("{{LAYER_RULES_SUMMARY}}", layer_rules_summary)
text = text.replace(
    "{{LAYER_RULES_POLICY_JSON}}",
    json.dumps(layer_rules_policy, ensure_ascii=False, sort_keys=True),
)
path.write_text(text, encoding="utf-8")
PY
    else
        :
    fi
elif [[ ! -f "$CODE_DOC" ]]; then
    touch "$CODE_DOC"
fi

if $JSON_MODE; then
    printf '{"FEATURE_SPEC":"%s","CODE_DOC":"%s","FEATURE_DIR":"%s","FEATURE_DOCS_DIR":"%s","HAS_GIT":"%s","NAMING_SOURCE_KIND":"%s","NAMING_SOURCE_FILE":"%s","NAMING_SOURCE_REASON":"%s","LAYER_RULES_SOURCE_KIND":"%s","LAYER_RULES_SOURCE_MODE":"%s","LAYER_RULES_SOURCE_FILE":"%s","LAYER_RULES_SOURCE_REASON":"%s","LAYER_RULES_INFERENCE_CONFIDENCE":"%s","LAYER_RULES_INFERENCE_RULES_EXTRACTED":"%s","LAYER_RULES_INFERENCE_FALLBACK":"%s","LAYER_RULES_POLICY_JSON":%s,"LAYER_RULES_RESOLVED_PATH":"%s","LAYER_RULES_HAS_LAYER_RULES":"%s"}\n' \
        "$FEATURE_SPEC" "$CODE_DOC" "$FEATURE_DIR" "$FEATURE_DOCS_DIR" "$HAS_GIT" "$NAMING_SOURCE_KIND" "$NAMING_SOURCE_FILE" "$NAMING_SOURCE_REASON" \
        "$LAYER_RULES_SOURCE_KIND" "$LAYER_RULES_SOURCE_MODE" "$LAYER_RULES_SOURCE_FILE" "$LAYER_RULES_SOURCE_REASON" "$LAYER_RULES_INFERENCE_CONFIDENCE" "$LAYER_RULES_INFERENCE_RULES_EXTRACTED" "$LAYER_RULES_INFERENCE_FALLBACK" "$LAYER_RULES_POLICY_JSON" "$LAYER_RULES_RESOLVED_PATH" "$LAYER_RULES_HAS_LAYER_RULES"
else
    echo "FEATURE_SPEC: $FEATURE_SPEC"
    echo "CODE_DOC: $CODE_DOC"
    echo "FEATURE_DIR: $FEATURE_DIR"
    echo "FEATURE_DOCS_DIR: $FEATURE_DOCS_DIR"
    echo "HAS_GIT: $HAS_GIT"
    echo "NAMING_SOURCE_KIND: $NAMING_SOURCE_KIND"
    echo "NAMING_SOURCE_FILE: $NAMING_SOURCE_FILE"
    echo "NAMING_SOURCE_REASON: $NAMING_SOURCE_REASON"
    echo "LAYER_RULES_SOURCE_KIND: $LAYER_RULES_SOURCE_KIND"
    echo "LAYER_RULES_SOURCE_MODE: $LAYER_RULES_SOURCE_MODE"
    echo "LAYER_RULES_SOURCE_FILE: $LAYER_RULES_SOURCE_FILE"
    echo "LAYER_RULES_SOURCE_REASON: $LAYER_RULES_SOURCE_REASON"
    echo "LAYER_RULES_INFERENCE_CONFIDENCE: $LAYER_RULES_INFERENCE_CONFIDENCE"
    echo "LAYER_RULES_INFERENCE_RULES_EXTRACTED: $LAYER_RULES_INFERENCE_RULES_EXTRACTED"
    echo "LAYER_RULES_INFERENCE_FALLBACK: $LAYER_RULES_INFERENCE_FALLBACK"
    echo "LAYER_RULES_RESOLVED_PATH: $LAYER_RULES_RESOLVED_PATH"
    echo "LAYER_RULES_HAS_LAYER_RULES: $LAYER_RULES_HAS_LAYER_RULES"
fi
