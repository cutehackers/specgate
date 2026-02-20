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
        printf '{"ok":false,"spec":"%s","naming_source":{"kind":"%s","file":"%s","reason":"%s"},"missing_sections":[],"empty_sections":[],"issue_messages":["spec.md not found"],"edge_case_count":0,"placeholder_tokens":[],"unresolved_clarifications":0,"concrete_ui_terms":[],"forbidden_naming_terms":[]}\n' \
            "$FEATURE_SPEC" "$NAMING_SOURCE_KIND" "$NAMING_SOURCE_FILE" "$NAMING_SOURCE_REASON"
    else
        echo "ERROR: spec.md not found: $FEATURE_SPEC" >&2
    fi
    exit 1
fi

python3 - <<'PY' "$FEATURE_SPEC" "$JSON_MODE" "$NAMING_SOURCE_KIND" "$NAMING_SOURCE_FILE" "$NAMING_SOURCE_REASON"
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
text = spec_path.read_text(encoding="utf-8").replace("\r\n", "\n")

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
