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

TEST_SPEC="$FEATURE_DOCS_DIR/test-spec.md"
TEMPLATE="$REPO_ROOT/.specify/templates/test-spec-template.md"
if [[ -f "$TEMPLATE" && ! -f "$TEST_SPEC" ]]; then
    cp "$TEMPLATE" "$TEST_SPEC"
elif [[ ! -f "$TEST_SPEC" ]]; then
    touch "$TEST_SPEC"
fi

if $JSON_MODE; then
    printf '{"FEATURE_SPEC":"%s","TEST_SPEC":"%s","FEATURE_DIR":"%s","FEATURE_DOCS_DIR":"%s","HAS_GIT":"%s"}\n' \
        "$FEATURE_SPEC" "$TEST_SPEC" "$FEATURE_DIR" "$FEATURE_DOCS_DIR" "$HAS_GIT"
else
    echo "FEATURE_SPEC: $FEATURE_SPEC"
    echo "TEST_SPEC: $TEST_SPEC"
    echo "FEATURE_DIR: $FEATURE_DIR"
    echo "FEATURE_DOCS_DIR: $FEATURE_DOCS_DIR"
    echo "HAS_GIT: $HAS_GIT"
fi
