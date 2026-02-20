#!/usr/bin/env bash

set -e

JSON_MODE=false
MIGRATE=false
POINTER_PATH="specs/feature-stage.local.json"

usage() {
    cat <<'USAGE'
Usage: specgate-status.sh [options]

Options:
  --json             Print JSON output.
  --migrate          Recompute stage/current_doc/progress and update pointer timestamp.
  --pointer <path>   Pointer json path (default: specs/feature-stage.local.json).
  --help             Show this message.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --migrate)
            MIGRATE=true
            shift
            ;;
        --pointer)
            POINTER_PATH="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option '$1'." >&2
            exit 1
            ;;
    esac

done

if [[ ! -f "$POINTER_PATH" ]]; then
    echo "ERROR: pointer file not found: $POINTER_PATH" >&2
    exit 1
fi

python3 - <<'PY' "$POINTER_PATH" "$JSON_MODE" "$MIGRATE"
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

pointer = Path(sys.argv[1])
json_mode = sys.argv[2] == "true"
migrate = sys.argv[3] == "true"
obsolete_tag_re = re.compile(r"\[obsolete\s*:", re.IGNORECASE)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


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
    text = read_text(doc_path)
    body = section_text(text.replace("\r\n", "\n"), section_name)
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

    id_re = re.compile(
        rf"^\s*-\s*\[(?: |x|X)\]\s+(?:\[{re.escape(id_prefix)}\d+\]|{re.escape(id_prefix)}\d+)\b.*$",
        re.MULTILINE,
    )
    done_id_re = re.compile(
        rf"^\s*-\s*\[(?:x|X)\]\s+(?:\[{re.escape(id_prefix)}\d+\]|{re.escape(id_prefix)}\d+)\b.*$",
        re.MULTILINE,
    )
    id_tasks = id_re.findall(body)
    done_id_tasks = done_id_re.findall(body)

    if id_tasks:
        return {"done": len(done_id_tasks), "total": len(id_tasks)}
    return {"done": len(done_tasks), "total": len(all_tasks)}


def infer_stage(status: str, existing_stage: str, code_counts: dict, test_counts: dict) -> str:
    allowed_stages = {
        "specifying",
        "clarifying",
        "coding",
        "test_planning",
        "test_writing",
        "done",
        "blocked",
    }
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


with open(pointer, "r", encoding="utf-8") as f:
    data = json.load(f)

status = data.get("status", "in_progress")
if status == "done":
    default_stage = "done"
elif status == "blocked":
    default_stage = data.get("stage", "blocked")
else:
    default_stage = "specifying"

allowed_stages = {
    "specifying",
    "clarifying",
    "coding",
    "test_planning",
    "test_writing",
    "done",
    "blocked",
}
stage = data.get("stage", default_stage)
if stage not in allowed_stages:
    stage = default_stage

current_doc = data.get("current_doc", "")
progress = data.get("progress", {"code": {"done": 0, "total": 0}, "test": {"done": 0, "total": 0}})

if migrate:
    feature_dir = Path(data.get("feature_dir", "")).expanduser()
    if not feature_dir.is_absolute():
        feature_dir = (pointer.parent / feature_dir).resolve()
    if not feature_dir.exists():
        raise SystemExit(f"ERROR: feature_dir not found: {feature_dir}")

    code_counts = parse_task_counts(
        feature_dir / "docs" / "tasks.md",
        "code-tasks",
        "C",
    )
    test_counts = parse_task_counts(
        feature_dir / "docs" / "test-spec.md",
        "test-code",
        "TC",
    )

    stage = infer_stage(status, stage, code_counts, test_counts)
    current_doc = data.get("current_doc", "")
    if stage == "blocked" and not current_doc:
        current_doc = "tasks.md"
    elif stage != "done":
        current_doc = {
            "specifying": "spec.md",
            "clarifying": "spec.md",
            "coding": "tasks.md",
            "test_planning": "test-spec.md",
            "test_writing": "test-spec.md",
            "done": "",
            "blocked": current_doc or "tasks.md",
        }[stage]

    progress = {
        "code": code_counts,
        "test": test_counts,
    }
    data.update(
        {
            "stage": stage,
            "current_doc": current_doc,
            "progress": progress,
            "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
    )
    with open(pointer, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

out = {
    "feature_dir": data.get("feature_dir", ""),
    "feature_id": data.get("feature_id", ""),
    "status": status,
    "stage": stage,
    "current_doc": current_doc,
    "progress": progress,
    "updated_at": data.get("updated_at", ""),
}

if json_mode:
    print(json.dumps(out, ensure_ascii=False))
else:
    code = progress.get("code", {})
    test = progress.get("test", {})
    print(f"FEATURE_DIR: {out['feature_dir']}")
    print(f"FEATURE_ID: {out['feature_id']}")
    print(f"STATUS: {out['status']}")
    print(f"STAGE: {out['stage']}")
    print(f"CURRENT_DOC: {out['current_doc']}")
    print(f"CODE_PROGRESS: {code.get('done',0)}/{code.get('total',0)}")
    print(f"TEST_PROGRESS: {test.get('done',0)}/{test.get('total',0)}")
    print(f"UPDATED_AT: {out['updated_at']}")
PY
