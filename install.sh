#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=""
SCRIPT_PATH=""
if [[ -n "${0:-}" && -f "${0}" && "${0}" != "bash" ]]; then
  SCRIPT_PATH="${0}"
fi
if [[ -n "${SCRIPT_PATH}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
fi
PREFIX="."
DRY_RUN=0
FORCE=0
VERSION="main"
REPO_URL="${REPO_URL:-https://github.com/cutehackers/specgate}"
SCRIPT_SOURCE_DIR=""
TMP_DIR=""
AGENT_SELECTION="all"

KNOWN_AGENTS=(claude codex opencode)
COMMON_ASSETS=(
  ".specify"
  "docs/SPECGATE.md"
)
CLAUDE_ASSETS=(
  ".claude/commands/specgate"
  ".claude/hooks/statusline.js"
)
CODEX_ASSETS=(
  ".codex/commands/specgate"
)
OPENCODE_ASSETS=(
  ".opencode/command"
)
ASSETS=()
SELECTED_AGENTS=()

print_usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Install SpecGate into a consumer project.

Options:
  --prefix <path>    Install target directory (default: .)
  --dry-run          Show planned file operations without writing files
  --force            Overwrite existing files/directories
  --version <name>    Ref to install when downloading (default: main)
  --ai <list>        Agents to install (comma-separated). Supported: all, claude, codex, opencode
  --agent <list>     Alias for --ai
  -h, --help         Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
case "$1" in
    --prefix)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --prefix"
        print_usage
        exit 1
      fi
      PREFIX="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --version)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --version"
        print_usage
        exit 1
      fi
      VERSION="${2:-}"
      shift 2
      ;;
    --ai|--agent)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for $1"
        print_usage
        exit 1
      fi
      AGENT_SELECTION="${2:-}"
      shift 2
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

normalize_ai_selection() {
  local input="${1:-}"
  local -a requested=()
  local normalized=""
  local target

  if [[ -z "${input//[[:space:]]/}" ]]; then
    input="all"
  fi

  IFS=',' read -r -a requested <<< "$input"

  for target in "${requested[@]}"; do
    target="${target//[[:space:]]/}"

    case "$target" in
      "")
        continue
        ;;
      all)
        echo "claude codex opencode"
        return 0
        ;;
      claude|codex|opencode)
        if [[ " $normalized " != *" $target "* ]]; then
          if [[ -n "$normalized" ]]; then
            normalized="$normalized $target"
          else
            normalized="$target"
          fi
        fi
        ;;
      *)
        echo "Unsupported --ai/--agent value: $target" >&2
        echo "Supported values: all, claude, codex, opencode" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$normalized" ]]; then
    normalized="claude codex opencode"
  fi

  printf '%s ' "$normalized"
}

build_assets() {
  local -a selected=("$@")
  ASSETS=("${COMMON_ASSETS[@]}")

  local agent
  for agent in "${selected[@]}"; do
    case "$agent" in
      claude)
        ASSETS+=("${CLAUDE_ASSETS[@]}")
        ;;
      codex)
        ASSETS+=("${CODEX_ASSETS[@]}")
        ;;
      opencode)
        ASSETS+=("${OPENCODE_ASSETS[@]}")
        ;;
    esac
  done
}

has_local_assets() {
  local base_dir="$1"
  local rel_path
  shift

  for rel_path in "$@"; do
    if [[ ! -e "$base_dir/$rel_path" ]]; then
      return 1
    fi
  done

  return 0
}

cleanup_tmp() {
  if [[ -n "${TMP_DIR}" ]] && [[ -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup_tmp EXIT

resolve_remote_archive() {
  local candidate
  local archive_url
  local candidates=( "heads/${VERSION}" "tags/${VERSION}" )

  for candidate in "${candidates[@]}"; do
    archive_url="${REPO_URL}/archive/refs/${candidate}.tar.gz"
    if curl -fsI "${archive_url}" >/dev/null 2>&1; then
      echo "${archive_url}"
      return 0
    fi
  done

  return 1
}

normalize_output="$(normalize_ai_selection "$AGENT_SELECTION")"
read -r -a SELECTED_AGENTS <<< "$normalize_output"
build_assets "${SELECTED_AGENTS[@]}"

if [[ "${#SELECTED_AGENTS[@]}" -eq "${#KNOWN_AGENTS[@]}" ]]; then
  SELECTED_AGENTS_LABEL="all"
else
  SELECTED_AGENTS_LABEL="${SELECTED_AGENTS[*]}"
fi

resolve_script_source() {
  if [[ -n "${SCRIPT_DIR}" ]] && has_local_assets "${SCRIPT_DIR}" "${ASSETS[@]}"; then
    echo "${SCRIPT_DIR}"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    echo "Remote installation requires curl and tar." >&2
    exit 1
  fi

  local archive
  local extracted_dir
  archive="$(resolve_remote_archive)" || {
    echo "Could not download reference '${VERSION}'. Check --version value or repo access." >&2
    exit 1
  }

  TMP_DIR="$(mktemp -d)"
  curl -fsSL "${archive}" | tar -xz -C "${TMP_DIR}"
  extracted_dir="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d -name 'specgate-*' -print -quit)"

  if [[ -z "${extracted_dir}" ]] || [[ ! -d "${extracted_dir}" ]]; then
    echo "Failed to extract installer archive." >&2
    exit 1
  fi

  if ! has_local_assets "${extracted_dir}" "${ASSETS[@]}"; then
    echo "Downloaded archive does not contain expected SpecGate payload." >&2
    exit 1
  fi

  echo "${extracted_dir}"
}

SCRIPT_SOURCE_DIR="$(resolve_script_source)"

mkdir -p "$PREFIX"
TARGET_DIR="$(cd "$PREFIX" && pwd)"

copy_item() {
  local rel_path="$1"
  local source_path="$SCRIPT_SOURCE_DIR/$rel_path"
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
echo "Target agents: ${SELECTED_AGENTS_LABEL}"
for asset in "${ASSETS[@]}"; do
  copy_item "$asset"
done

echo "Installation completed."
