#!/usr/bin/env bash
# Common functions and variables for all scripts

# Get repository root, with fallback for non-git repositories
get_repo_root() {
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        git rev-parse --show-toplevel
    else
        # Fall back to script location for non-git repos
        local script_dir="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        (cd "$script_dir/../../.." && pwd)
    fi
}

# Check if we have git available
has_git() {
    git rev-parse --show-toplevel >/dev/null 2>&1
}

require_feature_dir() {
    local feature_dir="$1"

    if [[ -n "$feature_dir" ]]; then
        echo "$feature_dir"
        return 0
    fi

    if [[ -n "${SPECIFY_FEATURE_DIR:-}" ]]; then
        echo "$SPECIFY_FEATURE_DIR"
        return 0
    fi

    return 1
}

suggest_feature_dirs() {
    local feature_dir="$1"
    local repo_root="$2"
    local suggestions=""

    if [[ "$feature_dir" == *"/"* ]]; then
        if [[ -d "$repo_root/$feature_dir" ]]; then
            suggestions="$repo_root/$feature_dir"$'\n'
        fi
        suggestions+=$(find "$repo_root" -type d -path "*/$feature_dir" 2>/dev/null | head -n 20)
    else
        suggestions=$(find "$repo_root" -type d -name "$feature_dir" 2>/dev/null | head -n 20)
    fi

    if [[ -n "$suggestions" ]]; then
        echo "Did you mean one of these?" >&2
        printf '%s\n' "$suggestions" | awk 'NF' | sort -u | head -n 10 | sed 's/^/  - /' >&2
        echo "Choose one and re-run with --feature-dir <absolute path>." >&2
    else
        echo "No similar folders found under $repo_root." >&2
    fi
}

get_feature_paths() {
    local feature_dir
    feature_dir=$(require_feature_dir "$1") || true

    if [[ -z "$feature_dir" ]]; then
        echo "ERROR: --feature-dir is required (absolute path to the feature folder)." >&2
        return 1
    fi

    local repo_root
    repo_root=$(get_repo_root)

    if [[ "$feature_dir" != /* ]]; then
        echo "ERROR: --feature-dir must be an absolute path. Got: $feature_dir" >&2
        suggest_feature_dirs "$feature_dir" "$repo_root"
        return 1
    fi

    local has_git_repo="false"

    if has_git; then
        has_git_repo="true"
    fi

    local feature_docs_dir="$feature_dir/docs"

    printf 'REPO_ROOT=%q\n' "$repo_root"
    printf 'HAS_GIT=%q\n' "$has_git_repo"
    printf 'FEATURE_DIR=%q\n' "$feature_dir"
    printf 'FEATURE_DOCS_DIR=%q\n' "$feature_docs_dir"
    printf 'FEATURE_SPEC=%q\n' "$feature_docs_dir/spec.md"
    printf 'CODE_DOC=%q\n' "$feature_docs_dir/tasks.md"
    printf 'RESEARCH=%q\n' "$feature_docs_dir/research.md"
    printf 'DATA_MODEL=%q\n' "$feature_docs_dir/data-model.md"
    printf 'QUICKSTART=%q\n' "$feature_docs_dir/quickstart.md"
    printf 'SCREEN_ABSTRACTION=%q\n' "$feature_docs_dir/screen_abstraction.md"
    printf 'CONTRACTS_DIR=%q\n' "$feature_docs_dir/contracts"
}

check_file() { [[ -f "$1" ]] && echo "  ✓ $2" || echo "  ✗ $2"; }
check_dir() {
    [[ -d "$1" && -n "$(ls -A "$1" 2>/dev/null)" ]] && echo "  ✓ $2" || echo "  ✗ $2"
}
