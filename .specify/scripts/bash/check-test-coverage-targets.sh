#!/usr/bin/env bash

set -euo pipefail

JSON_MODE=false
FEATURE_DIR_ARG=""
LCOV_PATH_ARG="coverage/lcov.info"
ALLOW_MISSING_LCOV=false

usage() {
    cat <<'USAGE'
Usage: check-test-coverage-targets.sh --feature-dir <abs-path> [options]

Options:
  --feature-dir <abs-path>   Absolute path to feature directory (required)
  --lcov <path>              Path to lcov.info (default: coverage/lcov.info)
  --allow-missing-lcov       Do not fail when lcov is not yet generated; return skipped coverage status
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
        --lcov)
            LCOV_PATH_ARG="$2"
            shift 2
            ;;
        --json)
            JSON_MODE=true
            shift
            ;;
        --allow-missing-lcov)
            ALLOW_MISSING_LCOV=true
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

TEST_SPEC="$FEATURE_DOCS_DIR/test-spec.md"
if [[ ! -f "$TEST_SPEC" ]]; then
    echo "ERROR: test-spec.md not found: $TEST_SPEC" >&2
    exit 1
fi

LCOV_PATH="$LCOV_PATH_ARG"
if [[ "$LCOV_PATH" != /* ]]; then
    LCOV_PATH="$REPO_ROOT/$LCOV_PATH"
fi

python3 - <<'PY' "$TEST_SPEC" "$LCOV_PATH" "$REPO_ROOT" "$JSON_MODE" "$ALLOW_MISSING_LCOV"
import json
import re
from collections import defaultdict
import sys
from pathlib import Path


def parse_sections(markdown: str) -> dict:
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


def is_separator_row(line: str) -> bool:
    return bool(re.fullmatch(r"\|?[-:|\s]+\|?", line.strip()))


def parse_table_rows(section_text: str):
    lines = [ln.strip() for ln in section_text.splitlines() if ln.strip().startswith("|")]
    if len(lines) < 2:
        return [], [], ["Test Component Inventory table is missing or incomplete"]

    header = [c.strip() for c in lines[0].strip("|").split("|")]
    rows = []
    errors = []

    for line in lines[1:]:
        if is_separator_row(line):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < len(header):
            cells += ["" for _ in range(len(header) - len(cells))]
        row = {header[i]: cells[i] if i < len(cells) else "" for i in range(len(header))}
        rows.append(row)

    if not rows:
        errors.append("Test Component Inventory must include at least one data row")

    return header, rows, errors


def parse_target_percent(raw: str):
    token = raw.strip().strip("`")
    match = re.search(r"(\d+(?:\.\d+)?)\s*%?$", token)
    if not match:
        return None
    value = float(match.group(1))
    if value < 0 or value > 100:
        return None
    return value


def sanitize_path(raw: str) -> str:
    value = raw.strip()
    if not value:
        return ""

    link_match = re.match(r"^\s*\[[^\]]*\]\(([^)]+)\)\s*$", value)
    if link_match:
        value = link_match.group(1).strip()

    value = value.strip("`\"'<>[]()")
    value = re.sub(r"\s+", " ", value)
    if value.startswith("file://"):
        value = value[len("file://"):]
    value = value.replace("\\", "/")
    return value


def normalize_path(raw: str, repo_root: Path) -> str:
    value = sanitize_path(raw)
    if not value:
        return ""

    path_obj = Path(value)
    if path_obj.is_absolute():
        try:
            return path_obj.resolve().relative_to(repo_root.resolve()).as_posix()
        except Exception:
            return path_obj.as_posix()

    return path_obj.as_posix().lstrip("./")


def build_lookup_variants(raw: str, repo_root: Path):
    path_obj = Path(raw)
    posix_path = path_obj.as_posix()
    variants = [posix_path]

    cleaned = posix_path.lstrip("./")
    if cleaned and cleaned != posix_path:
        variants.append(cleaned)

    if path_obj.name and path_obj.name not in variants:
        variants.append(path_obj.name)

    if path_obj.is_absolute():
        try:
            variants.append(path_obj.resolve().relative_to(repo_root.resolve()).as_posix())
        except Exception:
            pass

    deduped = []
    for candidate in variants:
        if candidate and candidate not in deduped:
            deduped.append(candidate)
    return deduped


def parse_coverage_anchors(lcov_path: Path, repo_root: Path):
    coverage = {}
    alias_map = defaultdict(list)
    current = None
    covered = 0
    total = 0

    def commit():
        nonlocal current, covered, total
        if current is None:
            return
        bucket = coverage.setdefault(current, {"covered": 0, "total": 0})
        bucket["covered"] += covered
        bucket["total"] += total

    for raw in lcov_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if line.startswith("SF:"):
            commit()
            current = normalize_path(line[3:], repo_root)
            covered = 0
            total = 0
            continue
        if line.startswith("DA:") and current:
            payload = line[3:]
            parts = payload.split(",", 1)
            if len(parts) != 2:
                continue
            total += 1
            try:
                hits = int(parts[1])
            except ValueError:
                hits = 0
            if hits > 0:
                covered += 1
            continue
        if line == "end_of_record":
            commit()
            current = None
            covered = 0
            total = 0

    commit()

    for stats in coverage.values():
        total_lines = stats["total"]
        stats["percent"] = 0.0 if total_lines == 0 else (stats["covered"] / total_lines) * 100.0

    for source_file in coverage:
        for alias in build_lookup_variants(source_file, repo_root):
            alias_map[alias].append(source_file)

    return coverage, alias_map


def resolve_coverage_entry(source_file: str, coverage: dict, alias_map: dict, repo_root: Path):
    candidates = build_lookup_variants(source_file, repo_root)
    for alias in candidates:
        if alias in coverage:
            return coverage[alias], f"direct:{alias}"

    basename = Path(source_file).name
    by_name = alias_map.get(basename, [])

    normalized_source = source_file.lstrip("./")
    tail_matches = [
        item
        for item in coverage
        if item == normalized_source or item.endswith(f"/{normalized_source}")
    ]
    if len(tail_matches) == 1:
        return coverage[tail_matches[0]], "tail:unique"
    if len(tail_matches) > 1:
        return {
            "status": "ambiguous",
            "options": sorted(set(tail_matches)),
            "reason": "tail_ambiguous",
        }, "ambiguous"

    if len(by_name) == 1:
        return coverage[by_name[0]], "basename:unique"

    if len(by_name) > 1:
        source_norm = normalize_path(source_file, repo_root)
        normalized = source_norm
        tail_matches = [item for item in by_name if item.endswith(f"/{normalized}")]

        if len(tail_matches) == 1:
            return coverage[tail_matches[0]], "tail:unique"
        if normalized in by_name:
            return coverage[normalized], "normalized"
        if tail_matches:
            return {"status": "ambiguous", "options": sorted(set(by_name)), "reason": "basename_ambiguous"}, "ambiguous"

    if len(by_name) > 0:
        return {"status": "ambiguous", "options": sorted(set(by_name)), "reason": "basename_ambiguous"}, "ambiguous"

    return None, "missing"


test_spec_path = Path(sys.argv[1])
lcov_path = Path(sys.argv[2])
repo_root = Path(sys.argv[3]).resolve()
json_mode = sys.argv[4] == "true"
allow_missing_lcov = sys.argv[5] == "true"

sections = parse_sections(test_spec_path.read_text(encoding="utf-8").replace("\r\n", "\n"))
errors = []

inventory_key = "## Test Component Inventory"
if inventory_key not in sections:
    errors.append("test-spec.md is missing ## Test Component Inventory section")
    inventory_section = ""
else:
    inventory_section = sections[inventory_key]

header, rows, table_errors = parse_table_rows(inventory_section)
errors.extend(table_errors)

required_columns = ["Test ID", "Source File", "Coverage Target"]
for col in required_columns:
    if header and col not in header:
        errors.append(f"Test Component Inventory missing required column: {col}")

parsed_targets = []
if not errors:
    for row in rows:
        test_id = row.get("Test ID", "").strip() or "(unknown)"
        source_file = normalize_path(row.get("Source File", ""), repo_root)
        target_raw = row.get("Coverage Target", "")
        target = parse_target_percent(target_raw)

        if not source_file:
            errors.append(f"{test_id}: Source File is empty")
            continue
        if target is None:
            errors.append(
                f"{test_id}: invalid Coverage Target '{target_raw}' (expected percent like 85% or 85)"
            )
            continue

        parsed_targets.append(
            {
                "test_id": test_id,
                "source_file": source_file,
                "target": target,
                "target_raw": target_raw,
            }
        )

missing_lcov = not lcov_path.exists()
if missing_lcov and allow_missing_lcov:
    warnings = [f"Skipping coverage gate: lcov file not found: {lcov_path}"]
    skip_ok = not errors
    result = {
        "ok": skip_ok,
        "skipped": True,
        "skip_reason": "lcov_missing",
        "test_spec": str(test_spec_path),
        "lcov": str(lcov_path),
        "targets": len(parsed_targets),
        "errors": errors,
        "failures": [],
        "warnings": warnings,
    }
    if json_mode:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(f"WARN: {warnings[0]}")
        if errors:
            print("ERROR: coverage target gate failed before skip handling:", file=sys.stderr)
            for error in errors:
                print(f"  - {error}", file=sys.stderr)
        else:
            print("INFO: Coverage check skipped (run after `flutter test --coverage`).")
    if not skip_ok:
        raise SystemExit(1)
    # do not fail because this command is used in early execution phases
    raise SystemExit(0)
elif missing_lcov:
    errors.append(f"lcov file not found: {lcov_path}")
    parsed_targets = []
    failures = []
    result = {
        "ok": False,
        "skipped": False,
        "skip_reason": None,
        "test_spec": str(test_spec_path),
        "lcov": str(lcov_path),
        "targets": len(parsed_targets),
        "errors": errors,
        "failures": [],
    }
    if json_mode:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print("ERROR: coverage target gate failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)
coverage, alias_map = parse_coverage_anchors(lcov_path, repo_root) if not errors else ({}, {})
failures = []
warnings = []

for item in parsed_targets:
    stats, match_reason = resolve_coverage_entry(
        item["source_file"],
        coverage,
        alias_map,
        repo_root,
    )

    if isinstance(stats, dict) and stats.get("status") == "ambiguous":
        failures.append(
            {
                "test_id": item["test_id"],
                "source_file": item["source_file"],
                "target": item["target"],
                "actual": None,
                "reason": "ambiguous_in_lcov",
                "candidates": stats.get("options", []),
            }
        )
        continue

    if not stats:
        failures.append(
            {
                "test_id": item["test_id"],
                "source_file": item["source_file"],
                "target": item["target"],
                "actual": None,
                "reason": "missing_in_lcov",
            }
        )
        continue

    if match_reason != "direct:" + item["source_file"]:
        warnings.append(
            {
                "test_id": item["test_id"],
                "source_file": item["source_file"],
                "matched_with": match_reason,
            }
        )

    actual = float(stats.get("percent", 0.0))
    if actual + 1e-9 < item["target"]:
        failures.append(
            {
                "test_id": item["test_id"],
                "source_file": item["source_file"],
                "target": item["target"],
                "actual": round(actual, 2),
                "reason": "below_target",
            }
        )

ok = not errors and not failures

result = {
    "ok": ok,
    "skipped": False,
    "test_spec": str(test_spec_path),
    "lcov": str(lcov_path),
    "targets": len(parsed_targets),
    "errors": errors,
    "failures": failures,
    "warnings": warnings,
}

if json_mode:
    print(json.dumps(result, ensure_ascii=False))
else:
    if ok:
        print(
            f"OK: coverage targets satisfied ({len(parsed_targets)} target(s), lcov={lcov_path})"
        )
    else:
        print("ERROR: coverage target gate failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        for failure in failures:
            if failure["reason"] == "missing_in_lcov":
                print(
                    f"  - {failure['test_id']}: missing coverage entry for {failure['source_file']}",
                    file=sys.stderr,
                )
            elif failure["reason"] == "ambiguous_in_lcov":
                print(
                    f"  - {failure['test_id']}: ambiguous coverage match for {failure['source_file']} -> {', '.join(failure['candidates'])}",
                    file=sys.stderr,
                )
            else:
                print(
                    f"  - {failure['test_id']}: {failure['source_file']} coverage {failure['actual']}% < target {failure['target']}%",
                    file=sys.stderr,
                )
        for warning in warnings:
            print(
                f"WARN: {warning['test_id']} source matched via {warning['matched_with']} ({warning['source_file']})",
                file=sys.stderr,
            )

if not ok:
    raise SystemExit(1)
PY
