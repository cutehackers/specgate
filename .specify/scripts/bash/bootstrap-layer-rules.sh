#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT_ARG=""
FEATURE_DIR_ARG=""
FEATURE_ID_ARG=""
FORCE=false
CREATE_OVERRIDE=true
JSON_MODE=false

usage() {
    cat <<'USAGE'
Usage: bootstrap-layer-rules.sh [options]

Options:
  --repo-root <path>        Repository root used for .specify/layer_rules
  --feature-dir <abs-path>  Absolute path of a feature folder
  --feature-id <id>         Explicit feature id for override filename
  --force                   Overwrite existing files
  --no-override             Skip feature override file creation
  --json                    Print JSON output
  --help                    Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root)
            REPO_ROOT_ARG="$2"
            shift 2
            ;;
        --feature-dir)
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --feature-id)
            FEATURE_ID_ARG="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --no-override)
            CREATE_OVERRIDE=false
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

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$REPO_ROOT_ARG" ]]; then
    if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
        source "$SCRIPT_DIR/common.sh"
        REPO_ROOT_ARG="$(get_repo_root)"
    else
        REPO_ROOT_ARG="$(cd "$SCRIPT_DIR/../../.." && pwd)"
    fi
fi

REPO_ROOT="$REPO_ROOT_ARG"
LAYER_RULES_ROOT="$REPO_ROOT/.specify/layer_rules"
CONTRACT_TEMPLATE=""

if [[ -f "$REPO_ROOT/.specify/templates/layer-rules-template.yaml" ]]; then
    CONTRACT_TEMPLATE="$REPO_ROOT/.specify/templates/layer-rules-template.yaml"
elif [[ -f "$SCRIPT_DIR/../../templates/layer-rules-template.yaml" ]]; then
    CONTRACT_TEMPLATE="$SCRIPT_DIR/../../templates/layer-rules-template.yaml"
elif [[ -f "$SCRIPT_DIR/../templates/layer-rules-template.yaml" ]]; then
    # Backward-compatible fallback for repositories that keep scripts under a deeper tree.
    CONTRACT_TEMPLATE="$SCRIPT_DIR/../templates/layer-rules-template.yaml"
fi
CONTRACT_PATH="$LAYER_RULES_ROOT/contract.yaml"
OVERRIDE_DIR="$LAYER_RULES_ROOT/overrides"

if [[ ! -f "$CONTRACT_TEMPLATE" ]]; then
    echo "ERROR: layer rules template not found: $CONTRACT_TEMPLATE" >&2
    exit 1
fi

OVERRIDE_SKIPPED_REASON=""
if [[ "$CREATE_OVERRIDE" == true && -z "$FEATURE_DIR_ARG" && -z "$FEATURE_ID_ARG" ]]; then
    CREATE_OVERRIDE=false
    OVERRIDE_SKIPPED_REASON="No feature context provided."
fi

temp_id_file="$(mktemp)"
python3 - "$REPO_ROOT" "$FEATURE_DIR_ARG" "$FEATURE_ID_ARG" <<'PY' > "$temp_id_file"
import re
import sys
from pathlib import Path

repo_root = Path(sys.argv[1]).resolve()
feature_dir_raw = (sys.argv[2] or "").strip()
feature_id_raw = (sys.argv[3] or "").strip()


def resolve_feature_id_seed(feature_path: Path, repo_root: Path, fallback: str) -> str:
    try:
        return str(feature_path.relative_to(repo_root))
    except Exception:
        return fallback


if feature_id_raw:
    value = feature_id_raw
else:
    if not feature_dir_raw:
        print("")
        raise SystemExit
    try:
        feature_path = Path(feature_dir_raw).resolve()
        value = resolve_feature_id_seed(feature_path, repo_root, str(feature_path))
    except Exception:
        value = feature_dir_raw

value = value.strip().replace("\\", "/")
value = value.replace("/", "-")
value = re.sub(r"[^A-Za-z0-9._-]", "-", value).strip("-").strip(".")
print(value or "feature")
PY

FEATURE_ID=""
if [[ -f "$temp_id_file" ]]; then
    FEATURE_ID="$(cat "$temp_id_file")"
    rm -f "$temp_id_file"
fi

mkdir -p "$LAYER_RULES_ROOT" "$OVERRIDE_DIR"

contract_created=false
contract_overwritten=false
if [[ ! -f "$CONTRACT_PATH" || "$FORCE" == true ]]; then
    if [[ -f "$CONTRACT_PATH" ]]; then
        contract_overwritten=true
    fi
    cp "$CONTRACT_TEMPLATE" "$CONTRACT_PATH"
    contract_created=true
fi

override_path=""
override_created=false
override_overwritten=false
if [[ "$CREATE_OVERRIDE" == true ]]; then
    override_path="$OVERRIDE_DIR/$FEATURE_ID.yaml"
    if [[ ! -f "$override_path" || "$FORCE" == true ]]; then
        if [[ -f "$override_path" ]]; then
            override_overwritten=true
        fi
        cp "$CONTRACT_TEMPLATE" "$override_path"
        override_created=true
    fi
fi

if $JSON_MODE; then
    printf '{'
    printf '"ok":true,'
    printf '"repo_root":"%s",' "$(printf '%s' "$REPO_ROOT" | sed 's/"/\\"/g')"
    printf '"contract_path":"%s",' "$(printf '%s' "$CONTRACT_PATH" | sed 's/"/\\"/g')"
    printf '"contract_created":%s,' "$contract_created"
    printf '"contract_overwritten":%s,' "$contract_overwritten"
    printf '"override_path":"%s",' "$(printf '%s' "$override_path" | sed 's/"/\\"/g')"
    printf '"override_created":%s,' "$override_created"
    printf '"override_overwritten":%s,' "$override_overwritten"
    printf '"feature_id":"%s",' "$FEATURE_ID"
    printf '"force":%s,' "$FORCE"
    printf '"create_override":%s' "$CREATE_OVERRIDE"
    printf '}\n'
else
    echo "Bootstrap completed: .specify/layer_rules"
    if [[ "$contract_created" == true ]]; then
        if [[ "$contract_overwritten" == true ]]; then
            echo "  OVERWRITTEN: $CONTRACT_PATH"
        else
            echo "  CREATED: $CONTRACT_PATH"
        fi
    else
        echo "  EXISTS: $CONTRACT_PATH"
    fi

    if [[ "$CREATE_OVERRIDE" == true ]]; then
        if [[ "$override_created" == true ]]; then
            if [[ "$override_overwritten" == true ]]; then
                echo "  OVERWRITTEN: $override_path"
            else
                echo "  CREATED: $override_path"
            fi
        else
            echo "  EXISTS: $override_path"
        fi
    elif [[ "$OVERRIDE_SKIPPED_REASON" == "No feature context provided." ]]; then
        echo "INFO: override file generation skipped ($OVERRIDE_SKIPPED_REASON)."
        echo "      Run with --feature-dir/--feature-id to create .specify/layer_rules/overrides/<feature-id>.yaml."
    elif [[ "$CREATE_OVERRIDE" == false ]]; then
        echo "INFO: override generation skipped by --no-override."
    fi

    if [[ "$CREATE_OVERRIDE" == true ]] && [[ -z "$FEATURE_ID" ]]; then
        echo "No feature override generated (feature id not provided)."
    fi
    echo "Use:"
    echo "  .specify/scripts/bash/load-layer-rules.sh --source-dir <feature-path> --json"
    echo "  (or --feature-dir for backward compatibility)"
    echo "to verify resolution."
fi
