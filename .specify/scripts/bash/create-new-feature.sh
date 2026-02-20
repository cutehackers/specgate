#!/usr/bin/env bash

set -e

JSON_MODE=false
SHORT_NAME=""
BRANCH_NUMBER=""
CREATE_BRANCH=false
FEATURE_DIR=""
ARGS=()

require_value() {
    local flag="$1"
    local value="$2"
    if [[ -z "$value" || "$value" == --* ]]; then
        echo "Error: $flag requires a value" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --short-name)
            require_value "$1" "${2:-}"
            SHORT_NAME="$2"
            shift 2
            ;;
        --number)
            require_value "$1" "${2:-}"
            BRANCH_NUMBER="$2"
            shift 2
            ;;
        --feature-dir)
            require_value "$1" "${2:-}"
            FEATURE_DIR="$2"
            shift 2
            ;;
        --create-branch)
            CREATE_BRANCH=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 --feature-dir <path> [--create-branch] [--json] [--short-name <name>] [--number N] <feature_description>"
            echo ""
            echo "Options:"
            echo "  --feature-dir <path> Absolute path to the feature folder (required)"
            echo "  --create-branch     Create a git feature branch (optional)"
            echo "  --json              Output in JSON format"
            echo "  --short-name <name> Provide a custom short name (2-4 words) for the branch"
            echo "  --number N          Specify branch number manually (overrides auto-detection)"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --feature-dir /abs/path/to/feature --create-branch 'Add user authentication system' --short-name 'user-auth'"
            echo "  $0 --feature-dir /abs/path/to/feature 'Implement OAuth2 integration for API'"
            exit 0
            ;;
        --)
            shift
            ARGS+=("$@")
            break
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

FEATURE_DESCRIPTION="${ARGS[*]}"
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Usage: $0 --feature-dir <path> [--create-branch] [--json] [--short-name <name>] [--number N] <feature_description>" >&2
    exit 1
fi

if [ -z "$FEATURE_DIR" ]; then
    echo "Error: --feature-dir is required (absolute path to the feature folder)" >&2
    exit 1
fi

if [[ "$FEATURE_DIR" != /* ]]; then
    echo "Error: --feature-dir must be an absolute path. Got: $FEATURE_DIR" >&2
    exit 1
fi

# Function to find the repository root by searching for existing project markers
find_repo_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -d "$dir/.specify" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

find_package_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/pubspec.yaml" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

get_package_name() {
    local pubspec="$1"
    grep -E '^name:' "$pubspec" 2>/dev/null | head -1 | awk '{print $2}'
}

derive_feature_id() {
    local feature_dir="$1"
    local package_root=""
    local package_name=""
    local relative_path=""

    package_root=$(find_package_root "$feature_dir") || true
    if [ -n "$package_root" ]; then
        package_name=$(get_package_name "$package_root/pubspec.yaml")
        if [ -n "$package_name" ]; then
            relative_path="${feature_dir#$package_root/}"
            echo "${package_name}:${relative_path}"
            return 0
        fi
    fi

    echo "$feature_dir"
}

# Function to get highest number from specs directory
get_highest_from_specs() {
    local specs_dir="$1"
    local highest=0
    
    if [ -d "$specs_dir" ]; then
        for dir in "$specs_dir"/*; do
            [ -d "$dir" ] || continue
            dirname=$(basename "$dir")
            number=$(echo "$dirname" | grep -o '^[0-9]\+' || echo "0")
            number=$((10#$number))
            if [ "$number" -gt "$highest" ]; then
                highest=$number
            fi
        done
    fi
    
    echo "$highest"
}

# Function to get highest number from git branches
get_highest_from_branches() {
    local highest=0
    
    # Get all branches (local and remote)
    branches=$(git branch -a 2>/dev/null || echo "")
    
    if [ -n "$branches" ]; then
        while IFS= read -r branch; do
            # Clean branch name: remove leading markers and remote prefixes
            clean_branch=$(echo "$branch" | sed 's/^[* ]*//; s|^remotes/[^/]*/||')
            
            # Extract feature number if branch matches pattern ###-*
            if echo "$clean_branch" | grep -q '^[0-9]\{3\}-'; then
                number=$(echo "$clean_branch" | grep -o '^[0-9]\{3\}' || echo "0")
                number=$((10#$number))
                if [ "$number" -gt "$highest" ]; then
                    highest=$number
                fi
            fi
        done <<< "$branches"
    fi
    
    echo "$highest"
}

# Function to check existing branches (local and remote) and return next available number
check_existing_branches() {
    local specs_dir="$1"

    # Fetch all remotes to get latest branch info (suppress errors if no remotes)
    git fetch --all --prune 2>/dev/null || true

    # Get highest number from ALL branches (not just matching short name)
    local highest_branch=$(get_highest_from_branches)

    # Get highest number from ALL specs (not just matching short name)
    local highest_spec=$(get_highest_from_specs "$specs_dir")

    # Take the maximum of both
    local max_num=$highest_branch
    if [ "$highest_spec" -gt "$max_num" ]; then
        max_num=$highest_spec
    fi

    # Return next number
    echo $((max_num + 1))
}

# Function to clean and format a branch name
clean_branch_name() {
    local name="$1"
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//'
}

# Resolve repository root. Prefer git information when available, but fall back
# to searching for repository markers so the workflow still functions in repositories that
# were initialised with --no-git.
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT=$(git rev-parse --show-toplevel)
    HAS_GIT=true
else
    REPO_ROOT="$(find_repo_root "$SCRIPT_DIR")"
    if [ -z "$REPO_ROOT" ]; then
        echo "Error: Could not determine repository root. Please run this script from within the repository." >&2
        exit 1
    fi
    HAS_GIT=false
fi

cd "$REPO_ROOT"

SPECS_DIR="$REPO_ROOT/specs"
NAMING_SOURCE_VALUE=""
NAMING_SOURCE_KIND="DEFAULT"
NAMING_SOURCE_FILE=""
NAMING_SOURCE_REASON="No usable naming policy found; repository default naming guardrails apply."
resolve_naming_source "$FEATURE_DIR" "$REPO_ROOT"
if [[ -n "$NAMING_SOURCE_FILE" ]]; then
    NAMING_SOURCE_VALUE="$NAMING_SOURCE_KIND: ${NAMING_SOURCE_FILE}"
else
    NAMING_SOURCE_VALUE="$NAMING_SOURCE_KIND: repository default naming guardrails"
fi

# Function to generate branch name with stop word filtering and length filtering
generate_branch_name() {
    local description="$1"
    
    # Common stop words to filter out
    local stop_words="^(i|a|an|the|to|for|of|in|on|at|by|with|from|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|can|may|might|must|shall|this|that|these|those|my|your|our|their|want|need|add|get|set)$"
    
    # Convert to lowercase and split into words
    local clean_name=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g')
    
    # Filter words: remove stop words and words shorter than 3 chars (unless they're uppercase acronyms in original)
    local meaningful_words=()
    for word in $clean_name; do
        # Skip empty words
        [ -z "$word" ] && continue
        
        # Keep words that are NOT stop words AND (length >= 3 OR are potential acronyms)
        if ! echo "$word" | grep -qiE "$stop_words"; then
            if [ ${#word} -ge 3 ]; then
                meaningful_words+=("$word")
            elif echo "$description" | grep -q "\b${word^^}\b"; then
                # Keep short words if they appear as uppercase in original (likely acronyms)
                meaningful_words+=("$word")
            fi
        fi
    done
    
    # If we have meaningful words, use first 3-4 of them
    if [ ${#meaningful_words[@]} -gt 0 ]; then
        local max_words=3
        if [ ${#meaningful_words[@]} -eq 4 ]; then max_words=4; fi
        
        local result=""
        local count=0
        for word in "${meaningful_words[@]}"; do
            if [ $count -ge $max_words ]; then break; fi
            if [ -n "$result" ]; then result="$result-"; fi
            result="$result$word"
            count=$((count + 1))
        done
        echo "$result"
    else
        # Fallback to original logic if no meaningful words found
        local cleaned=$(clean_branch_name "$description")
        echo "$cleaned" | tr '-' '\n' | grep -v '^$' | head -3 | tr '\n' '-' | sed 's/-$//'
    fi
}

BRANCH_NAME=""
FEATURE_NUM=""

if $CREATE_BRANCH; then
    # Generate branch name
    if [ -n "$SHORT_NAME" ]; then
        # Use provided short name, just clean it up
        BRANCH_SUFFIX=$(clean_branch_name "$SHORT_NAME")
    else
        # Generate from description with smart filtering
        BRANCH_SUFFIX=$(generate_branch_name "$FEATURE_DESCRIPTION")
    fi

    # Determine branch number
    if [ -z "$BRANCH_NUMBER" ]; then
        if [ "$HAS_GIT" = true ]; then
            # Check existing branches on remotes
            BRANCH_NUMBER=$(check_existing_branches "$SPECS_DIR")
        else
            # Fall back to local directory check
            HIGHEST=$(get_highest_from_specs "$SPECS_DIR")
            BRANCH_NUMBER=$((HIGHEST + 1))
        fi
    fi

    # Force base-10 interpretation to prevent octal conversion (e.g., 010 → 8 in octal, but should be 10 in decimal)
    FEATURE_NUM=$(printf "%03d" "$((10#$BRANCH_NUMBER))")
    BRANCH_NAME="${FEATURE_NUM}-${BRANCH_SUFFIX}"

    # GitHub enforces a 244-byte limit on branch names
    # Validate and truncate if necessary
    MAX_BRANCH_LENGTH=244
    if [ ${#BRANCH_NAME} -gt $MAX_BRANCH_LENGTH ]; then
        # Calculate how much we need to trim from suffix
        # Account for: feature number (3) + hyphen (1) = 4 chars
        MAX_SUFFIX_LENGTH=$((MAX_BRANCH_LENGTH - 4))
        
        # Truncate suffix at word boundary if possible
        TRUNCATED_SUFFIX=$(echo "$BRANCH_SUFFIX" | cut -c1-$MAX_SUFFIX_LENGTH)
        # Remove trailing hyphen if truncation created one
        TRUNCATED_SUFFIX=$(echo "$TRUNCATED_SUFFIX" | sed 's/-$//')
        
        ORIGINAL_BRANCH_NAME="$BRANCH_NAME"
        BRANCH_NAME="${FEATURE_NUM}-${TRUNCATED_SUFFIX}"
        
        >&2 echo "[specify] Warning: Branch name exceeded GitHub's 244-byte limit"
        >&2 echo "[specify] Original: $ORIGINAL_BRANCH_NAME (${#ORIGINAL_BRANCH_NAME} bytes)"
        >&2 echo "[specify] Truncated to: $BRANCH_NAME (${#BRANCH_NAME} bytes)"
    fi

    if [ "$HAS_GIT" = true ]; then
        git checkout -b "$BRANCH_NAME"
    else
        >&2 echo "[specify] Warning: Git repository not detected; skipped branch creation for $BRANCH_NAME"
    fi
fi

mkdir -p "$FEATURE_DIR"

FEATURE_DOCS_DIR="$FEATURE_DIR/docs"
mkdir -p "$FEATURE_DOCS_DIR"
FEATURE_ID="$(derive_feature_id "$FEATURE_DIR")"

TEMPLATE="$REPO_ROOT/.specify/templates/spec-template.md"
SPEC_FILE="$FEATURE_DOCS_DIR/spec.md"
SPEC_INITIALIZED=false
if [ -f "$SPEC_FILE" ]; then
    # Idempotent behavior: never overwrite an existing spec file.
    SPEC_INITIALIZED=false
elif [ -f "$TEMPLATE" ]; then
    cp "$TEMPLATE" "$SPEC_FILE"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$SPEC_FILE" "$NAMING_SOURCE_VALUE" <<'PY'
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
    fi
    SPEC_INITIALIZED=true
else
    touch "$SPEC_FILE"
    SPEC_INITIALIZED=true
fi

# Set the SPECIFY_FEATURE_DIR environment variable for the current session
export SPECIFY_FEATURE_DIR="$FEATURE_DIR"

if $JSON_MODE; then
    printf '{"FEATURE_DIR":"%s","FEATURE_DOCS_DIR":"%s","FEATURE_ID":"%s","SPEC_FILE":"%s","BRANCH_NAME":"%s","FEATURE_NUM":"%s","SPEC_INITIALIZED":%s,"NAMING_SOURCE_KIND":"%s","NAMING_SOURCE_FILE":"%s","NAMING_SOURCE_REASON":"%s"}\n' \
        "$FEATURE_DIR" "$FEATURE_DOCS_DIR" "$FEATURE_ID" "$SPEC_FILE" "$BRANCH_NAME" "$FEATURE_NUM" "$SPEC_INITIALIZED" "$NAMING_SOURCE_KIND" "$NAMING_SOURCE_FILE" "$NAMING_SOURCE_REASON"
else
    if $CREATE_BRANCH; then
        echo "BRANCH_NAME: $BRANCH_NAME"
        echo "FEATURE_NUM: $FEATURE_NUM"
    fi
    echo "FEATURE_DIR: $FEATURE_DIR"
    echo "FEATURE_DOCS_DIR: $FEATURE_DOCS_DIR"
    echo "FEATURE_ID: $FEATURE_ID"
    echo "SPEC_FILE: $SPEC_FILE"
    echo "SPEC_INITIALIZED: $SPEC_INITIALIZED"
    echo "NAMING_SOURCE_KIND: $NAMING_SOURCE_KIND"
    echo "NAMING_SOURCE_FILE: $NAMING_SOURCE_FILE"
    echo "NAMING_SOURCE_REASON: $NAMING_SOURCE_REASON"
    echo "SPECIFY_FEATURE_DIR environment variable set to: $FEATURE_DIR"
fi
