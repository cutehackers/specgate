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
        python3 - "$CODE_DOC" "$naming_source_value" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
target = sys.argv[2]

text = path.read_text(encoding="utf-8")
lines = text.splitlines()
for i, line in enumerate(lines):
    if line.startswith("- **Naming Source**:"):
        lines[i] = f"- **Naming Source**: {target}"
        break
path.write_text("\n".join(lines) + ("\n" if text.endswith("\n") else ""), encoding="utf-8")
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
