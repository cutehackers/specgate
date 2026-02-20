#!/usr/bin/env bash

set -euo pipefail

JSON_MODE=false
POINTER_PATH="specs/feature-stage.local.json"
FEATURE_DIR_ARG=""
STAGE_OVERRIDE=""
CURRENT_DOC_OVERRIDE=""
STATUS_OVERRIDE=""
PRESERVE_STAGE=false

usage() {
    cat <<'EOF'
Usage: specgate-sync-pointer.sh [options]

Options:
  --feature-dir <abs-path>   Feature directory to track (optional).
  --pointer <path>           Pointer json path (default: specs/feature-stage.local.json).
  --stage <stage>            Override stage.
  --current-doc <doc>        Override current_doc.
  --status <status>          Override status (in_progress|done|blocked).
  --preserve-stage           Keep existing stage/current_doc unless explicitly overridden.
  --json                     Emit json output.
  --help                     Show help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature-dir)
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --pointer)
            POINTER_PATH="$2"
            shift 2
            ;;
        --stage)
            STAGE_OVERRIDE="$2"
            shift 2
            ;;
        --current-doc)
            CURRENT_DOC_OVERRIDE="$2"
            shift 2
            ;;
        --status)
            STATUS_OVERRIDE="$2"
            shift 2
            ;;
        --preserve-stage)
            PRESERVE_STAGE=true
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

POINTER_DIR="$(dirname "$POINTER_PATH")"
mkdir -p "$POINTER_DIR"

python3 - <<'PY' \
    "$POINTER_PATH" \
    "$FEATURE_DIR_ARG" \
    "$STAGE_OVERRIDE" \
    "$CURRENT_DOC_OVERRIDE" \
    "$STATUS_OVERRIDE" \
    "$PRESERVE_STAGE" \
    "$JSON_MODE"
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

pointer_path = Path(sys.argv[1])
feature_dir_arg = sys.argv[2].strip()
stage_override = sys.argv[3].strip()
current_doc_override = sys.argv[4].strip()
status_override = sys.argv[5].strip()
preserve_stage = sys.argv[6] == "true"
json_mode = sys.argv[7] == "true"
obsolete_tag_re = re.compile(r"\[obsolete\s*:", re.IGNORECASE)

allowed_stages = {
    "specifying",
    "clarifying",
    "coding",
    "test_planning",
    "test_writing",
    "done",
    "blocked",
}
allowed_statuses = {"in_progress", "done", "blocked"}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_pointer(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid pointer json at {path}: {exc}")
    if not isinstance(data, dict):
        fail(f"pointer json must be an object: {path}")
    return data


def section_text(markdown: str, section_name: str) -> str:
    section_key = section_name.strip().lower()
    current = None
    buf = []
    sections = {}
    for line in markdown.splitlines():
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if match:
            if current is not None:
                sections[current] = "\n".join(buf)
            current = match.group(1).strip().lower()
            buf = []
            continue
        if current is not None:
            buf.append(line)
    if current is not None:
        sections[current] = "\n".join(buf)
    return sections.get(section_key, "")


def parse_task_counts(doc_path: Path, section_name: str, id_prefix: str) -> dict:
    if not doc_path.exists():
        return {"done": 0, "total": 0}
    text = doc_path.read_text(encoding="utf-8").replace("\r\n", "\n")
    body = section_text(text, section_name)
    if not body.strip():
        return {"done": 0, "total": 0}

    body_lines = []
    for line in body.splitlines():
        if obsolete_tag_re.search(line):
            continue
        body_lines.append(line)
    body = "\n".join(body_lines)

    all_tasks = re.findall(r"^\s*-\s*\[(?: |x|X)\]\s+.*$", body, re.MULTILINE)
    done_tasks = re.findall(r"^\s*-\s*\[(?:x|X)\]\s+.*$", body, re.MULTILINE)

    id_pattern = re.compile(
        rf"^\s*-\s*\[(?: |x|X)\]\s+(?:\[{re.escape(id_prefix)}\d+\]|{re.escape(id_prefix)}\d+)\b.*$",
        re.MULTILINE,
    )
    done_id_pattern = re.compile(
        rf"^\s*-\s*\[(?:x|X)\]\s+(?:\[{re.escape(id_prefix)}\d+\]|{re.escape(id_prefix)}\d+)\b.*$",
        re.MULTILINE,
    )
    id_tasks = id_pattern.findall(body)
    done_id_tasks = done_id_pattern.findall(body)

    if id_tasks:
        return {"done": len(done_id_tasks), "total": len(id_tasks)}
    return {"done": len(done_tasks), "total": len(all_tasks)}


def parse_feature_id(feature_dir: str, fallback: str) -> str:
    spec_path = Path(feature_dir) / "docs" / "spec.md"
    if not spec_path.exists():
        return fallback

    spec_text = spec_path.read_text(encoding="utf-8")
    patterns = [
        re.compile(r"^\s*[-*]?\s*\*\*Feature ID\*\*:\s*(.+?)\s*$", re.MULTILINE),
        re.compile(r"^\s*Feature ID\s*:\s*(.+?)\s*$", re.MULTILINE),
    ]
    for pattern in patterns:
        match = pattern.search(spec_text)
        if match:
            value = match.group(1).strip()
            value = re.sub(r"^`+|`+$", "", value).strip()
            if value:
                return value
    return fallback


def infer_stage(
    status: str,
    existing_stage: str,
    code_counts: dict,
    test_counts: dict,
) -> str:
    if status == "done":
        return "done"
    if status == "blocked":
        return existing_stage if existing_stage in allowed_stages else "blocked"

    code_total = int(code_counts.get("total", 0))
    code_done = int(code_counts.get("done", 0))
    test_total = int(test_counts.get("total", 0))
    test_done = int(test_counts.get("done", 0))

    if code_total == 0:
        if existing_stage in {"specifying", "clarifying"}:
            return existing_stage
        return "specifying"
    if code_done < code_total:
        return "coding"
    if test_total == 0:
        return "test_planning"
    if test_done < test_total:
        return "test_writing"
    return "test_writing"


data = read_pointer(pointer_path)

if stage_override and stage_override not in allowed_stages:
    fail(f"invalid stage override: {stage_override}")
if status_override and status_override not in allowed_statuses:
    fail(f"invalid status override: {status_override}")

existing_feature_dir = str(data.get("feature_dir", "")).strip()
feature_dir_raw = feature_dir_arg or existing_feature_dir
if not feature_dir_raw:
    fail("feature_dir is required (pass --feature-dir or set pointer first)")

feature_dir_path = Path(feature_dir_raw).expanduser()
if not feature_dir_path.is_absolute():
    feature_dir_path = (Path.cwd() / feature_dir_path).resolve()
else:
    feature_dir_path = feature_dir_path.resolve()
feature_dir = str(feature_dir_path)

existing_feature_id = str(data.get("feature_id", "")).strip()
feature_id_fallback = (
    existing_feature_id if feature_dir == existing_feature_dir else ""
)
feature_id = parse_feature_id(feature_dir, feature_id_fallback)

code_counts = parse_task_counts(
    Path(feature_dir) / "docs" / "tasks.md",
    "code-tasks",
    "C",
)
test_counts = parse_task_counts(
    Path(feature_dir) / "docs" / "test-spec.md",
    "test-code",
    "TC",
)

status = status_override or str(data.get("status", "in_progress")).strip()
if status not in allowed_statuses:
    status = "in_progress"

existing_stage = str(data.get("stage", "")).strip()
if status == "done":
    stage = "done"
elif stage_override:
    stage = stage_override
elif (
    preserve_stage
    and existing_stage in allowed_stages
    and existing_stage != "done"
):
    stage = existing_stage
else:
    stage = infer_stage(status, existing_stage, code_counts, test_counts)

default_doc_by_stage = {
    "specifying": "spec.md",
    "clarifying": "spec.md",
    "coding": "tasks.md",
    "test_planning": "test-spec.md",
    "test_writing": "test-spec.md",
    "blocked": str(data.get("current_doc", "")).strip() or "tasks.md",
    "done": "",
}
current_doc = (
    ""
    if stage == "done"
    else (
        current_doc_override
        if current_doc_override
        else (
            str(data.get("current_doc", "")).strip()
            if preserve_stage and not stage_override and str(data.get("current_doc", "")).strip()
            else default_doc_by_stage.get(stage, "tasks.md")
        )
    )
)

updated = dict(data)
updated.update(
    {
        "feature_dir": feature_dir,
        "feature_id": feature_id,
        "status": status,
        "stage": stage,
        "current_doc": current_doc,
        "progress": {
            "code": code_counts,
            "test": test_counts,
        },
        "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
)


def normalize_pointer(payload: dict) -> dict:
    normalized = dict(payload)
    normalized.pop("updated_at", None)
    return normalized


def changed_payload(before: dict, after: dict) -> tuple[bool, dict, dict]:
    before_norm = normalize_pointer(before)
    after_norm = normalize_pointer(after)
    changed = before_norm != after_norm
    return changed, before_norm, after_norm


changed, normalized_before, normalized_after = changed_payload(data, updated)

if not changed:
    unchanged_out = {
        "changed": False,
        "message": "SpecGate pointer already up to date",
        "before": normalized_before,
        "after": normalized_after,
    }
    if json_mode:
        print(json.dumps(unchanged_out, ensure_ascii=False))
    else:
        print("POINTER_SYNC: unchanged")
    raise SystemExit(0)

pointer_path.write_text(
    json.dumps(updated, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

if json_mode:
    print(
        json.dumps(
            {
                "changed": True,
                "before": normalized_before,
                "after": normalize_pointer(updated),
                "updated_pointer": updated,
            },
            ensure_ascii=False,
        )
    )
else:
    print("POINTER_SYNC: updated")
    print(f"POINTER_PATH: {pointer_path}")
    print(f"FEATURE_DIR: {updated['feature_dir']}")
    print(f"FEATURE_ID: {updated.get('feature_id', '')}")
    print(f"STATUS: {updated['status']}")
    print(f"STAGE: {updated['stage']}")
    print(f"CURRENT_DOC: {updated['current_doc']}")
    code = updated["progress"]["code"]
    test = updated["progress"]["test"]
    print(f"CODE_PROGRESS: {code.get('done', 0)}/{code.get('total', 0)}")
    print(f"TEST_PROGRESS: {test.get('done', 0)}/{test.get('total', 0)}")
    print(f"UPDATED_AT: {updated.get('updated_at', '')}")
PY
