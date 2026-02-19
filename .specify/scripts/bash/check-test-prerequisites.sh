#!/usr/bin/env bash

set -euo pipefail

JSON_MODE=false
PATHS_ONLY=false
FEATURE_DIR_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --paths-only)
            PATHS_ONLY=true
            shift
            ;;
        --feature-dir)
            FEATURE_DIR_ARG="$2"
            shift 2
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

TEST_SPEC="$FEATURE_DOCS_DIR/test-spec.md"

if $PATHS_ONLY; then
    if $JSON_MODE; then
        printf '{"REPO_ROOT":"%s","FEATURE_DIR":"%s","FEATURE_DOCS_DIR":"%s","FEATURE_SPEC":"%s","TEST_SPEC":"%s"}\n' \
            "$REPO_ROOT" "$FEATURE_DIR" "$FEATURE_DOCS_DIR" "$FEATURE_SPEC" "$TEST_SPEC"
    else
        echo "REPO_ROOT: $REPO_ROOT"
        echo "FEATURE_DIR: $FEATURE_DIR"
        echo "FEATURE_DOCS_DIR: $FEATURE_DOCS_DIR"
        echo "FEATURE_SPEC: $FEATURE_SPEC"
        echo "TEST_SPEC: $TEST_SPEC"
    fi
    exit 0
fi

if [[ ! -f "$TEST_SPEC" ]]; then
    if $JSON_MODE; then
        printf '{"ok":false,"FEATURE_DIR":"%s","FEATURE_DOCS_DIR":"%s","TEST_SPEC":"%s","errors":["test-spec.md not found. Run /test-spec first."]}\n' \
            "$FEATURE_DIR" "$FEATURE_DOCS_DIR" "$TEST_SPEC"
    else
        echo "ERROR: test-spec.md not found in $FEATURE_DOCS_DIR" >&2
        echo "Run /test-spec first." >&2
    fi
    exit 1
fi

python3 - <<'PY' "$TEST_SPEC" "$JSON_MODE" "$FEATURE_DIR" "$FEATURE_DOCS_DIR"
import json
import re
import sys
from pathlib import Path

test_spec_path = Path(sys.argv[1])
json_mode = sys.argv[2] == "true"
feature_dir = sys.argv[3]
feature_docs_dir = sys.argv[4]
text = test_spec_path.read_text(encoding="utf-8").replace("\r\n", "\n")
obsolete_tag_re = re.compile(r"\[obsolete\s*:", re.IGNORECASE)

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

errors = []

if "## test-code" not in sections:
    errors.append("test-spec.md is missing ## test-code section")
if "## Execution Context" not in sections:
    errors.append("test-spec.md is missing ## Execution Context section")
if "## Test Component Inventory" not in sections:
    errors.append("test-spec.md is missing ## Test Component Inventory section")

test_code_text = sections.get("## test-code", "")
execution_context_text = sections.get("## Execution Context", "")
inventory_text = sections.get("## Test Component Inventory", "")
active_test_code_lines = [
    ln
    for ln in test_code_text.splitlines()
    if not obsolete_tag_re.search(ln)
]
active_test_code_text = "\n".join(active_test_code_lines)

all_task_lines = re.findall(r"^\s*-\s*\[(?: |x|X)\]\s+.*$", active_test_code_text, re.MULTILINE)
tc_task_lines = re.findall(
    r"^\s*-\s*\[(?: |x|X)\]\s+\[?(TC\d+)\]?\b.*$",
    active_test_code_text,
    re.MULTILINE,
)
done_task_lines = re.findall(r"^\s*-\s*\[(?:x|X)\]\s+.*$", active_test_code_text, re.MULTILINE)

task_order = []
task_status = {}
for line in active_test_code_text.splitlines():
    match = re.match(
        r"^\s*-\s*\[(?P<state>[ xX])\]\s+\[?(?P<task_id>TC\d+)\]?\b",
        line,
    )
    if not match:
        continue
    task_id = match.group("task_id")
    state = match.group("state").strip().lower()
    if task_id not in task_status:
        task_order.append(task_id)
    task_status[task_id] = state == "x"

pended_task_ids = [task_id for task_id in task_order if not task_status.get(task_id, True)]
first_pending_task = pended_task_ids[0] if pended_task_ids else ""

if not all_task_lines:
    errors.append("test-code must include at least one checklist task row")
if not tc_task_lines:
    errors.append("test-code must include at least one TC### task id")

def clean_cell(raw: str) -> str:
    raw = raw.strip()
    if not raw:
        return ""

    if raw.startswith("[") and "](" in raw and raw.endswith(")"):
        match = re.search(r"\(([^)]+)\)", raw)
        if match:
            raw = match.group(1).strip()

    return raw.strip("`").strip()

task_ids_seen = set()
task_ids_order = []
for line in active_test_code_text.splitlines():
    match = re.match(r"^\s*-\s*\[(?: |x|X)\]\s+\[?(TC\d+)\]?\b", line)
    if not match:
        continue
    task_id = match.group(1)
    if task_id in task_ids_seen:
        errors.append(f"test-code has duplicate task id: {task_id}")
    else:
        task_ids_seen.add(task_id)
        task_ids_order.append(task_id)

inventory_test_ids = []
inventory_id_seen = set()
table_lines = [
    ln.strip()
    for ln in inventory_text.splitlines()
    if ln.strip().startswith("|")
]
if len(table_lines) < 2:
    errors.append("Test Component Inventory table must include header and at least one row")
else:
    header = [cell.strip() for cell in table_lines[0].strip("|").split("|")]
    required_cols = {"Test ID", "Source File", "Coverage Target"}
    missing_cols = sorted(required_cols - set(header))
    if missing_cols:
        errors.append(
            "Test Component Inventory missing required columns: "
            + ", ".join(missing_cols)
        )
    else:
        header_idx = {name: idx for idx, name in enumerate(header)}
        data_row_count = 0
        invalid_targets = []
        invalid_ids = []
        for raw_line in table_lines[1:]:
            if re.fullmatch(r"\|?[-:\s|]+\|?", raw_line):
                continue
            cells = [cell.strip() for cell in raw_line.strip("|").split("|")]
            if len(cells) < len(header):
                cells += [""] * (len(header) - len(cells))

            test_id = cells[header_idx["Test ID"]].strip() or "(unknown)"
            source_file = cells[header_idx["Source File"]].strip()
            source_file = clean_cell(source_file)
            test_file = ""
            if "Test File" in header_idx:
                test_file = clean_cell(cells[header_idx["Test File"]])
            target_raw = cells[header_idx["Coverage Target"]].strip()
            data_row_count += 1

            if test_id in inventory_id_seen:
                errors.append(f"Test Component Inventory has duplicate Test ID: {test_id}")
            else:
                inventory_id_seen.add(test_id)
                inventory_test_ids.append(test_id)

            if not re.fullmatch(r"TC\d{3,4}", test_id):
                invalid_ids.append((test_id, raw_line.strip()))

            if not source_file:
                errors.append(f"Inventory row {test_id} has empty Source File")
            if "Test File" in header_idx and not test_file:
                errors.append(f"Inventory row {test_id} has empty Test File")

            target_match = re.search(r"(\d+(?:\.\d+)?)\s*%?$", target_raw)
            if not target_match:
                invalid_targets.append((test_id, target_raw))
                continue
            target_value = float(target_match.group(1))
            if target_value < 0 or target_value > 100:
                invalid_targets.append((test_id, target_raw))

        if data_row_count == 0:
            errors.append("Test Component Inventory must include at least one data row")
        if invalid_ids:
            formatted = ", ".join(
                f"{row_id} (expected format TC### or TC####)"
                for row_id, _ in invalid_ids
            )
            errors.append("Test Component Inventory Test ID format must be TC### or TC####: " + formatted)
        if invalid_targets:
            errors.append(
                "Invalid Coverage Target values in inventory: "
                + ", ".join(
                    f"{test_id}='{target}'"
                    for test_id, target in invalid_targets
                )
            )

        missing_in_inventory = [id_ for id_ in task_ids_order if id_ not in inventory_id_seen]
        if missing_in_inventory:
            errors.append(
                "test-code includes Test IDs missing from inventory: "
                + ", ".join(missing_in_inventory)
            )

        orphan_inventory_ids = [
            id_
            for id_ in inventory_test_ids
            if id_ not in task_ids_seen
        ]
        if orphan_inventory_ids:
            errors.append(
                "Test Component Inventory contains Test IDs not present in test-code: "
                + ", ".join(orphan_inventory_ids)
            )

forbidden_regex = re.compile(
    r"\b(layout|pixel|padding|margin|spacing|typography|font|color|theme|style|animation|motion|shadow|gradient|radius|border|position|widget tree)\b",
    re.IGNORECASE,
)
forbidden_terms = sorted({m.group(1).lower() for m in forbidden_regex.finditer(active_test_code_text)})
if forbidden_terms:
    errors.append(
        "test-code includes concrete UI terms: " + ", ".join(forbidden_terms)
    )


def parse_counter(label: str):
    pattern = re.compile(
        rf"(?:^|\n)\s*(?:-\s*)?(?:\*\*)?{re.escape(label)}(?:\*\*)?\s*:\s*(\d+)\s*$",
        re.IGNORECASE | re.MULTILINE,
    )
    match = pattern.search(execution_context_text)
    return int(match.group(1)) if match else None


def parse_text_field(label: str):
    pattern = re.compile(
        rf"(?:^|\n)\s*(?:-\s*)?(?:\*\*)?{re.escape(label)}(?:\*\*)?\s*:\s*(.+?)\s*$",
        re.IGNORECASE | re.MULTILINE,
    )
    match = pattern.search(execution_context_text)
    return match.group(1).strip() if match else None


context = {
    "Total": parse_counter("Total"),
    "Pending": parse_counter("Pending"),
    "In Progress": parse_counter("In Progress"),
    "Done": parse_counter("Done"),
    "Blocked": parse_counter("Blocked"),
    "Next Task": parse_text_field("Next Task"),
    "Last Updated": parse_text_field("Last Updated"),
}

for field in ("Total", "Pending", "In Progress", "Done", "Blocked", "Next Task", "Last Updated"):
    if context[field] is None:
        errors.append(f"Execution Context missing field: {field}")

task_total = len(all_task_lines)
task_done = len(done_task_lines)

if context["Total"] is not None and context["Total"] != task_total:
    errors.append(
        f"Execution Context Total ({context['Total']}) does not match test-code task count ({task_total})"
    )
if context["Done"] is not None and context["Done"] != task_done:
    errors.append(
        f"Execution Context Done ({context['Done']}) does not match checked tasks ({task_done})"
    )

if all(context[k] is not None for k in ("Total", "Pending", "In Progress", "Done", "Blocked")):
    composed = (
        context["Pending"]
        + context["In Progress"]
        + context["Done"]
        + context["Blocked"]
    )
    if composed != context["Total"]:
        errors.append(
            f"Execution Context counters do not sum to Total ({composed} != {context['Total']})"
        )

if context["Next Task"] is not None and context["Next Task"]:
    normalized_next = context["Next Task"].strip().lower()
    match = re.search(r"\bTC\d+\b", context["Next Task"], re.IGNORECASE)

    if match:
        next_task_id = (match.group(0) if match else "").upper()
        if first_pending_task:
            if next_task_id != first_pending_task:
                errors.append(
                    f"Execution Context Next Task ({next_task_id}) must point to first pending task ({first_pending_task})"
                )
        else:
            errors.append(
                f"Execution Context Next Task ({next_task_id}) is stale because all test tasks are complete"
            )
    elif normalized_next not in {"none", "n/a", "na", "-", "done", "completed", "finish", "finished"}:
        errors.append(
            "Execution Context Next Task must be TC### or terminal value (none/n/a/completed/done)"
        )
    elif first_pending_task:
        errors.append(
            "Execution Context Next Task is terminal while pending tasks remain"
        )
else:
    if first_pending_task:
        errors.append("Execution Context Next Task is required while pending tasks remain")

if first_pending_task and context["Done"] == task_total:
    errors.append(
        "Execution Context counters indicate no pending tasks, but pending test tasks were detected"
    )

if not first_pending_task and context["Done"] < task_total:
    errors.append("Execution Context has no pending tasks but Done count is less than Total")

result = {
    "ok": not errors,
    "FEATURE_DIR": feature_dir,
    "FEATURE_DOCS_DIR": feature_docs_dir,
    "TEST_SPEC": str(test_spec_path),
    "AVAILABLE_TEST_DOCS": ["test-spec.md"],
    "TASK_COUNTS": {
        "total": task_total,
        "done": task_done,
        "pending_like": max(task_total - task_done, 0),
    },
    "forbidden_terms": forbidden_terms,
    "errors": errors,
}

if json_mode:
    print(json.dumps(result, ensure_ascii=False))
else:
    if result["ok"]:
        print(f"FEATURE_DIR:{feature_dir}")
        print(f"FEATURE_DOCS_DIR:{feature_docs_dir}")
        print("AVAILABLE_TEST_DOCS:")
        print("  ✓ test-spec.md")
        print(f"TASK_COUNTS: total={task_total}, done={task_done}")
    else:
        print("ERROR: test-spec prerequisite gate failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)

if errors:
    sys.exit(1)
PY
