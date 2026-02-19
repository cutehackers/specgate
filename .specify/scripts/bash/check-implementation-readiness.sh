#!/usr/bin/env bash

set -euo pipefail

JSON_MODE=false
FEATURE_DIR_ARG=""

usage() {
    cat <<'USAGE'
Usage: check-implementation-readiness.sh --feature-dir <abs-path> [options]

Options:
  --feature-dir <abs-path>   Absolute path to feature folder (required)
  --json                     Print JSON output
  --help                     Show this message
USAGE
}

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

if [[ ! -f "$CODE_DOC" ]]; then
    echo "ERROR: code.md not found: $CODE_DOC" >&2
    exit 1
fi

python3 - <<'PY' "$CODE_DOC" "$JSON_MODE"
import json
import re
import sys
from pathlib import Path

code_doc_path = Path(sys.argv[1])
json_mode = sys.argv[2] == "true"

text = code_doc_path.read_text(encoding="utf-8").replace("\r\n", "\n")

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

code_tasks = sections.get("## code-tasks", "")

task_re = re.compile(r"^\s*-\s*\[(?P<done>[ xX])\]\s+(?P<rest>.+)$")
priority_re = re.compile(r"^P([123])$", re.IGNORECASE)
obsolete_tag_re = re.compile(r"\[obsolete\s*:\s*", re.IGNORECASE)

stats = {
    "total": 0,
    "done": 0,
    "pending": 0,
    "priority_counts": {"P1": {"total": 0, "done": 0}, "P2": {"total": 0, "done": 0}, "P3": {"total": 0, "done": 0}},
    "blocking_p2": {"total": 0, "done": 0},
}

blocked_items = []
seen_task_ids = set()
invalid_priority_rows = []

for raw_line in code_tasks.splitlines():
    match = task_re.match(raw_line.strip())
    if not match:
        continue

    if obsolete_tag_re.search(match.group("rest").strip()):
        continue

    line = match.group("rest").strip()
    done = match.group("done").strip().lower() == "x"

    tokens = line.split()
    if not tokens:
        invalid_priority_rows.append(raw_line)
        continue

    tags = []
    task_id = ""
    if re.fullmatch(r"C\d{3,4}", tokens[0], re.IGNORECASE):
        task_id = tokens[0].upper()
        if task_id in seen_task_ids:
            invalid_priority_rows.append(f"Duplicate task id: {task_id}")
            continue
        seen_task_ids.add(task_id)
        tag_block = line[len(tokens[0]):].lstrip()
        tags = [tag.strip() for tag in re.findall(r"\[([^\]]+)\]", tag_block)]
    else:
        tag_block = line
        tags = [tag.strip() for tag in re.findall(r"\[([^\]]+)\]", tag_block)]
        if tags and re.fullmatch(r"C\d{3,4}", tags[0], re.IGNORECASE):
            # fallback support for accidental bracketed id style: [C001] [P1] ...
            task_id = tags[0].upper()
            if task_id in seen_task_ids:
                invalid_priority_rows.append(f"Duplicate task id: {task_id}")
                continue
            seen_task_ids.add(task_id)
            tags = tags[1:]
        else:
            invalid_priority_rows.append(f"Missing required task id tag [C###] in: {raw_line}")
            continue

    priority = ""
    is_blocking = False

    # Expected patterns: [P2], [P2][BLOCKING], [P2-BLOCKING], [P2 BLOCKING]
    if not tags:
        invalid_priority_rows.append(raw_line)
        continue
    priority_token = tags[0].upper()
    if re.fullmatch(r"P([123])(?:[- ]BLOCKING)", priority_token):
        priority = f"P{re.search(r'([123])', priority_token).group(1)}"
        is_blocking = True
    elif priority_token == "P2" and len(tags) > 1 and tags[1].upper() == "BLOCKING":
        priority = "P2"
        is_blocking = True
        tags = tags[2:]
    elif re.fullmatch(r"P([123])", priority_token):
        priority = priority_token
    else:
        match = priority_re.match(priority_token)
        if match:
            priority = f"P{match.group(1)}"
        else:
            invalid_priority_rows.append(raw_line)
            continue
        tags = tags[1:]

    if priority == "P2" and not is_blocking:
        if tags and tags[0].upper() == "BLOCKING":
            is_blocking = True
            tags = tags[1:]

    if "BLOCKING" in [tag.upper() for tag in tags]:
        invalid_priority_rows.append(
            f"BLOCKING must be used immediately after P2 priority: {raw_line}"
        )
        continue

    if is_blocking and priority != "P2":
        invalid_priority_rows.append(f"P-BLOCKING is only valid for P2: {raw_line}")
        continue

    if priority not in stats["priority_counts"]:
        invalid_priority_rows.append(raw_line)
        continue

    stats["total"] += 1
    priority_stats = stats["priority_counts"][priority]
    priority_stats["total"] += 1
    if done:
        stats["done"] += 1
        priority_stats["done"] += 1
        if is_blocking:
            stats["blocking_p2"]["done"] += 1
    else:
        stats["pending"] += 1
        if is_blocking:
            blocked_items.append({"id": task_id, "priority": priority, "status": "PENDING", "reason": "P2-BLOCKING"})

    if priority == "P2" and is_blocking:
        stats["blocking_p2"]["total"] += 1

if stats["total"] == 0:
    invalid_priority_rows.append("No valid code tasks found in ## code-tasks")

stats["ready_for_test_spec"] = (
    stats["priority_counts"]["P1"]["done"] == stats["priority_counts"]["P1"]["total"]
    and stats["blocking_p2"]["done"] == stats["blocking_p2"]["total"]
)

ok = len(invalid_priority_rows) == 0 and stats["ready_for_test_spec"]

if json_mode:
    if not ok and not stats["ready_for_test_spec"] and stats["total"] > 0:
        status = "BLOCKED"
    elif not ok:
        status = "INVALID"
    else:
        status = "READY"

    result = {
        "ok": ok,
        "code_doc": str(code_doc_path),
        "status": status,
        "ready_for_test_spec": stats["ready_for_test_spec"],
        "pending_blocks": blocked_items[:20],
        "invalid_priority_rows": invalid_priority_rows,
        "stats": stats,
    }
    print(json.dumps(result, ensure_ascii=False))
else:
    print(f"OK: implementation readiness check for {code_doc_path}")
    print(f"  total={stats['total']}, done={stats['done']}, pending={stats['pending']}")
    print("  P1: {}/{} done".format(stats['priority_counts']['P1']['done'], stats['priority_counts']['P1']['total']))
    print("  P2: {}/{} done".format(stats['priority_counts']['P2']['done'], stats['priority_counts']['P2']['total']))
    print("  P2-BLOCKING: {}/{} done".format(stats['blocking_p2']['done'], stats['blocking_p2']['total']))
    print(f"  ready_for_test_spec={stats['ready_for_test_spec']}")

    if invalid_priority_rows:
        print("ERROR: invalid code task priority format:")
        for raw_line in invalid_priority_rows:
            print(f"  - {raw_line}")

    if not stats["ready_for_test_spec"]:
        print("ERROR: implementation is not ready to move to /test-spec.")
        for item in blocked_items[:20]:
            print(f"  - {item['id']}: {item['reason']} pending")

if not ok:
    raise SystemExit(1)
PY
