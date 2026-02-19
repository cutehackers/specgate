#!/usr/bin/env bash

set -e

JSON_MODE=false
PATHS_ONLY=false
FEATURE_DIR_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --paths-only)
            PATHS_ONLY=true
            shift
            ;;
        --feature-dir)
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --help|-h)
            cat << 'USAGE'
Usage: check-prerequisites.sh [OPTIONS]

OPTIONS:
  --feature-dir <path>  Absolute path to the feature folder (required)
  --json                Output in JSON format
  --paths-only          Only output path variables (no validation)
USAGE
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

if $PATHS_ONLY; then
    if $JSON_MODE; then
        printf '{"REPO_ROOT":"%s","FEATURE_DIR":"%s","FEATURE_DOCS_DIR":"%s","FEATURE_SPEC":"%s","CODE_DOC":"%s","RESEARCH":"%s","DATA_MODEL":"%s","QUICKSTART":"%s","SCREEN_ABSTRACTION":"%s","CONTRACTS_DIR":"%s"}\n' \
            "$REPO_ROOT" "$FEATURE_DIR" "$FEATURE_DOCS_DIR" "$FEATURE_SPEC" "$CODE_DOC" "$RESEARCH" "$DATA_MODEL" "$QUICKSTART" "$SCREEN_ABSTRACTION" "$CONTRACTS_DIR"
    else
        echo "REPO_ROOT: $REPO_ROOT"
        echo "FEATURE_DIR: $FEATURE_DIR"
        echo "FEATURE_DOCS_DIR: $FEATURE_DOCS_DIR"
        echo "FEATURE_SPEC: $FEATURE_SPEC"
        echo "CODE_DOC: $CODE_DOC"
        echo "RESEARCH: $RESEARCH"
        echo "DATA_MODEL: $DATA_MODEL"
        echo "QUICKSTART: $QUICKSTART"
        echo "SCREEN_ABSTRACTION: $SCREEN_ABSTRACTION"
        echo "CONTRACTS_DIR: $CONTRACTS_DIR"
    fi
    exit 0
fi

if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "ERROR: Feature directory not found: $FEATURE_DIR" >&2
    exit 1
fi

if [[ ! -d "$FEATURE_DOCS_DIR" ]]; then
    echo "ERROR: docs/ directory not found: $FEATURE_DOCS_DIR" >&2
    exit 1
fi

if [[ ! -f "$FEATURE_SPEC" ]]; then
    echo "ERROR: spec.md not found in $FEATURE_DOCS_DIR" >&2
    exit 1
fi

if [[ ! -f "$CODE_DOC" ]]; then
    echo "ERROR: code.md not found in $FEATURE_DOCS_DIR" >&2
    echo "Run /codify first to create the implementation code spec." >&2
    exit 1
fi

docs=("spec.md" "code.md")
[[ -f "$RESEARCH" ]] && docs+=("research.md")
[[ -f "$DATA_MODEL" ]] && docs+=("data-model.md")
[[ -f "$QUICKSTART" ]] && docs+=("quickstart.md")
[[ -f "$SCREEN_ABSTRACTION" ]] && docs+=("screen_abstraction.md")
if [[ -d "$CONTRACTS_DIR" ]] && [[ -n "$(ls -A "$CONTRACTS_DIR" 2>/dev/null)" ]]; then
    docs+=("contracts/")
fi

if $JSON_MODE; then
    json_docs=$(printf '"%s",' "${docs[@]}")
    json_docs="[${json_docs%,}]"
    printf '{"FEATURE_DIR":"%s","FEATURE_DOCS_DIR":"%s","AVAILABLE_DOCS":%s}\n' "$FEATURE_DIR" "$FEATURE_DOCS_DIR" "$json_docs"
else
    echo "FEATURE_DIR:$FEATURE_DIR"
    echo "FEATURE_DOCS_DIR:$FEATURE_DOCS_DIR"
    echo "AVAILABLE_DOCS:"
    printf '  ✓ %s\n' "${docs[@]}"
fi
