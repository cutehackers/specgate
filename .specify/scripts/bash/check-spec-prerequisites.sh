#!/usr/bin/env bash

set -euo pipefail

FEATURE_DIR_ARG=""
JSON_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature-dir)
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --json)
            JSON_MODE=true
            shift
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

if [[ ! -f "$FEATURE_SPEC" ]]; then
    if $JSON_MODE; then
        printf '{"ok":false,"spec":"%s","naming_source":{"kind":"%s","file":"%s","reason":"%s"},"missing_sections":[],"empty_sections":[],"issue_messages":["spec.md not found"],"edge_case_count":0,"placeholder_tokens":[],"unresolved_clarifications":0,"concrete_ui_terms":[],"forbidden_naming_terms":[],"naming_policy":{},"naming_policy_violations":[]}\n' \
            "$FEATURE_SPEC" "$NAMING_SOURCE_KIND" "$NAMING_SOURCE_FILE" "$NAMING_SOURCE_REASON"
    else
        echo "ERROR: spec.md not found: $FEATURE_SPEC" >&2
    fi
    exit 1
fi

python3 - <<'PY' "$FEATURE_SPEC" "$JSON_MODE" "$NAMING_SOURCE_KIND" "$NAMING_SOURCE_FILE" "$NAMING_SOURCE_REASON" "$NAMING_POLICY_JSON"
import json
import re
import sys
from pathlib import Path

spec_path = Path(sys.argv[1])
json_mode = sys.argv[2] == "true"
json_naming_source = {
    "kind": sys.argv[3] if len(sys.argv) > 3 else "DEFAULT",
    "file": sys.argv[4] if len(sys.argv) > 4 else "",
    "reason": sys.argv[5] if len(sys.argv) > 5 else "No naming policy metadata provided.",
}
try:
    json_naming_rules = json.loads(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] else {}
except Exception:
    json_naming_rules = {}
text = spec_path.read_text(encoding="utf-8").replace("\r\n", "\n")


def normalize_naming_rules(raw):
    if not isinstance(raw, dict):
        return {}

    if isinstance(raw.get("naming"), dict):
        base_rules = {**raw}
        base_rules.update(raw["naming"])
    else:
        base_rules = raw

    normalized = {}
    for key, value in base_rules.items():
        if key == "naming":
            continue
        if not isinstance(value, str):
            continue
        normalized[str(key).strip().lower().replace("-", "_")] = value.strip()
    return normalized

required_sections = [
    "## Metadata",
    "## Problem Statement & Scope",
    "## User Scenarios",
    "## Acceptance Matrix",
    "## Functional Requirements",
    "## Domain Model",
    "## Edge Cases",
    "## Architecture Compliance",
    "## Success Criteria",
    "## Clarifications",
]

sections = {}
current = None
buffer = []
for line in text.splitlines():
    match = re.match(r"^##\s+(.+?)\s*$", line)
    if match:
        if current is not None:
            sections[current] = "\n".join(buffer)
        current = f"## {match.group(1).strip()}"
        buffer = []
        continue
    if current is not None:
        buffer.append(line)
if current is not None:
    sections[current] = "\n".join(buffer)

missing_sections = [s for s in required_sections if s not in sections]


def is_separator(line: str) -> bool:
    return bool(re.fullmatch(r"\|?[-:\s|]+\|?", line.strip()))


def has_meaningful_content(content: str) -> bool:
    for raw in content.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("### "):
            continue
        if line.startswith(">"):
            continue
        if is_separator(line):
            continue
        return True
    return False


def naming_suffix(pattern: str) -> str:
    if not isinstance(pattern, str):
        return ""

    suffix = re.sub(r"\{[^{}]+\}", "", pattern).strip()
    return suffix


def naming_key_display(key: str) -> str:
    normalized = str(key).strip().lower().replace("-", "_")
    if normalized == "dto":
        return "DTO"
    if normalized == "use_case":
        return "Use Case"
    if normalized == "data_source":
        return "Data Source"
    if normalized == "repository_impl":
        return "Repository Impl"
    return " ".join(part.capitalize() for part in normalized.split("_"))


def naming_row_label(key: str) -> str:
    return f"{naming_key_display(key)} naming rule from resolved naming source"


empty_sections = []
for section in required_sections:
    if section not in sections:
        continue
    if not has_meaningful_content(sections[section]):
        empty_sections.append(section)

edge_cases_text = sections.get("## Edge Cases", "")
edge_case_count = sum(
    1
    for line in edge_cases_text.splitlines()
    if re.match(r"^\s*(?:[-*]|\d+\.)\s+\S", line)
)

issue_messages = []
if edge_case_count < 5:
    issue_messages.append(
        f"Edge Cases must include at least 5 items (found {edge_case_count})."
    )

user_scenarios = sections.get("## User Scenarios", "")
scenario_ids = sorted(set(re.findall(r"\bUS-\d{3}\b", user_scenarios)))
priority_count = len(re.findall(r"Priority:\s*P[123]\b", user_scenarios, re.IGNORECASE))
independent_count = len(
    re.findall(r"Independent Completion", user_scenarios, re.IGNORECASE)
)

if not scenario_ids:
    issue_messages.append("User Scenarios must include at least one US-### item.")
if priority_count < len(scenario_ids):
    issue_messages.append(
        "Each user scenario must include an explicit priority (P1/P2/P3)."
    )
if independent_count < len(scenario_ids):
    issue_messages.append(
        "Each user scenario must include Independent Completion criteria."
    )

functional_requirements = sections.get("## Functional Requirements", "")
fr_ids = sorted(set(re.findall(r"\bFR-\d{3}\b", functional_requirements)))
if not fr_ids:
    issue_messages.append("Functional Requirements must include at least one FR-### item.")

acceptance_matrix = sections.get("## Acceptance Matrix", "")
ac_ids = sorted(set(re.findall(r"\bAC-\d{3}\b", acceptance_matrix)))
if not ac_ids:
    issue_messages.append("Acceptance Matrix must include at least one AC-### item.")

placeholder_pattern = re.compile(r"\[([^\]\n]{2,80})\](?!\()")
allowed_token = re.compile(
    r"^(?:US|FR|AC|SC|TC|TS)-\d{3}$|^P[123]$|^PASS/OPEN$",
    re.IGNORECASE,
)
placeholder_tokens = set()

for section in required_sections:
    content = sections.get(section, "")
    for raw in content.splitlines():
        for token in placeholder_pattern.findall(raw):
            normalized = token.strip()
            if not normalized:
                continue
            if allowed_token.match(normalized):
                continue
            placeholder_tokens.add(normalized)

unresolved_clarifications = len(
    re.findall(r"\[NEEDS CLARIFICATION:[^\]]+\]", text, re.IGNORECASE)
)
if unresolved_clarifications > 0:
    issue_messages.append(
        f"Found {unresolved_clarifications} unresolved NEEDS CLARIFICATION marker(s)."
    )

ui_forbidden_regex = re.compile(
    r"\b(layout|pixel|padding|margin|spacing|typography|font|color|theme|style|animation|shadow|gradient|radius|border|position|widget\s+tree)\b",
    re.IGNORECASE,
)
name_forbidden_regex = re.compile(
    r"\b(utils\.dart|helpers\.dart|Util|Helper|Manager)\b"
)
ui_policy_markers = (
    "do not include",
    "forbidden",
    "abstraction-only",
    "screen abstraction",
    "authoring guardrail",
    "policy",
)
ui_scan_sections = [
    "## Problem Statement & Scope",
    "## User Scenarios",
    "## Acceptance Matrix",
    "## Functional Requirements",
    "## Domain Model",
    "## Edge Cases",
    "## Success Criteria",
    "## Clarifications",
]
concrete_ui_terms = set()

for section_name in ui_scan_sections:
    content = sections.get(section_name, "")
    for raw in content.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("### "):
            continue
        if is_separator(line):
            continue

        lowered = line.lower()
        if any(marker in lowered for marker in ui_policy_markers):
            continue

        for term_match in ui_forbidden_regex.finditer(line):
            concrete_ui_terms.add(term_match.group(1).lower())

if concrete_ui_terms:
    issue_messages.append(
        "Specification includes concrete UI terms: "
        + ", ".join(sorted(concrete_ui_terms))
    )

forbidden_naming_terms = set()
for section_name in required_sections:
    if section_name == "## Architecture Compliance":
        continue
    section_content = sections.get(section_name, "")
    for raw in section_content.splitlines():
        for match in name_forbidden_regex.finditer(raw):
            forbidden_naming_terms.add(match.group(1))

if forbidden_naming_terms:
    issue_messages.append(
        "Specification includes ambiguous naming terms prohibited by architecture policy: "
        + ", ".join(sorted(forbidden_naming_terms))
    )


naming_policy_violations = []


def parse_domain_entities(text: str):
    section = sections.get("## Domain Model", "")
    if not section:
        return []

    in_entities = False
    in_table = False
    table_header_seen = False
    entities = []
    seen = set()
    table_sep_re = re.compile(r"^\|?[-:\s|]+\|?$")

    for line in section.splitlines():
        if re.match(r"^###\s+", line):
            if in_entities:
                break
            if re.match(r"^###\s*Entities\b", line, re.IGNORECASE):
                in_entities = True
            continue

        if not in_entities:
            continue

        stripped = line.strip()
        if not stripped:
            continue

        if stripped.startswith("|"):
            if table_sep_re.fullmatch(stripped):
                continue

            if not in_table:
                in_table = True
                table_header_seen = True
                continue

            if table_header_seen:
                table_header_seen = False
                continue

            cells = [cell.strip() for cell in stripped.strip("|").split("|")]
            if not cells:
                continue
            candidate = cells[0].strip()
            if not candidate or candidate.lower() in {"entity", "entities"}:
                continue

            m = re.match(r"^\*\*([^*]+)\*\*$", candidate)
            if m:
                candidate = m.group(1).strip()

            if re.match(r"^\[([^\]]+)\]$", candidate):
                candidate = candidate.strip("[]").strip()

            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", candidate) and candidate.lower() not in {"entity", "entities"}:
                if candidate not in seen:
                    seen.add(candidate)
                    entities.append(candidate)
            continue

        if not re.match(r"^\s*-\s+", line):
            continue

        # parse bullet style list entries
        if stripped.startswith("- ###"):
            continue

        m = re.match(r"^\s*-\s+\*\*([^*]+)\*\*(?:\s*:.*)?$", stripped)
        if not m:
            m = re.match(r"^\s*-\s*\[([^\]]+)\](?:\s*:.*)?$", stripped)
        if not m:
            m = re.match(r"^\s*-\s*([A-Za-z_][A-Za-z0-9_]*)(?:\s*:.*)?$", stripped)

        if m:
            name = m.group(1).strip()
            if name and name.lower() not in {"entity", "entities"} and name not in seen:
                seen.add(name)
                entities.append(name)

    return entities


def architecture_compliance_issue(section_content: str, row_label: str, expected_suffix):
    if not expected_suffix:
        return None
    row_marker = row_label.lower()
    for line in section_content.splitlines():
        if row_marker not in line.lower():
            continue
        if "|" not in line:
            continue
        normalized = line.replace(" ", "")
        if expected_suffix in line:
            return None
        if expected_suffix in normalized:
            return None
        if "{{" in line and "}}" in line:
            return (
                "Architecture Compliance table includes unresolved naming placeholder "
                f"for {row_label}."
            )
        return (
            "Architecture Compliance table has naming row for "
            f"{row_label} but does not include resolved suffix '{expected_suffix}'."
        )
    return (
        "Architecture Compliance table is missing required naming row: "
        f"{row_label}"
    )


naming_rules = normalize_naming_rules(json_naming_rules)
expected_rules = []
for key in [
    "entity",
    "dto",
    "use_case",
    "repository",
    "repository_impl",
    "event",
    "controller",
    "data_source",
    "provider",
]:
    if key in naming_rules:
        rule = naming_rules[key]
        suffix = naming_suffix(rule)
        if suffix:
            expected_rules.append((key, rule, suffix))

expected_entity_rule = naming_rules.get("entity", "")
expected_entity_suffix = naming_suffix(expected_entity_rule)

if expected_rules:
    arch = sections.get("## Architecture Compliance", "")
    for key, _, suffix in expected_rules:
        arch_check = architecture_compliance_issue(
            arch, naming_row_label(key), suffix
        )
        if arch_check:
            issue_messages.append(arch_check)

if expected_entity_suffix:
    domain_entities = parse_domain_entities(text)
    missing_suffix_entities = [
        entity_name
        for entity_name in domain_entities
        if not entity_name.endswith(expected_entity_suffix)
    ]
    if missing_suffix_entities:
        display_rule = (
            expected_entity_rule
            if expected_entity_rule
            else expected_entity_suffix
        )
        violation = (
            "Domain entities in spec.md do not follow naming policy (`Entities: "
            + display_rule
            + "`): "
            + ", ".join(sorted(missing_suffix_entities))
        )
        naming_policy_violations.append(violation)
        issue_messages.append(violation)

ok = not (
    missing_sections
    or empty_sections
    or issue_messages
    or placeholder_tokens
)

result = {
    "ok": ok,
    "spec": str(spec_path),
    "naming_source": json_naming_source,
    "missing_sections": missing_sections,
    "empty_sections": empty_sections,
    "issue_messages": issue_messages,
    "edge_case_count": edge_case_count,
    "placeholder_tokens": sorted(placeholder_tokens),
    "unresolved_clarifications": unresolved_clarifications,
    "concrete_ui_terms": sorted(concrete_ui_terms),
    "forbidden_naming_terms": sorted(forbidden_naming_terms),
    "naming_policy": naming_rules,
    "naming_policy_violations": naming_policy_violations,
}

if json_mode:
    print(json.dumps(result, ensure_ascii=False))
else:
    if ok:
        print(f"OK: spec.md prerequisite gate passed ({spec_path})")
    else:
        print("ERROR: spec.md prerequisite gate failed:", file=sys.stderr)
        if missing_sections:
            print("Missing sections:", file=sys.stderr)
            for item in missing_sections:
                print(f"  - {item}", file=sys.stderr)
        if empty_sections:
            print("Empty sections:", file=sys.stderr)
            for item in empty_sections:
                print(f"  - {item}", file=sys.stderr)
        if issue_messages:
            print("Rule violations:", file=sys.stderr)
            for item in issue_messages:
                print(f"  - {item}", file=sys.stderr)
        if placeholder_tokens:
            print("Unresolved placeholder tokens:", file=sys.stderr)
            for item in sorted(placeholder_tokens):
                print(f"  - [{item}]", file=sys.stderr)
        if concrete_ui_terms:
            print("Concrete UI terms detected:", file=sys.stderr)
            for item in sorted(concrete_ui_terms):
                print(f"  - {item}", file=sys.stderr)
        if forbidden_naming_terms:
            print("Ambiguous naming terms detected:", file=sys.stderr)
            for item in sorted(forbidden_naming_terms):
                print(f"  - {item}", file=sys.stderr)

if not ok:
    sys.exit(1)
PY
