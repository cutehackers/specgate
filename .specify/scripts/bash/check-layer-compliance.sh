#!/usr/bin/env bash

set -euo pipefail

FEATURE_DIR_ARG=""
JSON_MODE=false
STRICT_LAYER=false

usage() {
    cat <<'USAGE'
Usage: check-layer-compliance.sh --feature-dir <abs-path> [options]

Options:
  --feature-dir <abs-path>  Absolute path to the feature folder (required)
  --strict-layer            Fail when layer policy is missing or violations are found
  --json                    Print JSON output
  --help                    Show this message
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature-dir)
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --strict-layer)
            STRICT_LAYER=true
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
source "$SCRIPT_DIR/common.sh"

eval $(get_feature_paths "$FEATURE_DIR_ARG") || exit 1

python3 - "$FEATURE_DIR" "$LAYER_RULES_POLICY_JSON" "$STRICT_LAYER" "$LAYER_RULES_SOURCE_KIND" "$LAYER_RULES_SOURCE_FILE" "$LAYER_RULES_SOURCE_REASON" "$JSON_MODE" <<'PY'
import json
import re
import sys
from pathlib import Path


feature_dir = Path(sys.argv[1]).resolve()
raw_policy = sys.argv[2] if len(sys.argv) > 2 else "{}"
strict_layer = sys.argv[3].lower() == "true" if len(sys.argv) > 3 else False
layer_rules_source = {
    "kind": sys.argv[4] if len(sys.argv) > 4 else "DEFAULT",
    "file": sys.argv[5] if len(sys.argv) > 5 else "",
    "reason": sys.argv[6] if len(sys.argv) > 6 else "No layer rules metadata provided.",
}
json_mode = sys.argv[7].lower() == "true" if len(sys.argv) > 7 else False

try:
    policy = json.loads(raw_policy) if raw_policy else {}
except Exception:
    policy = {}

layer_rules = policy.get("layer_rules") if isinstance(policy, dict) else {}
if not isinstance(layer_rules, dict):
    layer_rules = {}

errors_policy = {}
behavior = {}
if isinstance(policy, dict):
    errors_policy = policy.get("errors", {}) if isinstance(policy.get("errors", {}), dict) else {}
    behavior = policy.get("behavior", {}) if isinstance(policy.get("behavior", {}), dict) else {}

layer_rules_present = bool(layer_rules)
use_case_policy = errors_policy.get("policy", {}).get("use_case") if isinstance(errors_policy.get("policy", {}), dict) else {}
if not isinstance(use_case_policy, dict):
    use_case_policy = {}

domain_policy = errors_policy.get("policy", {}).get("domain_layer") if isinstance(errors_policy.get("policy", {}), dict) else {}
if not isinstance(domain_policy, dict):
    domain_policy = {}

require_result_type = bool(domain_policy.get("require_result_type", False))
forbid_exceptions = domain_policy.get("forbid_exceptions", [])
if not isinstance(forbid_exceptions, list):
    forbid_exceptions = []

allow_direct_repository_implementation_use = bool(
    behavior.get("use_case", {}).get("allow_direct_repository_implementation_use", True)
)


def normalize_layer(path_rel: str):
    if "/presentation/" in path_rel:
        return "presentation"
    if "/domain/" in path_rel:
        return "domain"
    if "/data/" in path_rel:
        return "data"
    return ""


def add_finding(findings, path: Path, line_no: int, layer: str, severity: str, category: str, message: str, snippet: str):
    findings.append(
        {
            "file": path.as_posix(),
            "line": int(line_no),
            "layer": layer,
            "severity": severity,
            "category": category,
            "message": message,
            "snippet": snippet.strip(),
        }
    )


forbid_imports = {}
for layer, data in layer_rules.items():
    if not isinstance(data, dict):
        continue
    patterns = []
    for item in data.get("forbid_import_patterns", []):
        if isinstance(item, str):
            patterns.append(item)
    forbid_imports[layer] = patterns

findings = []
warnings = []

policy_parse_errors = []
policy_parse_warnings = []
if isinstance(policy, dict):
    raw_parse_errors = policy.get("errors", [])
    if isinstance(raw_parse_errors, list):
        policy_parse_errors = raw_parse_errors
    raw_parse_warnings = policy.get("warnings", [])
    if isinstance(raw_parse_warnings, list):
        policy_parse_warnings = raw_parse_warnings

for warning in policy_parse_warnings:
    if isinstance(warning, str):
        warnings.append(warning)
for error in policy_parse_errors:
    if isinstance(error, str):
        warnings.append(f"policy parse issue: {error}")

# Non-strict mode does not fail by default when policy is missing.
policy_available_warning = ""
if not layer_rules_present:
    policy_available_warning = (
        "No usable layer_rules section resolved from .specify/layer_rules/contract.yaml "
        "or override/architecture/constitution documents."
    )
    if strict_layer:
        warnings.append(
            policy_available_warning
            + " Define contract.yaml (or run load-layer-rules.sh --write-contract) and rerun in strict mode."
        )


if not layer_rules_present:
    scanned_files = 0
    checked_files = 0
else:
    try:
        dart_files = sorted(feature_dir.rglob("*.dart"))
    except Exception:
        dart_files = []

    scanned_files = 0
    checked_files = 0
    for dart_file in dart_files:
        if not dart_file.is_file():
            continue

        rel = f"/{dart_file.relative_to(feature_dir).as_posix()}/"
        lowered_rel = rel.lower()

        if "/test/" in lowered_rel or "/build/" in lowered_rel:
            continue

        if dart_file.name.endswith("_test.dart"):
            continue

        if dart_file.name.endswith(".g.dart") or dart_file.name.endswith(".freezed.dart"):
            continue

        layer = normalize_layer(lowered_rel)
        if not layer:
            continue

        scanned_files += 1

        policy_layer = layer_rules.get(layer, {})
        if not isinstance(policy_layer, dict):
            continue

        checked_files += 1
        forbidden_patterns = [str(p) for p in policy_layer.get("forbid_import_patterns", []) if isinstance(p, str)]

        try:
            lines = dart_file.read_text(encoding="utf-8").splitlines()
        except Exception:
            continue

        is_domain_layer = layer == "domain"
        is_domain_use_case = is_domain_layer and "/use_case/" in lowered_rel

        for line_no, raw_line in enumerate(lines, start=1):
            stripped = raw_line.strip()
            if not stripped:
                continue

            import_match = re.match(r"^\s*import\s+['\"]([^'\"]+)['\"]", stripped)
            if import_match:
                target = import_match.group(1)

                for pattern in forbidden_patterns:
                    try:
                        if re.search(pattern, target):
                            add_finding(
                                findings,
                                dart_file,
                                line_no,
                                layer,
                                "error" if strict_layer else "warning",
                                "forbid_import",
                                f"Forbidden import for layer '{layer}'.",
                                stripped,
                            )
                    except re.error:
                        continue

                if is_domain_layer and is_domain_use_case and not allow_direct_repository_implementation_use:
                    if "repository_impl" in target:
                        add_finding(
                            findings,
                            dart_file,
                            line_no,
                            layer,
                            "error" if strict_layer else "warning",
                            "direct_repository_impl",
                            "Domain use case imports repository_impl directly.",
                            stripped,
                        )

            if is_domain_layer and require_result_type and is_domain_use_case:
                if re.match(r"^\s*call\s*\(", stripped):
                    add_finding(
                        findings,
                        dart_file,
                        line_no,
                        layer,
                        "error" if strict_layer else "warning",
                        "result_type",
                        "Domain use case methods must define explicit return types.",
                        stripped,
                    )

            if is_domain_layer and forbid_exceptions:
                for exception in forbid_exceptions:
                    pattern = rf"\bthrow\s+(?:[A-Za-z_][A-Za-z0-9_]*\.)?{re.escape(exception)}\b"
                    if re.search(pattern, stripped):
                        add_finding(
                            findings,
                            dart_file,
                            line_no,
                            layer,
                            "error" if strict_layer else "warning",
                            "exception_policy",
                            f"Forbidden exception raised: {exception}",
                            stripped,
                        )


error_count = len([item for item in findings if item["severity"] == "error"])
warning_count = len([item for item in findings if item["severity"] == "warning"])

if strict_layer:
    ok = layer_rules_present and error_count == 0 and not policy_parse_errors
else:
    ok = True
    if not layer_rules_present and policy_available_warning:
        warnings.append(
            policy_available_warning
            + " Add/regenerate .specify/layer_rules/contract.yaml and continue. "
            "Example: .specify/scripts/bash/load-layer-rules.sh --source-dir <abs feature path> --repo-root <repo root> --write-contract --json"
        )

payload = {
    "ok": ok,
    "strict": strict_layer,
    "policy_present": layer_rules_present,
    "layer_rules_source": layer_rules_source,
    "scanned_files": scanned_files,
    "checked_files": checked_files,
    "findings": findings,
    "warnings": warnings,
    "error_count": error_count,
    "warning_count": warning_count,
    "advice": (
        [
            "Create .specify/layer_rules/contract.yaml from layer-rules-template.yaml before strict mode, or run "
            ".specify/scripts/bash/load-layer-rules.sh --source-dir <abs feature path> --repo-root <repo root> --write-contract --json."
        ]
        if not layer_rules_present and strict_layer
        else []
    ),
    "summary": {
        "policy_present": layer_rules_present,
        "checked_files": checked_files,
        "scanned_files": scanned_files,
        "violation_count": error_count + warning_count,
    },
}

if json_mode:
    print(json.dumps(payload, ensure_ascii=False))
    raise SystemExit(0 if ok else 1)

if ok:
    print(f"OK: layer policy compliance passed for {feature_dir}")
else:
    print("ERROR: layer policy compliance failed:", file=sys.stderr)

print(f"  source_kind={layer_rules_source['kind']}")
print(f"  source_file={layer_rules_source['file'] or '<none>'}")
print(f"  reason={layer_rules_source['reason']}")
print(f"  strict_layer={strict_layer}")
print(f"  checked_files={checked_files}/{scanned_files}")

if payload["warnings"]:
    print("Warnings:")
    for warning in payload["warnings"]:
        print(f"  - {warning}")

if payload["findings"]:
    print("Findings:")
    for finding in payload["findings"]:
        file_path = finding.get("file", "<unknown>")
        line_no = finding.get("line", "?")
        severity = str(finding.get("severity", "warning")).upper()
        print(f"  - {severity} {file_path}:{line_no} {finding.get('category', 'policy')} :: {finding.get('message', '')}")

if payload["advice"]:
    print("Advice:")
    for item in payload["advice"]:
        print(f"  - {item}")

raise SystemExit(0 if ok else 1)
PY
