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
elif [[ ! -f "$CODE_DOC" ]]; then
    touch "$CODE_DOC"
fi

if $JSON_MODE; then
    printf '{"FEATURE_SPEC":"%s","CODE_DOC":"%s","FEATURE_DIR":"%s","FEATURE_DOCS_DIR":"%s","HAS_GIT":"%s"}\n' \
        "$FEATURE_SPEC" "$CODE_DOC" "$FEATURE_DIR" "$FEATURE_DOCS_DIR" "$HAS_GIT"
else
    echo "FEATURE_SPEC: $FEATURE_SPEC"
    echo "CODE_DOC: $CODE_DOC"
    echo "FEATURE_DIR: $FEATURE_DIR"
    echo "FEATURE_DOCS_DIR: $FEATURE_DOCS_DIR"
    echo "HAS_GIT: $HAS_GIT"
fi
