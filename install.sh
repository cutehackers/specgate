#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="."
DRY_RUN=0
FORCE=0

print_usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Install SpecGate into a consumer project.

Options:
  --prefix <path>    Install target directory (default: .)
  --dry-run          Show planned file operations without writing files
  --force            Overwrite existing files/directories
  -h, --help         Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
case "$1" in
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      print_usage
      exit 1
      ;;
  esac
done

mkdir -p "$PREFIX"
TARGET_DIR="$(cd "$PREFIX" && pwd)"

ASSETS=(
  ".specify"
  ".claude/commands/specgate"
  ".claude/hooks/statusline.js"
  ".opencode/command"
  ".codex/commands/specgate"
  "docs/SPECGATE.md"
)

copy_item() {
  local rel_path="$1"
  local source_path="$SCRIPT_DIR/$rel_path"
  local target_path="$TARGET_DIR/$rel_path"
  local ts

  if [[ ! -e "$source_path" ]]; then
    echo "SKIP: missing source $rel_path"
    return 0
  fi

  if [[ -e "$target_path" ]]; then
    if (( FORCE == 0 )); then
      echo "SKIP: $rel_path already exists (use --force)"
      return 0
    fi

    ts="$(date +%Y%m%d-%H%M%S)"
    if (( DRY_RUN == 1 )); then
      echo "DRY-RUN: would backup existing $rel_path -> $rel_path.backup-$ts"
    else
      mv "$target_path" "$target_path.backup-$ts"
      echo "Backed up existing $rel_path"
    fi
  fi

  if (( DRY_RUN == 1 )); then
    echo "DRY-RUN: would install $rel_path"
    return 0
  fi

  mkdir -p "$(dirname "$target_path")"
  cp -a "$source_path" "$target_path"
  echo "Installed: $rel_path"
}

echo "Installing SpecGate into $TARGET_DIR"
for asset in "${ASSETS[@]}"; do
  copy_item "$asset"
done

echo "Installation completed."
