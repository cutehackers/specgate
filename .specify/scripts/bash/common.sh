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

resolve_naming_source() {
    local feature_dir="$1"
    local repo_root="$2"
    local python_result=""

    NAMING_SOURCE_KIND="DEFAULT"
    NAMING_SOURCE_FILE=""
    NAMING_SOURCE_REASON="No usable naming policy found; repository default naming guardrails apply."

    if [[ -z "$repo_root" ]]; then
        repo_root="$(get_repo_root)"
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        NAMING_SOURCE_REASON="Python unavailable in environment; repository default naming guardrails apply."
        return 0
    fi

    python_result="$(python3 - "$feature_dir" "$repo_root" <<'PY'
import os
import re
import sys
from pathlib import Path

feature_dir = Path(os.path.abspath(sys.argv[1])) if len(sys.argv) > 1 else None
repo_root = Path(os.path.abspath(sys.argv[2])) if len(sys.argv) > 2 else None

if not feature_dir:
    print("kind=DEFAULT")
    print("file=")
    print("reason=No feature directory provided; repository default naming guardrails apply.")
    raise SystemExit

heading_re = re.compile(r"^\s*#{1,4}\s*Naming\s+(Rules|Convention|Policy)\s*$", re.IGNORECASE)
placeholder_re = re.compile(
    r"^(?:\[[ xX]\]\s*)?"
    r"(?:todo|tbd|to be determined|to be defined|n/a|na|none|placeholder)\b.*$",
    re.IGNORECASE,
)
markdown_heading_re = re.compile(r"^\s*#{1,4}\s+\S", re.IGNORECASE)


def is_meaningful_line(line: str) -> bool:
    raw = line.strip()
    if not raw:
        return False
    if raw.startswith('```') or raw.startswith('~~~'):
        return False
    if raw.startswith("<!--") and raw.endswith("-->"):
        return False
    if raw in {"-", "—", "*"}:
        return False

    normalized = re.sub(r"^\s*[-*]\s*(?:\[[ xX]\]\s*)?", "", raw).strip()
    if not normalized:
        return False
    if placeholder_re.match(normalized):
        return False

    return True


def has_meaningful_content(lines: str) -> bool:
    in_code_block = False
    for raw_line in lines.splitlines():
        stripped = raw_line.strip()
        if stripped.startswith('```') or stripped.startswith('~~~'):
            in_code_block = not in_code_block
            continue
        if in_code_block:
            continue
        if markdown_heading_re.match(raw_line):
            continue
        if not is_meaningful_line(raw_line):
            continue
        return True
    return False


def section_text(path: Path):
    if not path.is_file():
        return None

    text = path.read_text(encoding="utf-8", errors="ignore")
    in_section = False
    buffer = []

    in_code_block = False
    for raw_line in text.splitlines():
        if heading_re.match(raw_line):
            in_section = True
            buffer = []
            continue
        if not in_section:
            continue
        if in_section:
            if re.match(r"^\s*#{1,4}\s+\S", raw_line):
                break
            stripped = raw_line.strip()
            if stripped.startswith('```') or stripped.startswith('~~~'):
                in_code_block = not in_code_block
                continue
            if in_code_block:
                continue
            buffer.append(raw_line)

    if not in_section:
        return None
    joined = "\n".join(buffer).strip()
    return joined if has_meaningful_content(joined) else None


def has_meaningful_file(path: Path) -> bool:
    if not path.is_file():
        return False
    text = path.read_text(encoding="utf-8", errors="ignore")
    return has_meaningful_content(text)


arch_candidates = [feature_dir / "docs" / "ARCHITECTURE.md", feature_dir / "docs" / "architecture.md"]
constitution_candidates = [feature_dir / "docs" / "constitution.md", feature_dir / "constitution.md"]
if repo_root is not None:
    constitution_candidates.append(repo_root / ".specify" / "memory" / "constitution.md")

for candidate in arch_candidates:
    if section_text(candidate):
        print("kind=ARCHITECTURE")
        print(f"file={candidate}")
        print("reason=Architecture naming section found and contains concrete rules.")
        raise SystemExit

for candidate in constitution_candidates:
    if has_meaningful_file(candidate):
        print("kind=CONSTITUTION")
        print(f"file={candidate}")
        print("reason=Fallback constitution used per naming policy order.")
        raise SystemExit

print("kind=DEFAULT")
print("file=")
print("reason=No usable naming policy found; repository default naming guardrails apply.")
PY
)"

    if [[ -n "$python_result" ]]; then
        while IFS= read -r pair; do
            case "$pair" in
                kind=*) NAMING_SOURCE_KIND="${pair#kind=}" ;;
                file=*) NAMING_SOURCE_FILE="${pair#file=}" ;;
                reason=*) NAMING_SOURCE_REASON="${pair#reason=}" ;;
            esac
        done <<< "$python_result"
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

    resolve_naming_source "$feature_dir" "$repo_root"

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
    printf 'NAMING_SOURCE_KIND=%q\n' "$NAMING_SOURCE_KIND"
    printf 'NAMING_SOURCE_FILE=%q\n' "$NAMING_SOURCE_FILE"
    printf 'NAMING_SOURCE_REASON=%q\n' "$NAMING_SOURCE_REASON"
}

check_file() { [[ -f "$1" ]] && echo "  ✓ $2" || echo "  ✗ $2"; }
check_dir() {
    [[ -d "$1" && -n "$(ls -A "$1" 2>/dev/null)" ]] && echo "  ✓ $2" || echo "  ✗ $2"
}
