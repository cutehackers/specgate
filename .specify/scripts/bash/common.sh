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
    NAMING_POLICY_JSON="{}"

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
import json

feature_dir = Path(os.path.abspath(sys.argv[1])) if len(sys.argv) > 1 else None
repo_root = Path(os.path.abspath(sys.argv[2])) if len(sys.argv) > 2 else None

if not feature_dir:
    print("kind=DEFAULT")
    print("file=")
    print("reason=No feature directory provided; repository default naming guardrails apply.")
    raise SystemExit

# Accept architecture/constitution variants such as:
# - Naming Rules
# - Naming Conventions
# - Naming Convention
# - Naming Policy
# - File and Class Naming Rules
# - VI. Naming & Code Documentation
heading_re = re.compile(r"^\s*#{1,6}\s+.+$", re.IGNORECASE)
allowed_heading_markers = ("naming",)

placeholder_re = re.compile(
    r"^(?:\[[ xX]\]\s*)?"
    r"(?:todo|tbd|to be determined|to be defined|n/a|na|none|placeholder)\b.*$",
    re.IGNORECASE,
)
markdown_heading_re = re.compile(r"^\s*#{1,4}\s+\S", re.IGNORECASE)


def is_naming_heading(line: str) -> bool:
    raw = line.strip()
    if not heading_re.match(raw):
        return False
    if not raw.startswith("#"):
        return False

    title = re.sub(r"^\s*#{1,6}\s*", "", raw)
    title = re.sub(r"^[0-9IVXivx]+\.\s*", "", title)
    title = title.lower()
    if "naming" not in title:
        return False

    if re.match(r"^naming\b", title):
        return True

    markers = (
        "rule",
        "rules",
        "convention",
        "conventions",
        "policy",
        "guideline",
        "guidelines",
        "standard",
        "standards",
        "documentation",
    )
    return any(marker in title for marker in markers)


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
        if is_naming_heading(raw_line):
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


def parse_naming_rules(path: Path):
    if not path.is_file():
        return {}

    text = path.read_text(encoding="utf-8", errors="ignore")

    def coerce_rules(raw_rules):
        if not isinstance(raw_rules, dict):
            return None

        nested = raw_rules.get("naming")
        if isinstance(nested, dict):
            raw_rules = {**raw_rules, **nested}

        normalized = {}
        for key, value in raw_rules.items():
            if key == "naming":
                continue
            if not isinstance(value, str):
                continue
            normalized[key.lower().replace("-", "_")] = value.strip()

        required = {
            "entity",
            "dto",
            "use_case",
            "repository",
            "repository_impl",
            "event",
            "controller",
            "data_source",
            "provider",
        }
        if not (set(normalized) & required):
            return None

        return normalized if normalized else None

    def parse_fenced_blocks(block_text: str):
        # Match both backtick and tilde fenced blocks, with optional language tag.
        backtick = chr(96) * 3
        fence_re = re.compile(
            r"(?ms)(^|\n)(?P<fence>" + re.escape(backtick) + r"|~{3})\s*(?P<lang>[A-Za-z0-9_-]+)?\s*\n"
            r"(?P<body>.*?)(?=\n(?P=fence)(?:\s|$))"
        )

        for match in fence_re.finditer(block_text):
            lang = (match.group("lang") or "").strip().lower()
            body = match.group("body").strip()
            if not body:
                continue

            if lang != "json":
                continue

            try:
                loaded = json.loads(body)
                normalized = coerce_rules(loaded)
                if normalized:
                    return normalized
            except Exception:
                continue

        return None

    section_only = section_text(path)
    if section_only is None:
        section_only = ""

    parsed = parse_fenced_blocks(section_only)
    if parsed:
        return parsed

    try:
        parsed_json = json.loads(section_only)
        coerce = coerce_rules(parsed_json)
        if coerce:
            return coerce
    except Exception:
        pass

    parsed = parse_fenced_blocks(text)
    if parsed:
        return parsed

    try:
        parsed_json = json.loads(text)
        coerce = coerce_rules(parsed_json)
        if coerce:
            return coerce
    except Exception:
        pass

    return {}


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
    rules = parse_naming_rules(candidate)
    if rules:
        print("rules=" + json.dumps(rules))
        print("kind=ARCHITECTURE")
        print(f"file={candidate}")
        print("reason=Architecture naming section found and contains concrete rules.")
        raise SystemExit

for candidate in constitution_candidates:
    rules = parse_naming_rules(candidate)
    if rules:
        print("rules=" + json.dumps(rules))
        print("kind=CONSTITUTION")
        print(f"file={candidate}")
        print("reason=Fallback constitution used per naming policy order.")
        raise SystemExit

print("rules=" + json.dumps(parse_naming_rules(feature_dir)))
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
                rules=*) NAMING_POLICY_JSON="${pair#rules=}" ;;
            esac
        done <<< "$python_result"
    fi
}

resolve_layer_rules_source() {
    local feature_dir="$1"
    local repo_root="$2"
    local python_output
    local resolved_output
    local layer_rules_loader
    local -a load_layer_args

    layer_rules_loader="${SCRIPT_DIR:-$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/load-layer-rules.sh"

    LAYER_RULES_SOURCE_KIND="DEFAULT"
    LAYER_RULES_SOURCE_FILE=""
    LAYER_RULES_SOURCE_REASON="No resolved layer_rules source found. Using defaults."
    LAYER_RULES_POLICY_JSON="{}"
    LAYER_RULES_RESOLVED_PATH=""
    LAYER_RULES_HAS_LAYER_RULES="false"
    LAYER_RULES_PARSE_EVENTS="[]"
    LAYER_RULES_PARSE_SUMMARY="{}"

    if [[ ! -f "$layer_rules_loader" ]]; then
        LAYER_RULES_SOURCE_REASON="Layer rules loader script is not available; skipping layer policy resolution."
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        LAYER_RULES_SOURCE_REASON="python3 is required for machine-readable layer rules; fallback only."
        return 0
    fi

    load_layer_args=(
        --feature-dir "$feature_dir"
        --repo-root "$repo_root"
        --json
        --no-write-resolved
    )
    if ! python_output="$(bash "$layer_rules_loader" "${load_layer_args[@]}")"; then
        LAYER_RULES_SOURCE_REASON="load-layer-rules.sh failed to resolve layer rules."
        return 1
    fi
    if [[ -z "$python_output" ]]; then
        return 1
    fi

    resolved_output="$(python_output="$python_output" python3 - "$python_output" <<'PY'
import json
import os

raw = os.environ.get("python_output", "")
try:
    payload = json.loads(raw)
except Exception:
    payload = {}

if not isinstance(payload, dict):
    payload = {}
print("LAYER_RULES_SOURCE_KIND=" + payload.get("source_kind", "DEFAULT"))
print("LAYER_RULES_SOURCE_FILE=" + payload.get("source_file", ""))
print("LAYER_RULES_SOURCE_REASON=" + payload.get("source_reason", ""))
print("LAYER_RULES_RESOLVED_PATH=" + payload.get("resolved_path", ""))
print("LAYER_RULES_HAS_LAYER_RULES=" + ("true" if bool(payload.get("has_layer_rules", False)) else "false"))
print(f"LAYER_RULES_PARSE_EVENTS={json.dumps(payload.get('parse_events', []), ensure_ascii=False, separators=(',', ':'))}")
print(f"LAYER_RULES_PARSE_SUMMARY={json.dumps(payload.get('parse_summary', {}), ensure_ascii=False, separators=(',', ':'))}")

policy = payload.get("policy", {})
if not isinstance(policy, dict):
    policy = {}
print(f"LAYER_RULES_POLICY_JSON={json.dumps(policy, ensure_ascii=False, separators=(',', ':'))}")
PY
)"
    if [[ -z "$resolved_output" ]]; then
        return 1
    fi

    while IFS= read -r pair; do
        case "$pair" in
            LAYER_RULES_SOURCE_KIND=*) LAYER_RULES_SOURCE_KIND="${pair#LAYER_RULES_SOURCE_KIND=}" ;;
            LAYER_RULES_SOURCE_FILE=*) LAYER_RULES_SOURCE_FILE="${pair#LAYER_RULES_SOURCE_FILE=}" ;;
            LAYER_RULES_SOURCE_REASON=*) LAYER_RULES_SOURCE_REASON="${pair#LAYER_RULES_SOURCE_REASON=}" ;;
            LAYER_RULES_RESOLVED_PATH=*) LAYER_RULES_RESOLVED_PATH="${pair#LAYER_RULES_RESOLVED_PATH=}" ;;
            LAYER_RULES_HAS_LAYER_RULES=*) LAYER_RULES_HAS_LAYER_RULES="${pair#LAYER_RULES_HAS_LAYER_RULES=}" ;;
            LAYER_RULES_POLICY_JSON=*) LAYER_RULES_POLICY_JSON="${pair#LAYER_RULES_POLICY_JSON=}" ;;
            LAYER_RULES_PARSE_EVENTS=*) LAYER_RULES_PARSE_EVENTS="${pair#LAYER_RULES_PARSE_EVENTS=}" ;;
            LAYER_RULES_PARSE_SUMMARY=*) LAYER_RULES_PARSE_SUMMARY="${pair#LAYER_RULES_PARSE_SUMMARY=}" ;;
        esac
    done <<< "$resolved_output"

    if [[ -z "$LAYER_RULES_SOURCE_KIND" ]]; then
        LAYER_RULES_SOURCE_KIND="DEFAULT"
        LAYER_RULES_SOURCE_REASON="Resolved layer metadata could not be parsed from loader output; using defaults."
    fi
}

get_feature_paths() {
    local feature_dir
    feature_dir=$(require_feature_dir "$1") || true

    if [[ -z "$feature_dir" ]]; then
        echo "ERROR: --feature-dir is required (absolute path to the feature folder)." >&2
        return 1
    fi

    local repo_root=""

    local feature_repo_root
    feature_repo_root="$(cd "$feature_dir" && git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$feature_repo_root" ]]; then
        repo_root="$feature_repo_root"
    else
        repo_root="$(get_repo_root)"
    fi

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
    resolve_layer_rules_source "$feature_dir" "$repo_root"

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
    printf 'NAMING_POLICY_JSON=%q\n' "$NAMING_POLICY_JSON"
    printf 'LAYER_RULES_SOURCE_KIND=%q\n' "$LAYER_RULES_SOURCE_KIND"
    printf 'LAYER_RULES_SOURCE_FILE=%q\n' "$LAYER_RULES_SOURCE_FILE"
    printf 'LAYER_RULES_SOURCE_REASON=%q\n' "$LAYER_RULES_SOURCE_REASON"
    printf 'LAYER_RULES_RESOLVED_PATH=%q\n' "$LAYER_RULES_RESOLVED_PATH"
    printf 'LAYER_RULES_HAS_LAYER_RULES=%q\n' "$LAYER_RULES_HAS_LAYER_RULES"
    printf 'LAYER_RULES_POLICY_JSON=%q\n' "$LAYER_RULES_POLICY_JSON"
    printf 'LAYER_RULES_PARSE_EVENTS=%q\n' "$LAYER_RULES_PARSE_EVENTS"
    printf 'LAYER_RULES_PARSE_SUMMARY=%q\n' "$LAYER_RULES_PARSE_SUMMARY"
}

check_file() { [[ -f "$1" ]] && echo "  ✓ $2" || echo "  ✗ $2"; }
check_dir() {
    [[ -d "$1" && -n "$(ls -A "$1" 2>/dev/null)" ]] && echo "  ✓ $2" || echo "  ✗ $2"
}
