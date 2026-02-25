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
import copy
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


def parse_layer_rules_marked_blocks(content: str):
    blocks = []
    marker_re = re.compile(
        r"(?ms)<!--\s*layer-rules:start\s*-->(.*?)<!--\s*layer-rules:end\s*-->",
        re.IGNORECASE,
    )
    for index, match in enumerate(marker_re.finditer(content)):
        body = (match.group(1) or "").strip()
        if body.startswith("```"):
            body = re.sub(
                r"(?ms)^```[A-Za-z0-9_-]+\s*\n|^\s*```$",
                "",
                body,
            ).strip()
        if body:
            blocks.append(("layer_rules_marker", f"marker:{index}", body))
    return blocks


def parse_layer_rules_fenced_blocks(content: str):
    blocks = []
    for index, match in enumerate(
        re.finditer(
            r"(?ms)(^|\n)```(?:layer_rules|layer-rules)\s*\n(.*?)\n```",
            content,
        )
    ):
        body = (match.group(2) or "").strip()
        if body:
            blocks.append(("layer_rules_fence", f"fence:{index}", body))
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


def parse_yaml_for_template(text: str):
    try:
        import yaml  # type: ignore
        parsed = yaml.safe_load(text)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass

    try:
        from ruamel.yaml import YAML  # type: ignore
        loader = YAML(typ="safe")
        parsed = loader.load(text)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass

    return parse_yaml_subset(text)


def load_template_policy():
    template_path = repo_root / ".specify" / "templates" / "layer-rules-template.yaml"
    if not template_path.is_file():
        return {
            "kind": "layer_rules",
            "version": "1",
            "naming": {
                "entity": "{Name}Entity",
                "dto": "{Name}Dto",
                "use_case": "{Action}UseCase",
                "repository": "{Feature}Repository",
                "repository_impl": "{Feature}RepositoryImpl",
                "event": "{Feature}{Action}Event",
                "controller": "{Feature}Controller",
                "data_source": "{Feature}{Type}DataSource",
                "provider": "{featureName}{Type}Provider",
            },
            "layer_rules": {
                "domain": {
                    "forbid_import_patterns": [
                        "^package:.*\\/data\\/",
                        "^package:.*\\/presentation\\/",
                        "^package:.*\\/ui\\/",
                    ]
                },
                "data": {"forbid_import_patterns": ["^package:.*\\/presentation\\/"]},
                "presentation": {
                    "forbid_import_patterns": [
                        "^package:.*\\/data\\/.+\\/(dto|data_source|datasource|repository_impl)",
                        "^package:.*\\/domain\\/.+\\/(dto|entity)",
                    ]
                },
            },
            "errors": {
                "policy": {
                    "domain_layer": {
                        "forbid_exceptions": ["StateError", "Exception"],
                        "require_result_type": True,
                    }
                }
            },
            "behavior": {"use_case": {"allow_direct_repository_implementation_use": False}},
        }

    try:
        template_text = template_path.read_text(encoding="utf-8")
    except Exception as err:
        warnings.append(f"Failed to read template policy at {template_path}: {err}")
        return {}

    template = parse_yaml_for_template(template_text)
    if isinstance(template, dict):
        return template

    warnings.append(
        f"Template policy at {template_path} could not be parsed as YAML dict; returning default policy."
    )
    return {}


def _normalize_layer_name(raw: str):
    normalized = (raw or "").strip().lower()
    if not normalized:
        return ""
    replacements = {
        "ui": "presentation",
        "presentation layer": "presentation",
        "data layer": "data",
        "domain layer": "domain",
        "business": "domain",
    }
    if normalized in replacements:
        return replacements[normalized]
    if "presentation" in normalized:
        return "presentation"
    if "data" in normalized:
        return "data"
    if "domain" in normalized:
        return "domain"
    return normalized


def _extract_layer_from_text(raw: str):
    normalized = (raw or "").strip().lower()
    if not normalized:
        return ""
    return _normalize_layer_name(normalized)


def _merge_layer_patterns(dst: dict, source_layer: str, pattern: str, source: str):
    if not source_layer or not pattern:
        return
    layer_block = dst.setdefault(source_layer, {})
    if not isinstance(layer_block, dict):
        dst[source_layer] = {}
        layer_block = dst[source_layer]
    patterns = layer_block.setdefault("forbid_import_patterns", [])
    if not isinstance(patterns, list):
        patterns = []
        layer_block["forbid_import_patterns"] = patterns
    if pattern not in patterns:
        patterns.append(pattern)


def extract_doc_signals(path: Path):
    signals = {
        "naming": {},
        "layer_rules": {},
        "errors": {"policy": {"domain_layer": {}}},
        "behavior": {"use_case": {}},
        "evidence": [],
    }

    if not path.is_file():
        return signals

    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return signals

    heading_re = re.compile(r"^\s*#{1,6}\s+(.*?)\s*$")
    import_block_re = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]")
    named_prohibition_re = re.compile(
        r"(?i)\b(?:do not|don't|must not|should not|avoid|forbid|forbidden)\b.*\bimport\b"
    )
    explicit_import_bad_re = re.compile(
        r"(?i)(?:❌|WRONG|NOT_GOOD|bad|wrong)\s*.*\bimport\s+['\"]([^'\"]+)['\"]"
    )
    naming_hint_re = re.compile(
        r"(?i)\b(entity|dto|use[-_ ]case|repository[-_ ]impl|repository|event|controller|data[-_ ]source|provider)\b[^\n]*?`([^`]+)`"
    )
    return_type_re = re.compile(
        r"(?i)\b(return\s+type|result\s+type)\b.*\b(must|should|required)\b"
    )
    repository_impl_prohibition_re = re.compile(
        r"(?i)\b(do not|don't|must not|should not|forbid|forbidden)\b[^\n]*\brepository_impl\b"
    )
    exception_name_re = re.compile(r"\b([A-Z][A-Za-z0-9_]*Exception|Exception)\b")

    layer_pattern = re.compile(r"\b(domain|data|presentation|ui|ui layer|business layer|data layer|domain layer)\b", re.IGNORECASE)

    in_code_block = False
    current_section = ""
    active_layer_section = ""
    pending_bad_import_example = False
    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        stripped = raw_line.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_code_block = not in_code_block
            continue

        heading_match = heading_re.match(raw_line)
        if heading_match and not in_code_block:
            heading = heading_match.group(1).strip()
            normalized_heading = re.sub(r"\s+", " ", heading.lower())
            current_section = normalized_heading
            resolved_layer = _extract_layer_from_text(current_section)
            if resolved_layer in {"domain", "data", "presentation"}:
                active_layer_section = resolved_layer
            continue

        normalized = re.sub(r"\s+", " ", stripped.lower())

        if in_code_block:
            import_match = import_block_re.search(stripped)
            if not stripped:
                pending_bad_import_example = False
            if explicit_import_bad_re.search(stripped):
                pending_bad_import_example = True
                continue

            if import_match:
                import_target = import_match.group(1).strip()
                if pending_bad_import_example:
                    source_layer = _extract_layer_from_text(active_layer_section)
                    if not source_layer:
                        source_layer = _extract_layer_from_text(current_section.split(" ", 1)[0])
                    if source_layer in {"domain", "data", "presentation"}:
                        pattern = "^" + re.escape(import_target) + "$"
                        _merge_layer_patterns(signals["layer_rules"], source_layer, pattern, path)
                        signals["evidence"].append(
                            {
                                "file": str(path),
                                "line": line_no,
                                "pattern": pattern,
                                "rule": f"layer_rules.{source_layer}.forbid_import_patterns",
                                "signal": "bad_import_example",
                                "text": stripped,
                            }
                        )
                    pending_bad_import_example = False
                    continue
            else:
                pending_bad_import_example = False
            continue

        if named_prohibition_re.search(normalized):
            source_layer = _extract_layer_from_text(current_section)
            if source_layer not in {"domain", "data", "presentation"}:
                source_layer = _extract_layer_from_text(active_layer_section)
            if source_layer in {"domain", "data", "presentation"}:
                mentioned = layer_pattern.findall(normalized)
                for item in mentioned:
                    target_layer = _normalize_layer_name(item)
                    if not target_layer or target_layer == source_layer:
                        continue
                    pattern = f"^package:.*\\\\/{re.escape(target_layer)}\\\\/"
                    _merge_layer_patterns(signals["layer_rules"], source_layer, pattern, path)
                    signals["evidence"].append(
                        {
                            "file": str(path),
                            "line": line_no,
                            "pattern": pattern,
                            "rule": f"layer_rules.{source_layer}.forbid_import_patterns",
                            "signal": "explicit_prohibition",
                            "text": stripped,
                        }
                    )

        naming_match = naming_hint_re.search(stripped)
        if naming_match:
            key = naming_match.group(1).strip().lower().replace("-", "_").replace(" ", "_")
            if key == "use_case":
                key = "use_case"
            if key == "data_source":
                key = "data_source"
            if key == "repository_impl":
                key = "repository_impl"
            value = naming_match.group(2).strip()
            existing = signals["naming"].get(key)
            if not existing:
                signals["naming"][key] = value
            elif existing != value:
                signals["evidence"].append(
                    {
                        "file": str(path),
                        "line": line_no,
                        "pattern": value,
                        "rule": f"naming.{key}",
                        "signal": "naming_conflict",
                        "text": stripped,
                    }
                )
            signals["evidence"].append(
                {
                    "file": str(path),
                    "line": line_no,
                    "pattern": value,
                    "rule": f"naming.{key}",
                    "signal": "naming_hint",
                    "text": stripped,
                }
            )

        if return_type_re.search(normalized):
            if "errors" in signals and isinstance(signals["errors"], dict):
                policy = signals["errors"].setdefault("policy", {})
                if isinstance(policy, dict):
                    domain_layer = policy.setdefault("domain_layer", {})
                    if isinstance(domain_layer, dict):
                        domain_layer["require_result_type"] = True
                        signals["evidence"].append(
                            {
                                "file": str(path),
                                "line": line_no,
                                "pattern": "^explicit_return_type$",
                                "rule": "errors.policy.domain_layer.require_result_type",
                                "signal": "explicit_prohibition",
                                "text": stripped,
                            }
                        )

        if repository_impl_prohibition_re.search(normalized):
            behavior = signals["behavior"].setdefault("use_case", {})
            behavior["allow_direct_repository_implementation_use"] = False
            signals["evidence"].append(
                {
                    "file": str(path),
                    "line": line_no,
                    "pattern": "repository_impl",
                    "rule": "behavior.use_case.allow_direct_repository_implementation_use",
                    "signal": "explicit_prohibition",
                    "text": stripped,
                }
            )

        if "exception" in normalized:
            if current_section.find("error") >= 0 or current_section.find("exception") >= 0:
                exception_policy = signals["errors"].setdefault("policy", {}).setdefault("domain_layer", {})
                forbid = exception_policy.setdefault("forbid_exceptions", [])
                if not isinstance(forbid, list):
                    forbid = []
                    exception_policy["forbid_exceptions"] = forbid
                for match in exception_name_re.findall(normalized):
                    if match not in forbid:
                        forbid.append(match)
                        signals["evidence"].append(
                            {
                                "file": str(path),
                                "line": line_no,
                                "pattern": match,
                                "rule": "errors.policy.domain_layer.forbid_exceptions",
                                "signal": "explicit_prohibition",
                                "text": stripped,
                            }
                        )

    return signals


def infer_layer_rules(signals):
    inferred = {
        "kind": "layer_rules",
        "version": "1",
    }

    naming = signals.get("naming", {})
    if isinstance(naming, dict) and naming:
        inferred["naming"] = copy.deepcopy({k: v for k, v in naming.items() if v})

    layer_rules = signals.get("layer_rules", {})
    if isinstance(layer_rules, dict) and layer_rules:
        for layer, layer_signal in layer_rules.items():
            if layer not in {"domain", "data", "presentation"}:
                continue
            if not isinstance(layer_signal, dict):
                continue
            patterns = layer_signal.get("forbid_import_patterns", [])
            if isinstance(patterns, list) and patterns:
                filtered = [str(item) for item in patterns if str(item).strip()]
                if filtered:
                    inferred.setdefault("layer_rules", {}).setdefault(layer, {})["forbid_import_patterns"] = filtered

    errors = signals.get("errors", {})
    if isinstance(errors, dict):
        policy = errors.get("policy", {})
        if isinstance(policy, dict):
            domain_layer = policy.get("domain_layer", {})
            if isinstance(domain_layer, dict):
                inferred_domain = {"forbid_exceptions": [], "require_result_type": None}
                forbid = domain_layer.get("forbid_exceptions", [])
                if isinstance(forbid, list) and forbid:
                    inferred_domain["forbid_exceptions"] = [str(item) for item in forbid]
                if isinstance(domain_layer.get("require_result_type"), bool):
                    inferred_domain["require_result_type"] = bool(domain_layer.get("require_result_type"))
                if inferred_domain["forbid_exceptions"] or inferred_domain["require_result_type"] is not None:
                    inferred.setdefault("errors", {}).setdefault("policy", {})["domain_layer"] = {
                        "forbid_exceptions": inferred_domain["forbid_exceptions"],
                        "require_result_type": bool(inferred_domain["require_result_type"]),
                    }

    behavior = signals.get("behavior", {})
    if isinstance(behavior, dict):
        use_case = behavior.get("use_case", {})
        if isinstance(use_case, dict):
            if use_case.get("allow_direct_repository_implementation_use") is False:
                inferred.setdefault("behavior", {}).setdefault("use_case", {})[
                    "allow_direct_repository_implementation_use"
                ] = False

    # Remove empty keys
    if "naming" in inferred and not inferred["naming"]:
        inferred.pop("naming", None)
    if "layer_rules" in inferred and not inferred["layer_rules"]:
        inferred.pop("layer_rules", None)
    if "errors" in inferred and not inferred["errors"]:
        inferred.pop("errors", None)
    if "behavior" in inferred and not inferred["behavior"]:
        inferred.pop("behavior", None)

    return inferred


def evaluate_inference_confidence(signals, inferred_policy):
    evidence = signals.get("evidence", [])
    score = 0.0

    weights = {
        "explicit_prohibition": 0.25,
        "bad_import_example": 0.15,
        "naming_hint": 0.10,
    }

    for item in evidence:
        signal_type = str(item.get("signal", "")).strip().lower()
        score += weights.get(signal_type, 0.0)

    naming_conflicts = sum(1 for item in evidence if str(item.get("signal", "")) == "naming_conflict")
    if naming_conflicts:
        score -= 0.05 * naming_conflicts

    if score < 0.0:
        score = 0.0
    if score > 1.0:
        score = 1.0

    rules_extracted = 0
    if isinstance(inferred_policy, dict):
        if "naming" in inferred_policy and isinstance(inferred_policy["naming"], dict):
            rules_extracted += len(inferred_policy["naming"])
        if "layer_rules" in inferred_policy and isinstance(inferred_policy["layer_rules"], dict):
            for layer_rules in inferred_policy["layer_rules"].values():
                if isinstance(layer_rules, dict):
                    rules = layer_rules.get("forbid_import_patterns", [])
                    if isinstance(rules, list):
                        rules_extracted += len(rules)
        if "errors" in inferred_policy and isinstance(inferred_policy["errors"], dict):
            domain_layer = inferred_policy["errors"].get("policy", {}).get("domain_layer", {})
            if isinstance(domain_layer, dict):
                if isinstance(domain_layer.get("forbid_exceptions"), list):
                    rules_extracted += len(domain_layer["forbid_exceptions"])
                if isinstance(domain_layer.get("require_result_type"), bool):
                    rules_extracted += 1
        if "behavior" in inferred_policy and isinstance(inferred_policy["behavior"], dict):
            use_case = inferred_policy["behavior"].get("use_case", {})
            if isinstance(use_case, dict) and "allow_direct_repository_implementation_use" in use_case:
                rules_extracted += 1

    evidence_sanitized = []
    for item in evidence:
        if not isinstance(item, dict):
            continue
        evidence_sanitized.append(
            {
                "source": item.get("file", ""),
                "line": int(item.get("line", 0) or 0),
                "pattern": item.get("pattern", ""),
                "rule": item.get("rule", ""),
                "signal": str(item.get("signal", "")),
                "text": item.get("text", ""),
            }
        )

    return score, rules_extracted, evidence_sanitized


def merge_policy_with_template(base_policy: dict, inferred_policy: dict):
    merged = copy.deepcopy(base_policy or {})
    return merge_dict(merged, inferred_policy or {})


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
    elif path.suffix.lower() == ".json":
        text_candidates.append(("json_file", "full", raw))

    explicit_markers = parse_layer_rules_marked_blocks(raw)
    explicit_candidates = explicit_markers.copy()

    if explicit_candidates:
        text_candidates.extend(explicit_candidates)
    else:
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
if policy_source_dir.is_dir() and policy_source_dir.name == "docs":
    feature_path = policy_source_dir.parent
elif policy_source_dir.parent.name == "docs":
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

def choose_existing_path(*paths):
    for candidate in paths:
        if candidate.is_file():
            return candidate
    return None

feature_arch = choose_existing_path(feature_arch_main, feature_arch_lower)
feature_const = choose_existing_path(feature_cons, feature_cons_root)
feature_arch_files = [path for path in (feature_arch_main, feature_arch_lower) if path.is_file()]
feature_const_files = [path for path in (feature_cons, feature_cons_root) if path.is_file()]

candidate_sources = []
if explicit_source_file:
    candidate_sources.append(
        (explicit_source_file, explicit_source_kind, "Explicit source file passed as --source-dir")
    )
candidate_sources.extend([
    (contract_path, "CONTRACT", "Repository default contract"),
    (override_path, "OVERRIDE", "Feature override in .specify/layer_rules/overrides"),
])

if feature_const is not None:
    candidate_sources.append((feature_const, "CONSTITUTION", "Feature constitution"))
if feature_arch is not None:
    candidate_sources.append((feature_arch, "ARCHITECTURE", "Feature architecture"))

policy = {}
source_mode_resolved = "DEFAULT"
applied_sources = []
contract_written = False
inference_metadata = {
    "confidence": 0.0,
    "evidence": [],
    "rules_extracted": 0,
    "fallback_applied": False,
}
baseline_policy = {}

for source_path, source_kind, source_desc in candidate_sources:
    parsed = extract_file_name(str(source_path))
    _parsed = extract_yaml_or_json(source_path)
    if not _parsed:
        continue
    policy = merge_dict(policy, _parsed)
    source_kind_resolved = source_kind
    source_mode_resolved = "PARSED"
    source_file = str(source_path)
    source_reason = f"Loaded from {source_desc}: {source_path}"
    applied_sources.append({
        "kind": source_kind,
        "file": str(source_path),
        "path": str(source_path),
        "reason": source_reason,
    })

if not applied_sources:
    source_mode_resolved = "INFERRED"
    source_file = ""
    source_reason = "No usable explicit policy block found; trying inference from prose documentation."
    baseline_policy = load_template_policy()
    baseline_policy = baseline_policy or {}
    signals = {
        "naming": {},
        "layer_rules": {},
        "errors": {},
        "behavior": {},
        "evidence": [],
    }

    seen_candidates = set()
    for candidate in feature_arch_files + feature_const_files:
        candidate_real = str(candidate.resolve())
        candidate_key = candidate_real.casefold()
        if candidate_key in seen_candidates:
            continue
        seen_candidates.add(candidate_key)
        extracted = extract_doc_signals(candidate)
        if isinstance(extracted, dict):
            layer_rules_signals = extracted.get("layer_rules", {})
            naming_signals = extracted.get("naming", {})
            errors_signals = extracted.get("errors", {})
            behavior_signals = extracted.get("behavior", {})
            evidence = extracted.get("evidence", [])

            if isinstance(layer_rules_signals, dict):
                merge_dict(signals.setdefault("layer_rules", {}), layer_rules_signals)
            if isinstance(naming_signals, dict):
                merge_dict(signals.setdefault("naming", {}), naming_signals)
            if isinstance(errors_signals, dict):
                merge_dict(signals.setdefault("errors", {}), errors_signals)
            if isinstance(behavior_signals, dict):
                merge_dict(signals.setdefault("behavior", {}), behavior_signals)
            if isinstance(evidence, list):
                signals["evidence"].extend(evidence)

    inferred_policy = infer_layer_rules(signals)
    if inferred_policy:
        confidence, rules_extracted, evidence = evaluate_inference_confidence(signals, inferred_policy)
        inference_metadata["confidence"] = confidence
        inference_metadata["rules_extracted"] = int(rules_extracted)
        inference_metadata["evidence"] = evidence
        inference_metadata["fallback_applied"] = int(rules_extracted) > 0
        policy = merge_policy_with_template(baseline_policy, inferred_policy)
        source_kind_resolved = "INFERRED"
        source_reason = "No parseable policy block found. Applied inference from prose documentation."
        if feature_arch_files or feature_const_files:
            source_file = str(feature_arch_files[0] if feature_arch_files else feature_const_files[0])
        else:
            source_file = ""
        if source_file:
            applied_sources.append({
                "kind": "INFERRED",
                "file": source_file,
                "path": source_file,
                "reason": source_reason,
            })
    else:
        source_mode_resolved = "DEFAULT"
        source_kind_resolved = "DEFAULT"
        source_reason = "No usable layer_rules source found; using baseline template policy only."
        policy = merge_policy_with_template(baseline_policy, {})

if not policy:
    policy = {}
    source_kind_resolved = "DEFAULT"
    source_mode_resolved = "DEFAULT"

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
            source_kind_resolved = source_kind_resolved or "DEFAULT"
            source_file = str(contract_path)
            if source_mode_resolved == "INFERRED":
                source_reason = (
                    f"Generated from inferred policy and written to {contract_path}"
                )
            else:
                source_reason = (
                    f"Generated from loaded policy and written to {contract_path}"
                )
            if inference_metadata.get("fallback_applied"):
                source_mode_resolved = "INFERRED"
            elif not source_mode_resolved:
                source_mode_resolved = "PARSED"
            elif source_kind_resolved == "DEFAULT":
                source_mode_resolved = "DEFAULT"
            else:
                source_mode_resolved = "PARSED"
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
    if inference_metadata.get("fallback_applied"):
        warnings.append("No explicit layer_rules source was found. Policy was inferred from prose documentation.")
    else:
        warnings.append("No explicit layer_rules source was found. Baseline policy template was used.")
if not has_layer_rules:
    warnings.append("Resolved policy does not contain a non-empty layer_rules section.")

result = {
    "source_kind": source_kind_resolved,
    "source_mode": source_mode_resolved,
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
    "inference": inference_metadata,
    "inference_confidence": float(inference_metadata.get("confidence", 0.0) or 0.0),
    "inference_rules_extracted": int(inference_metadata.get("rules_extracted", 0) or 0),
    "inference_fallback_applied": bool(inference_metadata.get("fallback_applied", False)),
}

print(json.dumps(result, ensure_ascii=False))
PY
