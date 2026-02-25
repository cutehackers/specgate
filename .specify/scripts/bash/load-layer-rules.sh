#!/usr/bin/env bash

set -euo pipefail

POLICY_SOURCE_DIR_ARG=""
FEATURE_DIR_ARG=""
FEATURE_ID_ARG=""
REPO_ROOT_ARG=""
OUTPUT_JSON=false
WRITE_CONTRACT=false
FORCE_CONTRACT=false
CONTRACT_PATH_ARG=""
WRITE_RESOLVED=true

usage() {
    cat <<'USAGE'
Usage: load-layer-rules.sh --source-dir <path> [--feature-id <id>] [--repo-root <path>] [--json]
  --source-dir <path>       Feature policy source file or folder (supports relative path)
                           Supports fixed files under this directory or a direct file:
                           - docs/ARCHITECTURE.md
                           - docs/architecture.md
                           - docs/constitution.md
                           - constitution.md
                           - any readable file containing parseable policy payload
  Requires Python YAML parser:
  - PyYAML (recommended), or
  - ruamel.yaml
  --feature-dir <path>      Backward-compatible alias for --source-dir
  --feature-id <id>         Override/resolved cache key (feature-id)
  --repo-root <path>        Repository root used to resolve relative paths (defaults to this repo).
  --write-contract          Write resolved layer policy into .specify/layer_rules/contract.yaml
  --force-contract          Replace existing contract.yaml when writing
  --no-write-resolved       Skip writing .specify/layer_rules/resolved/<feature-id>.json
  --contract-path <path>    Destination for resolved contract write (default: .specify/layer_rules/contract.yaml)

Load layer rules from repository/feature policy sources and print resolved policy.
USAGE
}

require_arg() {
    local option_name="$1"
    local value="${2-}"

    if [[ -z "$value" || "$value" == --* ]]; then
        echo "ERROR: $option_name requires an argument." >&2
        usage >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-dir)
            require_arg "--source-dir" "${2-}"
            POLICY_SOURCE_DIR_ARG="$2"
            shift 2
            ;;
        --feature-dir)
            require_arg "--feature-dir" "${2-}"
            FEATURE_DIR_ARG="$2"
            if [[ -z "$POLICY_SOURCE_DIR_ARG" ]]; then
                POLICY_SOURCE_DIR_ARG="$2"
            fi
            shift 2
            ;;
        --feature-id)
            require_arg "--feature-id" "${2-}"
            FEATURE_ID_ARG="$2"
            shift 2
            ;;
        --repo-root)
            require_arg "--repo-root" "${2-}"
            REPO_ROOT_ARG="$2"
            shift 2
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --write-contract)
            WRITE_CONTRACT=true
            shift
            ;;
        --force-contract)
            FORCE_CONTRACT=true
            shift
            ;;
        --no-write-resolved)
            WRITE_RESOLVED=false
            shift
            ;;
        --contract-path)
            require_arg "--contract-path" "${2-}"
            CONTRACT_PATH_ARG="$2"
            shift 2
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

if [[ -z "${POLICY_SOURCE_DIR_ARG}" ]]; then
    echo "ERROR: --source-dir is required." >&2
    usage >&2
    exit 1
fi
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT_ARG:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
if [[ ! -d "$REPO_ROOT" ]]; then
    echo "ERROR: --repo-root must be an existing directory: $REPO_ROOT" >&2
    exit 1
fi

if [[ "$POLICY_SOURCE_DIR_ARG" = /* ]]; then
    POLICY_SOURCE_DIR="$POLICY_SOURCE_DIR_ARG"
else
    POLICY_SOURCE_DIR="$REPO_ROOT/$POLICY_SOURCE_DIR_ARG"
fi
if [[ ! -e "$POLICY_SOURCE_DIR" ]]; then
    echo "ERROR: --source-dir must be an existing file or directory: $POLICY_SOURCE_DIR_ARG" >&2
    echo "       (resolved to: $POLICY_SOURCE_DIR)" >&2
    exit 1
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
POLICY_SOURCE_DIR="$(cd "$(dirname "$POLICY_SOURCE_DIR")" && pwd)/$(basename "$POLICY_SOURCE_DIR")"

python3 - "$REPO_ROOT" "$POLICY_SOURCE_DIR" "$FEATURE_ID_ARG" "$WRITE_CONTRACT" "$FORCE_CONTRACT" "$CONTRACT_PATH_ARG" "$WRITE_RESOLVED" <<'PY'
import json
import re
import sys
from pathlib import Path

repo_root = Path(sys.argv[1]).resolve()
policy_source_dir = Path(sys.argv[2]).resolve()
requested_feature_id = (sys.argv[3] if len(sys.argv) > 3 else "").strip()
write_contract = (str(sys.argv[4]).lower() in {"1", "true", "yes", "on"}) if len(sys.argv) > 4 else False
force_contract = (str(sys.argv[5]).lower() in {"1", "true", "yes", "on"}) if len(sys.argv) > 5 else False
requested_contract_path = (sys.argv[6] if len(sys.argv) > 6 else "").strip()
write_resolved = (str(sys.argv[7]).lower() in {"1", "true", "yes", "on"}) if len(sys.argv) > 7 else True

if requested_contract_path:
    contract_path_base = Path(requested_contract_path).expanduser()
    if not contract_path_base.is_absolute():
        contract_path = repo_root / contract_path_base
    else:
        contract_path = contract_path_base
else:
    contract_path = repo_root / ".specify" / "layer_rules" / "contract.yaml"

def normalize_name(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    normalized = re.sub(r"[^A-Za-z0-9._-]", "-", value).strip("-").strip(".")
    return normalized or "feature"

def parse_scalar(value: str):
    raw = value.strip()
    if not raw:
        return ""
    if (raw.startswith('"') and raw.endswith('"')) or (raw.startswith("'") and raw.endswith("'")):
        return raw[1:-1]

    lower = raw.lower()
    if lower == "true":
        return True
    if lower == "false":
        return False

    if re.fullmatch(r"-?\d+", raw):
        try:
            return int(raw)
        except Exception:
            return raw
    if re.fullmatch(r"-?\d+\.\d+", raw):
        try:
            return float(raw)
        except Exception:
            return raw

    return raw

errors = []
warnings = []
parser_events = []

def _append_parser_event(
    source,
    parser,
    candidate_type,
    candidate_index,
    status,
    code,
    message="",
    line=None,
    column=None,
):
    event = {
        "source": source,
        "parser": parser,
        "candidate_type": candidate_type,
        "candidate_index": candidate_index,
        "status": status,
        "code": code,
        "message": (message or "").strip(),
    }
    if line is not None:
        event["line"] = int(line)
    if column is not None:
        event["column"] = int(column)
    parser_events.append(event)

def _extract_error_position(message: str):
    if not message:
        return None, None
    match = re.search(r"line\\s+(\\d+)(?:,\\s*column\\s+(\\d+))?", str(message), flags=re.IGNORECASE)
    if not match:
        return None, None
    line = int(match.group(1))
    col = match.group(2)
    return line, int(col) if col is not None else None

def parse_yaml_subset(text: str):
    raw_lines = [line.rstrip("\n") for line in text.splitlines()]
    if not raw_lines:
        return {}

    def parse_value_line(line_value: str):
        if not line_value:
            return {}

        parsed = parse_scalar(line_value)
        if isinstance(parsed, str):
            try:
                return json.loads(parsed)
            except Exception:
                return parsed
        return parsed

    def parse_map(start_index, base_indent):
        out = {}
        index = start_index
        while index < len(raw_lines):
            raw = raw_lines[index]
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                index += 1
                continue

            indent = len(raw) - len(raw.lstrip(" "))
            if indent < base_indent:
                break
            if indent > base_indent:
                index += 1
                continue

            if not re.match(r"[^:\-][^:]*:", stripped):
                index += 1
                continue

            key_match = re.match(r"([^:]+):(?:\s*(.*))?$", stripped)
            if not key_match:
                index += 1
                continue

            key = key_match.group(1).strip()
            raw_value = (key_match.group(2) or "").strip()

            if raw_value:
                out[key] = parse_value_line(raw_value)
                index += 1
                continue

            child_indent = indent + 2
            nested, new_index, is_block_list = parse_nested(index + 1, child_indent)
            out[key] = [] if is_block_list else nested
            index = new_index

        return out, index

    def parse_list(start_index, base_indent):
        out = []
        index = start_index
        while index < len(raw_lines):
            raw = raw_lines[index]
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                index += 1
                continue

            indent = len(raw) - len(raw.lstrip(" "))
            if indent < base_indent:
                break
            if indent > base_indent:
                index += 1
                continue
            if not stripped.startswith("- "):
                break

            item_content = stripped[2:].strip()
            if not item_content:
                nested, new_index, is_list = parse_nested(index + 1, indent + 2)
                out.append([] if is_list else nested)
                index = new_index
                continue

            pair = re.match(r"([^:]+):\s*(.*)$", item_content)
            if pair:
                child_key = pair.group(1).strip()
                child_value = pair.group(2).strip()
                if child_value:
                    out.append({child_key: parse_value_line(child_value)})
                else:
                    nested, new_index, is_list = parse_nested(index + 1, indent + 2)
                    out.append({child_key: [] if is_list else nested})
                    index = new_index
            else:
                out.append(parse_value_line(item_content))
            index += 1

        return out, index

    def parse_nested(start_index, child_indent):
        if start_index >= len(raw_lines):
            return {}, start_index, False

        j = start_index
        while j < len(raw_lines):
            first = raw_lines[j].strip()
            if not first or first.startswith("#"):
                j += 1
                continue
            indent = len(raw_lines[j]) - len(raw_lines[j].lstrip(" "))
            if indent < child_indent:
                return {}, start_index, False
            break

        if j >= len(raw_lines):
            return {}, start_index, False

        next_line = raw_lines[j].strip()
        if next_line.startswith("- "):
            nested_list, next_index = parse_list(j, indent if indent > child_indent else child_indent)
            return nested_list, next_index, True

        nested_map, next_index = parse_map(j, indent if indent > child_indent else child_indent)
        return nested_map, next_index, False

    parsed, _ = parse_map(0, 0)
    return parsed

def parse_yaml_blocks(content: str):
    blocks = []
    for match in re.finditer(
        r"(?ms)(^|\n)```(?:yaml|yml)\s*\n(.*?)\n```",
        content,
    ):
        blocks.append(match.group(2))
    return blocks

def parse_json_blocks(content: str):
    blocks = []
    for match in re.finditer(
        r"(?ms)(^|\n)```(?:json|JSON)\s*\n(.*?)\n```",
        content,
    ):
        blocks.append(match.group(2))
    return blocks

def parse_yaml_with_library(text: str, source: str, candidate_type: str, candidate_index: str):
    parse_errors = []
    _append_parser_event(
        source=source,
        parser="pyyaml",
        candidate_type=candidate_type,
        candidate_index=candidate_index,
        status="attempt",
        code="PY_YAML_PARSE_ATTEMPT",
        message="Attempted to parse candidate payload with PyYAML.",
    )
    _append_parser_event(
        source=source,
        parser="ruamel",
        candidate_type=candidate_type,
        candidate_index=candidate_index,
        status="attempt",
        code="RUAMEL_PARSE_ATTEMPT",
        message="Attempted to parse candidate payload with ruamel.yaml.",
    )

    try:
        import yaml  # type: ignore
        parsed = yaml.safe_load(text)
        _append_parser_event(
            source=source,
            parser="pyyaml",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="success",
            code="PY_YAML_PARSE_SUCCESS",
            message="Parsed candidate payload using PyYAML.",
        )
        return parsed
    except Exception as err:
        parse_error = f"{source}: PyYAML parse error ({err})"
        parse_errors.append(parse_error)
        line_no, col_no = _extract_error_position(str(err))
        _append_parser_event(
            source=source,
            parser="pyyaml",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="failed",
            code="PY_YAML_PARSE_ERROR",
            message=parse_error,
            line=line_no,
            column=col_no,
        )
        warnings.append(f"{parse_error}; trying alternative parser.")

    try:
        from ruamel.yaml import YAML  # type: ignore
        loader = YAML(typ="safe")
        parsed = loader.load(text)
        _append_parser_event(
            source=source,
            parser="ruamel",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="success",
            code="RUAMEL_PARSE_SUCCESS",
            message="Parsed candidate payload using ruamel.yaml.",
        )
        return parsed
    except Exception as err:
        parse_error = f"{source}: ruamel.yaml parse error ({err})"
        parse_errors.append(parse_error)
        if "No module named" in parse_error:
            _append_parser_event(
                source=source,
                parser="ruamel",
                candidate_type=candidate_type,
                candidate_index=candidate_index,
                status="failed",
                code="RUAMEL_IMPORT_ERROR",
                message=parse_error,
            )
        else:
            line_no, col_no = _extract_error_position(str(err))
            _append_parser_event(
                source=source,
                parser="ruamel",
                candidate_type=candidate_type,
                candidate_index=candidate_index,
                status="failed",
                code="RUAMEL_PARSE_ERROR",
                message=parse_error,
                line=line_no,
                column=col_no,
            )
        if len(parse_errors) > 1:
            warnings.append(f"{source}: ruamel.yaml parse error ({err}); no compatible parser succeeded.")

    if parse_errors:
        has_import_errors = all("No module named" in item for item in parse_errors)
        if has_import_errors:
            _append_parser_event(
                source=source,
                parser="yaml",
                candidate_type=candidate_type,
                candidate_index=candidate_index,
                status="failed",
                code="NO_YAML_PARSER_AVAILABLE",
                message=(
                    f"{source}: no YAML parser available. Install PyYAML or ruamel.yaml "
                    "before running layer rule resolution."
                ),
            )
            errors.append(
                f"{source}: no YAML parser available. Install PyYAML or ruamel.yaml before running layer rule resolution."
            )
        elif len(parse_errors) > 1:
            joined = " | ".join(parse_errors)
            _append_parser_event(
                source=source,
                parser="yaml",
                candidate_type=candidate_type,
                candidate_index=candidate_index,
                status="failed",
                code="YAML_PARSE_ERROR",
                message=joined,
            )
            errors.append(joined)
        else:
            _append_parser_event(
                source=source,
                parser="yaml",
                candidate_type=candidate_type,
                candidate_index=candidate_index,
                status="failed",
                code="YAML_PARSE_ERROR",
                message=parse_errors[0],
            )
            errors.append(parse_errors[0])
    return None

def parse_layer_rules(text: str, source: str, candidate_type: str, candidate_index: str):
    if not text:
        _append_parser_event(
            source=source,
            parser="yaml",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="failed",
            code="EMPTY_YAML_CANDIDATE",
            message=f"{source}: candidate payload is empty.",
        )
        return None

    parsed = parse_yaml_with_library(text, source, candidate_type, candidate_index)
    if isinstance(parsed, dict):
        _append_parser_event(
            source=source,
            parser="yaml",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="success",
            code="YAML_VALID_POLICY_FOUND",
            message=f"{source}: parsed YAML payload as dict; policy schema validation pending.",
        )
        return parsed
    if parsed is not None:
        _append_parser_event(
            source=source,
            parser="yaml",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="failed",
            code="YAML_NOT_OBJECT",
            message=f"{source}: parsed YAML payload is not a mapping/dict ({type(parsed).__name__}).",
        )
        errors.append(
            f"{source}: parsed YAML payload is not a mapping/dict ({type(parsed).__name__})."
        )

    return None

def parse_json_payload(text: str, source: str, candidate_type: str, candidate_index: str):
    if not text:
        _append_parser_event(
            source=source,
            parser="json",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="failed",
            code="EMPTY_JSON_CANDIDATE",
            message=f"{source}: candidate payload is empty.",
        )
        return None
    try:
        parsed = json.loads(text)
    except Exception as err:
        line_no, col_no = _extract_error_position(str(err))
        _append_parser_event(
            source=source,
            parser="json",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="failed",
            code="JSON_PARSE_ERROR",
            message=f"{source}: json parser error ({err})",
            line=line_no,
            column=col_no,
        )
        return None

    if not isinstance(parsed, dict):
        _append_parser_event(
            source=source,
            parser="json",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="failed",
            code="JSON_NOT_OBJECT",
            message=f"{source}: parsed JSON payload is not a mapping/dict ({type(parsed).__name__}).",
        )
        return parsed

    _append_parser_event(
        source=source,
        parser="json",
        candidate_type=candidate_type,
        candidate_index=candidate_index,
        status="success",
        code="JSON_VALID_POLICY_FOUND",
        message=f"{source}: parsed JSON payload as dict; policy schema validation pending.",
    )
    return parsed


def summarize_parser_events(events):
    summary = {
        "total": len(events),
        "failed": 0,
        "blocked_by_parser_missing": 0,
        "attempts": 0,
        "schema_mismatch": 0,
        "success": 0,
        "parsers": {},
    }
    for event in events:
        status = event.get("status", "")
        code = event.get("code", "")
        parser = event.get("parser", "unknown")
        summary["parsers"].setdefault(parser, 0)
        summary["parsers"][parser] += 1
        if status == "failed":
            summary["failed"] += 1
        if status == "success":
            summary["success"] += 1
        if status == "attempt":
            summary["attempts"] += 1
        if code == "NO_YAML_PARSER_AVAILABLE":
            summary["blocked_by_parser_missing"] += 1
        if code == "POLICY_SCHEMA_MISSING":
            summary["schema_mismatch"] += 1
    return summary

def is_valid_policy(value):
    if not isinstance(value, dict):
        return False
    has_naming = isinstance(value.get("naming"), dict) and bool(value.get("naming"))
    has_rules = isinstance(value.get("layer_rules"), dict) and bool(value.get("layer_rules"))
    has_errors = isinstance(value.get("errors"), dict) and bool(value.get("errors"))
    has_behavior = isinstance(value.get("behavior"), dict) and bool(value.get("behavior"))
    return bool(has_naming or has_rules or has_errors or has_behavior)

def merge_dict(base, overlay):
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge_dict(base[key], value)
        else:
            base[key] = value
    return base

def extract_yaml_or_json(path: Path):
    if not path.is_file():
        return None

    try:
        raw = path.read_text(encoding="utf-8")
    except Exception as err:
        errors.append(f"{path}: failed to read source file ({err})")
        return None

    text_candidates = []
    if path.suffix.lower() in {".yml", ".yaml"}:
        text_candidates.append(("yaml_file", "full", raw))
    text_candidates.extend(
        ("yaml_block", f"block:{index}", block)
        for index, block in enumerate(parse_yaml_blocks(raw))
    )
    text_candidates.extend(
        ("json_block", f"block:{index}", block)
        for index, block in enumerate(parse_json_blocks(raw))
    )

    for candidate_type, candidate_index, candidate in text_candidates:
        parsed = parse_layer_rules(candidate, str(path), candidate_type, candidate_index)
        if is_valid_policy(parsed):
            return parsed
        _append_parser_event(
            source=str(path),
            parser="policy_schema",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="failed",
            code="POLICY_SCHEMA_MISSING",
            message=f"{path}: candidate payload parsed but did not include policy keys.",
        )

        parsed_json = parse_json_payload(
            candidate,
            str(path),
            candidate_type,
            candidate_index,
        )
        if is_valid_policy(parsed_json):
            return parsed_json
        _append_parser_event(
            source=str(path),
            parser="policy_schema",
            candidate_type=candidate_type,
            candidate_index=candidate_index,
            status="failed",
            code="POLICY_SCHEMA_MISSING",
            message=f"{path}: candidate payload parsed as JSON but did not include policy keys.",
        )

    try:
        parsed = json.loads(raw)
    except Exception as err:
        _append_parser_event(
            source=str(path),
            parser="json",
            candidate_type="full_text",
            candidate_index="0",
            status="failed",
            code="JSON_FULL_TEXT_PARSE_ERROR",
            message=f"{path}: full-text JSON parse failed ({err}).",
        )
    else:
        if is_valid_policy(parsed):
            _append_parser_event(
                source=str(path),
                parser="json",
                candidate_type="full_text",
                candidate_index="0",
                status="success",
                code="JSON_FULL_TEXT_VALID_POLICY_FOUND",
                message=f"{path}: full-text JSON payload contains expected policy keys.",
            )
            return parsed
        _append_parser_event(
            source=str(path),
            parser="json",
            candidate_type="full_text",
            candidate_index="0",
            status="failed",
            code="JSON_FULL_TEXT_SCHEMA_MISSING",
            message=f"{path}: full-text JSON payload parsed but did not include policy keys.",
        )

    _append_parser_event(
        source=str(path),
        parser="policy_resolution",
        candidate_type="file",
        candidate_index="0",
        status="failed",
        code="NO_POLICY_FOUND",
        message=f"{path}: No valid policy payload was extracted from this file.",
    )

    return None

def extract_file_name(path: str):
    return Path(path).name

feature_path = policy_source_dir.resolve()
explicit_source_file = None
explicit_source_kind = "FEATURE_SOURCE"
if policy_source_dir.is_file():
    explicit_source_file = policy_source_dir
    if policy_source_dir.name in {"ARCHITECTURE.md", "architecture.md"}:
        explicit_source_kind = "ARCHITECTURE"
    elif policy_source_dir.name.lower() == "constitution.md":
        explicit_source_kind = "CONSTITUTION"
    if policy_source_dir.parent.name == "docs":
        feature_path = policy_source_dir.parent.parent
    else:
        feature_path = policy_source_dir.parent

if requested_feature_id:
    layer_feature_id = normalize_name(requested_feature_id)
else:
    try:
        relative_feature = feature_path.relative_to(repo_root)
    except Exception:
        relative_feature = Path(feature_path.name)
    layer_feature_id = normalize_name(str(relative_feature).replace("/", "-").replace("\\", "-"))

override_path = repo_root / ".specify" / "layer_rules" / "overrides" / f"{layer_feature_id}.yaml"
feature_arch_main = feature_path / "docs" / "ARCHITECTURE.md"
feature_arch_lower = feature_path / "docs" / "architecture.md"
feature_cons = feature_path / "docs" / "constitution.md"
feature_cons_root = feature_path / "constitution.md"

candidate_sources = []
if explicit_source_file:
    candidate_sources.append(
        (explicit_source_file, explicit_source_kind, "Explicit source file passed as --source-dir")
    )
candidate_sources.extend([
    (contract_path, "CONTRACT", "Repository default contract"),
    (override_path, "OVERRIDE", "Feature override in .specify/layer_rules/overrides"),
    (feature_cons, "CONSTITUTION", "Feature constitution"),
    (feature_cons_root, "CONSTITUTION", "Feature constitution"),
    (feature_arch_main, "ARCHITECTURE", "Feature architecture"),
    (feature_arch_lower, "ARCHITECTURE", "Feature architecture"),
])

policy = {}
applied_sources = []
contract_written = False

for source_path, source_kind, source_desc in candidate_sources:
    parsed = extract_file_name(str(source_path))
    _parsed = extract_yaml_or_json(source_path)
    if not _parsed:
        continue
    policy = merge_dict(policy, _parsed)
    source_kind_resolved = source_kind
    source_file = str(source_path)
    source_reason = f"Loaded from {source_desc}: {source_path}"
    applied_sources.append({
        "kind": source_kind,
        "file": str(source_path),
        "path": str(source_path),
        "reason": source_reason,
    })

if not applied_sources:
    source_kind_resolved = "DEFAULT"
    source_file = ""
    source_reason = "No usable layer_rules source found; using empty policy fallback."

if not policy:
    policy = {}

if write_contract:
    if not policy:
        warnings.append("No resolved policy available to write contract.yaml.")
    elif contract_path.exists() and not force_contract:
        warnings.append(
            f"contract.yaml already exists and --force-contract was not set: {contract_path}"
        )
    else:
        try:
            rendered = ""
            try:
                import yaml  # type: ignore
                rendered = yaml.safe_dump(
                    policy, sort_keys=False, allow_unicode=True
                )
            except Exception as err:
                warnings.append(
                    f"PyYAML unavailable; falling back to JSON-compatible YAML output for contract.yaml: {err}"
                )
                rendered = json.dumps(
                    policy, ensure_ascii=False, indent=2, sort_keys=False
                ) + "\n"

            contract_path.parent.mkdir(parents=True, exist_ok=True)
            with contract_path.open("w", encoding="utf-8") as fp:
                fp.write(rendered)
            contract_written = True
            source_kind_resolved = "CONTRACT_GENERATED"
            source_file = str(contract_path)
            source_reason = (
                f"Generated from loaded policy and written to {contract_path}"
            )
        except Exception as err:
            warnings.append(f"Failed to write contract.yaml: {err}")

resolved_path = ""
if write_resolved:
    resolved_dir = repo_root / ".specify" / "layer_rules" / "resolved"
    resolved_dir.mkdir(parents=True, exist_ok=True)
    resolved_path = str(resolved_dir / f"{layer_feature_id}.json")
    try:
        with open(resolved_path, "w", encoding="utf-8") as fp:
            json.dump(policy, fp, ensure_ascii=False, indent=2)
    except Exception as err:
        warnings.append(f"Failed to write resolved policy JSON: {err}")

layer_rules_block = policy.get("layer_rules")
has_layer_rules = isinstance(layer_rules_block, dict) and bool(layer_rules_block)
if not applied_sources:
    warnings.append("No layer_rules source was found. Governance checks fall back to empty policy.")
if not has_layer_rules:
    warnings.append("Resolved policy does not contain a non-empty layer_rules section.")

result = {
    "source_kind": source_kind_resolved,
    "source_file": source_file,
    "source_reason": source_reason,
    "has_layer_rules": bool(has_layer_rules),
    "has_policy": bool(policy),
    "contract_path": str(contract_path),
    "contract_written": bool(contract_written),
    "resolved_path": str(resolved_path),
    "applied_sources": applied_sources,
    "errors": errors,
    "warnings": warnings,
    "policy": policy,
    "parse_events": parser_events,
    "parse_summary": summarize_parser_events(parser_events),
}

print(json.dumps(result, ensure_ascii=False))
PY
