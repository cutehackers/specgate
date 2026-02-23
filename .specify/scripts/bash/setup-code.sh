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
        python3 - "$CODE_DOC" "$naming_source_value" "$NAMING_POLICY_JSON" <<'PY'
import sys
import json
import re
from pathlib import Path
from typing import Dict

path = Path(sys.argv[1])
target = sys.argv[2]
try:
    raw_rules = json.loads(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] else {}
except Exception:
    raw_rules = {}

nested = raw_rules.get("naming") if isinstance(raw_rules, dict) else None
if isinstance(nested, dict):
    merged = {**raw_rules, **nested}
else:
    merged = raw_rules if isinstance(raw_rules, dict) else {}

policy_rules: Dict[str, str] = {
    str(key).lower().replace("-", "_"): str(value).strip()
    for key, value in merged.items()
    if isinstance(value, str)
    and key != "naming"
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

naming_rules_text = (
    ", ".join(f"{k}={v}" for k, v in sorted(policy_rules.items()))
    if policy_rules
    else "No machine-readable naming policy resolved."
)
entity_suffix = policy_rules.get("entity", "{Name}Entity")
dto_suffix = naming_suffix_or_missing(policy_rules.get("dto", ""), "dto")
use_case_suffix = naming_suffix_or_missing(
    policy_rules.get("use_case", ""), "use_case"
)
repository_suffix = naming_suffix_or_missing(
    policy_rules.get("repository", ""), "repository"
)
repository_impl_suffix = naming_suffix_or_missing(
    policy_rules.get("repository_impl", ""), "repository_impl"
)
event_suffix = naming_suffix_or_missing(
    policy_rules.get("event", ""), "event"
)
controller_suffix = naming_suffix_or_missing(
    policy_rules.get("controller", ""), "controller"
)
data_source_suffix = naming_suffix_or_missing(
    policy_rules.get("data_source", ""), "data_source"
)
provider_suffix = naming_suffix_or_missing(
    policy_rules.get("provider", ""), "provider"
)

text = path.read_text(encoding="utf-8")
lines = text.splitlines()
for i, line in enumerate(lines):
    if line.startswith("- **Naming Source**:"):
        lines[i] = f"- **Naming Source**: {target}"
        continue
    if line.startswith("- **Naming Policy Rules**:"):
        lines[i] = f"- **Naming Policy Rules**: {naming_rules_text}"

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
path.write_text(text, encoding="utf-8")
PY
    else
        :
    fi
elif [[ ! -f "$CODE_DOC" ]]; then
    touch "$CODE_DOC"
fi

if $JSON_MODE; then
    printf '{"FEATURE_SPEC":"%s","CODE_DOC":"%s","FEATURE_DIR":"%s","FEATURE_DOCS_DIR":"%s","HAS_GIT":"%s","NAMING_SOURCE_KIND":"%s","NAMING_SOURCE_FILE":"%s","NAMING_SOURCE_REASON":"%s"}\n' \
        "$FEATURE_SPEC" "$CODE_DOC" "$FEATURE_DIR" "$FEATURE_DOCS_DIR" "$HAS_GIT" "$NAMING_SOURCE_KIND" "$NAMING_SOURCE_FILE" "$NAMING_SOURCE_REASON"
else
    echo "FEATURE_SPEC: $FEATURE_SPEC"
    echo "CODE_DOC: $CODE_DOC"
    echo "FEATURE_DIR: $FEATURE_DIR"
    echo "FEATURE_DOCS_DIR: $FEATURE_DOCS_DIR"
    echo "HAS_GIT: $HAS_GIT"
    echo "NAMING_SOURCE_KIND: $NAMING_SOURCE_KIND"
    echo "NAMING_SOURCE_FILE: $NAMING_SOURCE_FILE"
    echo "NAMING_SOURCE_REASON: $NAMING_SOURCE_REASON"
fi
