#!/usr/bin/env bash

set -e

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

if [[ ! -f "$CODE_DOC" ]]; then
    echo "ERROR: tasks.md not found: $CODE_DOC" >&2
    exit 1
fi

if [[ ! -f "$DATA_MODEL" ]]; then
    echo "ERROR: data-model.md not found: $DATA_MODEL" >&2
    exit 1
fi

python3 - <<'PY' "$CODE_DOC" "$JSON_MODE" "$SCREEN_ABSTRACTION" "$QUICKSTART" "$DATA_MODEL" "$CONTRACTS_DIR" "$NAMING_SOURCE_KIND" "$NAMING_SOURCE_FILE" "$NAMING_SOURCE_REASON"
import json
import re
import sys
from pathlib import Path

code_doc_path = Path(sys.argv[1])
json_mode = sys.argv[2] == "true"
screen_abstraction_path = Path(sys.argv[3]) if len(sys.argv) > 3 else None
quickstart_path = Path(sys.argv[4]) if len(sys.argv) > 4 else None
data_model_path = Path(sys.argv[5]) if len(sys.argv) > 5 else None
contracts_dir_path = Path(sys.argv[6]) if len(sys.argv) > 6 else None
json_naming_source = {
    "kind": sys.argv[7] if len(sys.argv) > 7 else "DEFAULT",
    "file": sys.argv[8] if len(sys.argv) > 8 else "",
    "reason": sys.argv[9] if len(sys.argv) > 9 else "No naming policy metadata provided.",
}
text = code_doc_path.read_text(encoding="utf-8").replace("\r\n", "\n")


required_sections = [
    "## Metadata",
    "## Technical Context",
    "## Architecture Compliance",
    "## Screen Abstraction Contract",
    "## Parallel Development & Mock Strategy",
    "## code-tasks",
    "## Execution Context",
]

forbidden_regex = re.compile(
    r"\b(layout|pixel|padding|margin|spacing|typography|font|color|theme|style|animation|shadow|gradient|radius|border|position|widget\s+tree)\b",
    re.IGNORECASE,
)
name_forbidden_regex = re.compile(
    r"\b(utils\.dart|helpers\.dart|Util|Helper|Manager)\b"
)
table_separator = re.compile(r"^\|?[-:\s|]+\|?$")
obsolete_tag_re = re.compile(r"\[obsolete\s*:", re.IGNORECASE)


def parse_sections(markdown: str):
    sections = {}
    current = None
    buffer = []
    for line in markdown.splitlines():
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
    return sections


def should_skip_line(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return True
    if stripped.startswith("### "):
        return True
    if table_separator.fullmatch(stripped):
        return True

    lowered = stripped.lower()
    ignore_markers = (
        "do not include",
        "forbidden",
        "no concrete",
        "must remain abstraction-only",
        "implementation-agnostic",
    )
    return any(marker in lowered for marker in ignore_markers)


def parse_file_marked_sections(path: Path):
    if path is None:
        return None, None
    if not path.is_file():
        return None, None

    file_text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    return parse_sections(file_text), file_text


def parse_task_priority_sections(section_text: str):
    task_line_re = re.compile(r"^\s*-\s*\[(?P<state>[ xX])\]\s+(?P<body>.+)$")
    task_counts = {"P1": 0, "P2": 0, "P3": 0}
    blocking_counts = {"P1": 0, "P2": 0, "P3": 0}
    blocking_done = 0
    blocking_pending = 0
    priority_issues = []
    task_ids_seen = set()

    priority_re = re.compile(r"^P([123])$", re.IGNORECASE)

    for raw_line in section_text.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("### "):
            continue
        if table_separator.fullmatch(stripped):
            continue
        if obsolete_tag_re.search(stripped):
            continue

        match = task_line_re.match(stripped)
        if not match:
            continue

        state = match.group("state").strip().lower()
        done_state = state == "x"
        payload = (match.group("body") or "").strip()
        if not payload:
            continue

        parts = payload.split()
        task_id = ""
        tags = []

        if parts and re.fullmatch(r"C\d{3,4}", parts[0], re.IGNORECASE):
            task_id = parts[0].upper()
            if task_id in task_ids_seen:
                priority_issues.append(f"Duplicate task id: {task_id}")
                continue
            else:
                task_ids_seen.add(task_id)
            tag_block = payload[len(parts[0]):].lstrip()
            tags = [tag.strip() for tag in re.findall(r"\[([^\]]+)\]", tag_block)]
        else:
            tags = [tag.strip() for tag in re.findall(r"\[([^\]]+)\]", payload)]
            if tags and re.fullmatch(r"C\d{3,4}", tags[0], re.IGNORECASE):
                # fallback support for accidental bracketed id style: [C001] [P1] ...
                task_id = tags[0].upper()
                if task_id in task_ids_seen:
                    priority_issues.append(f"Duplicate task id: {task_id}")
                    continue
                else:
                    task_ids_seen.add(task_id)
                tags = tags[1:]
            else:
                priority_issues.append(f"Missing task id [C###] in task line: {stripped}")
                continue

        if not tags:
            priority_issues.append(
                f"No priority tag found for task id {task_id}: {stripped}"
            )
            continue

        priority_token = ""
        is_blocking = False
        first_token = tags[0].upper()

        if re.fullmatch(r"P([123])(?:[- ]BLOCKING)", first_token):
            priority_token = f"P{re.search(r'([123])', first_token).group(1)}"
            is_blocking = True
        elif first_token == "P2" and len(tags) > 1 and tags[1].upper() == "BLOCKING":
            priority_token = "P2"
            is_blocking = True
            tags = tags[2:]
        elif re.fullmatch(r"P([123])", first_token):
            priority_token = first_token
            tags = tags[1:]
        else:
            match = priority_re.match(first_token)
            if match:
                priority_token = f"P{match.group(1)}"
            else:
                priority_issues.append(
                    "Non-priority token in task line: '{}'".format(stripped)
                )
                continue

        if priority_token == "P2" and not is_blocking:
            if tags and tags[0].upper() == "BLOCKING":
                is_blocking = True
                tags = tags[1:]

        if "BLOCKING" in [tag.upper() for tag in tags]:
            priority_issues.append(
                f"BLOCKING must be used immediately after P2 priority: {stripped}"
            )
            continue

        if is_blocking and priority_token != "P2":
            priority_issues.append(f"P-BLOCKING is only valid for P2: {stripped}")
            continue

        if priority_token not in {"P1", "P2", "P3"}:
            priority_issues.append(
                "Non-priority token in task line: '{}'".format(stripped)
            )
            continue

        task_counts[priority_token] += 1
        if is_blocking:
            blocking_counts[priority_token] += 1
            if done_state:
                blocking_done += 1
            else:
                blocking_pending += 1

    return task_counts, blocking_counts, {"pending": blocking_pending, "done": blocking_done}, priority_issues


def has_contract_artifacts(path: Path) -> bool:
    if path is None or not path.is_dir():
        return False
    return any(entry.is_file() for entry in path.rglob("*"))


def is_unspecified(value: str) -> bool:
    cleaned = value.strip()
    lowered = cleaned.lower()
    if not cleaned:
        return True
    if lowered in {"n/a", "na", "none", "tbd"}:
        return True
    if cleaned.startswith("[") and cleaned.endswith("]"):
        return True
    return False


def extract_strategy_field(section_text: str, label: str) -> str:
    pattern = re.compile(
        rf"^\s*-\s*(?:\*\*)?{re.escape(label)}(?:\*\*)?\s*:\s*(.+)\s*$",
        re.IGNORECASE | re.MULTILINE,
    )
    match = pattern.search(section_text)
    return match.group(1).strip() if match else ""


def parse_counter_field(section_text, label):
    pattern = re.compile(
        rf"(?:^|\n)\s*(?:-\s*)?(?:\*\*)?{re.escape(label)}(?:\*\*)?\s*:\s*(\d+)\s*$",
        re.IGNORECASE | re.MULTILINE,
    )
    match = pattern.search(section_text)
    return int(match.group(1)) if match else None


def parse_text_field(section_text, label):
    pattern = re.compile(
        rf"(?:^|\n)\s*(?:-\s*)?(?:\*\*)?{re.escape(label)}(?:\*\*)?\s*:\s*(.+?)\s*$",
        re.IGNORECASE | re.MULTILINE,
    )
    match = pattern.search(section_text)
    return match.group(1).strip() if match else None


def parse_execution_context(section_text, code_tasks_text):
    context = {
        "Total": parse_counter_field(section_text, "Total"),
        "Pending": parse_counter_field(section_text, "Pending"),
        "In Progress": parse_counter_field(section_text, "In Progress"),
        "Done": parse_counter_field(section_text, "Done"),
        "Blocked": parse_counter_field(section_text, "Blocked"),
        "Next Task": parse_text_field(section_text, "Next Task"),
        "Last Updated": parse_text_field(section_text, "Last Updated"),
    }

    active_lines = [
        ln for ln in code_tasks_text.splitlines() if not obsolete_tag_re.search(ln)
    ]

    task_re = re.compile(
        r"^\s*-\s*\[(?P<state>[ xX])\]\s+\[?(?P<task_id>C\d{3,4})\]?\b",
        re.IGNORECASE,
    )
    task_order = []
    task_status = {}
    for line in active_lines:
        match = task_re.match(line)
        if not match:
            continue
        task_id = match.group("task_id").upper()
        task_order.append(task_id)
        task_status[task_id] = match.group("state").strip().lower() == "x"

    pending_tasks = [task_id for task_id in task_order if not task_status.get(task_id, True)]
    first_pending = pending_tasks[0] if pending_tasks else ""
    context["task_count"] = len(task_order)
    context["done_task_count"] = len([v for v in task_status.values() if v])
    context["first_pending_task"] = first_pending

    return context


sections = parse_sections(text)
missing_sections = [s for s in required_sections if s not in sections]
violations_by_section = {}
name_violations_by_section = {}
sections_to_scan = {
    "## code-tasks": sections.get("## code-tasks", ""),
    "## Screen Abstraction Contract": sections.get("## Screen Abstraction Contract", ""),
}

artifact_checks = []
parsed_screen, screen_text = parse_file_marked_sections(screen_abstraction_path)
parsed_quickstart, quickstart_text = parse_file_marked_sections(quickstart_path)
parsed_data_model, data_model_text = parse_file_marked_sections(data_model_path)

if parsed_screen is None or not screen_text:
    artifact_checks.append("Missing required artifact: screen_abstraction.md")
else:
    sections_to_scan["SCREEN_ABSTRACTION_DOC"] = screen_text
    for section_name in (
        "## Purpose",
        "## Global Guardrails",
        "## Story Coverage Map",
        "## Screen Contracts",
    ):
        if section_name not in parsed_screen:
            artifact_checks.append(
                f"screen_abstraction.md missing section: {section_name}"
            )

if parsed_quickstart is None or not quickstart_text:
    artifact_checks.append("Missing required artifact: quickstart.md")
else:
    sections_to_scan["QUICKSTART_DOC"] = quickstart_text
    for section_name in ("## Purpose", "## Validation Scenarios"):
        if section_name not in parsed_quickstart:
            artifact_checks.append(
                f"quickstart.md missing section: {section_name}"
            )

if parsed_data_model is None or not data_model_text:
    artifact_checks.append("Missing required artifact: data-model.md")
else:
    sections_to_scan["DATA_MODEL_DOC"] = data_model_text


def iter_scan_lines(text_block: str):
    for line in text_block.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("### "):
            continue
        if table_separator.fullmatch(stripped):
            continue
        yield line


for section_name, content in sections_to_scan.items():
    if content is None:
        continue

    in_code_block = False
    for line in iter_scan_lines(content):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_code_block = not in_code_block
            continue
        if in_code_block or should_skip_line(line):
            continue

        found_terms = {m.group(1).lower() for m in forbidden_regex.finditer(stripped)}
        if found_terms:
            bucket = violations_by_section.setdefault(section_name, set())
            bucket.update(found_terms)
        found_name_terms = {
            m.group(1) for m in name_forbidden_regex.finditer(stripped)
        }
        if found_name_terms:
            bucket = name_violations_by_section.setdefault(section_name, set())
            bucket.update(found_name_terms)


code_tasks_text = sections.get("## code-tasks", "")
task_counts, blocking_counts, blocking_state_counts, priority_issues = parse_task_priority_sections(
    code_tasks_text
)
execution_context = parse_execution_context(
    sections.get("## Execution Context", ""), code_tasks_text
)
execution_total = execution_context["Total"]
execution_done = execution_context["Done"]
execution_pending = execution_context["Pending"]
execution_in_progress = execution_context["In Progress"]
execution_blocked = execution_context["Blocked"]
execution_next = execution_context["Next Task"]
execution_updated = execution_context["Last Updated"]
first_pending_task = execution_context.get("first_pending_task", "")
execution_context_issues = []
parallel_strategy_issues = []
contracts_detected = has_contract_artifacts(contracts_dir_path)
parallel_strategy_text = sections.get("## Parallel Development & Mock Strategy", "")

if execution_total is None:
    execution_context_issues.append("Execution Context missing field: Total")
if execution_pending is None:
    execution_context_issues.append("Execution Context missing field: Pending")
if execution_in_progress is None:
    execution_context_issues.append("Execution Context missing field: In Progress")
if execution_done is None:
    execution_context_issues.append("Execution Context missing field: Done")
if execution_blocked is None:
    execution_context_issues.append("Execution Context missing field: Blocked")
if execution_next is None or not execution_next.strip():
    execution_context_issues.append("Execution Context missing field: Next Task")
if execution_updated is None or not execution_updated.strip():
    execution_context_issues.append("Execution Context missing field: Last Updated")

if execution_total is not None and execution_context["task_count"] != execution_total:
    execution_context_issues.append(
        f"Execution Context Total ({execution_total}) does not match active code tasks ({execution_context['task_count']})"
    )
if execution_done is not None and execution_done != execution_context["done_task_count"]:
    execution_context_issues.append(
        f"Execution Context Done ({execution_done}) does not match completed code tasks ({execution_context['done_task_count']})"
    )

if all(v is not None for v in [execution_total, execution_pending, execution_in_progress, execution_done, execution_blocked]):
    computed = (
        execution_pending
        + execution_in_progress
        + execution_done
        + execution_blocked
    )
    if computed != execution_total:
        execution_context_issues.append(
            f"Execution Context counters do not sum to Total ({computed} != {execution_total})"
        )

    if execution_blocked is not None and execution_blocked != blocking_state_counts["pending"]:
        execution_context_issues.append(
            f"Execution Context Blocked ({execution_blocked}) must match pending BLOCKING tasks ({blocking_state_counts['pending']})"
        )

if first_pending_task:
    next_task_id = ""
    normalized = execution_next.lower().strip() if execution_next else ""
    normalized_match = re.search(r"\bC\d+\b", execution_next or "", re.IGNORECASE)
    if normalized_match:
        next_task_id = normalized_match.group(0).upper()
        if next_task_id != first_pending_task:
            execution_context_issues.append(
                f"Execution Context Next Task ({next_task_id}) must point to first pending task ({first_pending_task})"
            )
    elif normalized not in {"none", "n/a", "na", "done", "completed", "finish", "finished"}:
        execution_context_issues.append(
            "Execution Context Next Task must be C### or terminal value (none/n/a/completed/done)"
        )
else:
    normalized = (execution_next or "").strip().lower()
    if normalized not in {"", "none", "n/a", "na", "done", "completed", "finish", "finished"}:
        execution_context_issues.append(
            f"Execution Context Next Task ({execution_next}) is stale because all code tasks are complete"
        )
    if execution_done is not None and execution_done < execution_context["task_count"]:
        execution_context_issues.append(
            "Execution Context Done count is less than Total while no pending tasks were detected"
        )

if not any(task_counts.values()):
    priority_issues.append(
        "tasks.md # code-tasks has no priority-tagged tasks. "
        "Use [P1], [P2], or [P3], "
        "with [P2][BLOCKING] for blocking P2 tasks."
    )

contracts_present = extract_strategy_field(parallel_strategy_text, "Contracts Present")
contracts_present_normalized = (
    "" if is_unspecified(contracts_present) else contracts_present.strip().lower()
)

if is_unspecified(contracts_present):
    parallel_strategy_issues.append(
        "Parallel Development & Mock Strategy must state whether contracts are present."
    )
else:
    normalized = contracts_present_normalized
    if normalized not in {"yes", "no", "true", "false", "y", "n", "1", "0"}:
        parallel_strategy_issues.append("Contracts Present should be set to YES/NO.")
    elif normalized in {"yes", "true", "y", "1"}:
        if not contracts_detected:
            parallel_strategy_issues.append(
                "Contracts Present is YES but no contracts files are present under contracts/."
            )
        strategy_lower = parallel_strategy_text.lower()
        if "mock" not in strategy_lower:
            parallel_strategy_issues.append(
                "Parallel Development & Mock Strategy must reference mock workflow when contracts exist."
            )

        mock_server_approach = extract_strategy_field(
            parallel_strategy_text, "Mock Server Approach"
        )
        startup_command = extract_strategy_field(parallel_strategy_text, "Startup Command")
        contract_coverage = extract_strategy_field(
            parallel_strategy_text, "Contract Coverage"
        )

        if is_unspecified(mock_server_approach):
            parallel_strategy_issues.append(
                "Mock Server Approach must be concrete when contracts exist."
            )
        if is_unspecified(startup_command):
            parallel_strategy_issues.append(
                "Startup Command must be concrete when contracts exist."
            )
        if is_unspecified(contract_coverage):
            parallel_strategy_issues.append(
                "Contract Coverage must list mocked contract scope when contracts exist."
            )

        has_mock_contract_task = False
        for raw_line in code_tasks_text.splitlines():
            stripped = raw_line.strip()
            if not re.match(r"^- \[(?: |x|X)\]\s+", stripped):
                continue
            if obsolete_tag_re.search(stripped):
                continue
            lowered = stripped.lower()
            if "mock" in lowered and ("contract" in lowered or "contracts/" in lowered):
                has_mock_contract_task = True
                break

        if not has_mock_contract_task:
            parallel_strategy_issues.append(
                "tasks.md # code-tasks must include at least one mock/contract task when contracts exist."
            )
    else:
        # explicit NO/false declarations are valid when no contracts artifacts are present
        if contracts_detected:
            parallel_strategy_issues.append(
                "Contracts Present is NO/false while contracts directory contains artifacts."
            )

forbidden_terms = sorted(
    {term for terms in violations_by_section.values() for term in terms}
)
forbidden_name_terms = sorted(
    {term for terms in name_violations_by_section.values() for term in terms}
)
ok = (
    not missing_sections
    and not forbidden_terms
    and not forbidden_name_terms
    and not priority_issues
    and not artifact_checks
    and not parallel_strategy_issues
    and not execution_context_issues
)

result = {
    "ok": ok,
    "code_doc": str(code_doc_path),
    "naming_source": json_naming_source,
    "missing_sections": missing_sections,
    "artifact_errors": artifact_checks,
    "contracts_detected": contracts_detected,
    "parallel_strategy_issues": parallel_strategy_issues,
    "forbidden_terms": forbidden_terms,
    "forbidden_name_terms": forbidden_name_terms,
    "priority_issues": priority_issues,
    "priority_counts": task_counts,
    "blocking_priority_counts": blocking_counts,
    "execution_context": execution_context,
    "execution_context_issues": execution_context_issues,
    "violation_sections": {
        section: sorted(list(terms))
        for section, terms in violations_by_section.items()
    },
    "name_violation_sections": {
        section: sorted(list(terms))
        for section, terms in name_violations_by_section.items()
    },
}

if json_mode:
    print(json.dumps(result, ensure_ascii=False))
else:
    if ok:
        print(f"OK: tasks.md prerequisite gate passed ({code_doc_path})")
    else:
        print("ERROR: tasks.md prerequisite gate failed:", file=sys.stderr)
        if missing_sections:
            print("Missing sections:", file=sys.stderr)
            for section in missing_sections:
                print(f"  - {section}", file=sys.stderr)
        if artifact_checks:
            print("Artifact errors:", file=sys.stderr)
            for issue in artifact_checks:
                print(f"  - {issue}", file=sys.stderr)
        if priority_issues:
            print("Priority tag issues:", file=sys.stderr)
            for issue in priority_issues:
                print(f"  - {issue}", file=sys.stderr)
        if execution_context_issues:
            print("Execution Context issues:", file=sys.stderr)
            for issue in execution_context_issues:
                print(f"  - {issue}", file=sys.stderr)
        if parallel_strategy_issues:
            print("Parallel development issues:", file=sys.stderr)
            for issue in parallel_strategy_issues:
                print(f"  - {issue}", file=sys.stderr)
        if forbidden_terms:
            print("Forbidden concrete UI terms detected:", file=sys.stderr)
            for section, terms in result["violation_sections"].items():
                print(f"  - {section}: {', '.join(terms)}", file=sys.stderr)
        if forbidden_name_terms:
            print("Forbidden naming terms detected:", file=sys.stderr)
            for section, terms in result["name_violation_sections"].items():
                print(f"  - {section}: {', '.join(terms)}", file=sys.stderr)

if not ok:
    raise SystemExit(1)
PY
