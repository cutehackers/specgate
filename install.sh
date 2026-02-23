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
CLEAN=0
UNINSTALL=0
UPDATE=0
VERSION="main"
REPO_URL="${REPO_URL:-https://github.com/cutehackers/specgate}"
SCRIPT_SOURCE_DIR=""
TMP_DIR=""
AGENT_SELECTION="all"
CODEX_TARGET_MODE="project"

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
)
CODEX_SKILL_ASSETS=(
  ".codex/skills/specgate"
)
OPENCODE_ASSETS=(
  ".opencode/command"
)
ASSETS=()
SELECTED_AGENTS=()
SELECTED_CODEX=0
STATUSLINE_PATH=".claude/hooks/statusline.js"
SPECGATE_STATUSLINE_MARKER="# @specgate-managed:statusline"

print_usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Install SpecGate into a consumer project.

Options:
  --prefix <path>     Install target directory (default: .)
  --dry-run           Show planned file operations without writing files
  --force             Overwrite existing files/directories
  --update            Update existing SpecGate files in-place (no backup; skips unchanged)
  --clean             Remove selected SpecGate assets before install
  --uninstall         Remove SpecGate files from the target directory
  --version <name>    Ref to install when downloading (default: main)
  --preset <name>     Predefined install profile. Supported: claude, opencode, codex, codex-home, all
  --ai <list>         Agents to install (comma-separated). Supported: all, claude, codex, opencode
  --agent <list>      Alias for --ai
  --codex-target <project|home>  Where to install Codex Agent Skills when --ai includes codex (default: project)
  -h, --help          Show this help

Examples:
  curl -fsSL https://raw.githubusercontent.com/cutehackers/specgate/main/install.sh \
    | bash -s -- --preset claude --prefix .
  bash install.sh --preset claude --prefix .
  bash install.sh --update --preset claude --prefix .
  bash install.sh --uninstall --preset claude --prefix .
USAGE
}

apply_preset() {
  local preset="${1:-}"

  if [[ -z "${preset//[[:space:]]/}" ]]; then
    echo "Missing value for --preset" >&2
    print_usage
    exit 1
  fi

  case "$preset" in
    claude)
      AGENT_SELECTION="claude"
      CODEX_TARGET_MODE="project"
      ;;
    opencode)
      AGENT_SELECTION="opencode"
      CODEX_TARGET_MODE="project"
      ;;
    codex|codex-project)
      AGENT_SELECTION="codex"
      CODEX_TARGET_MODE="project"
      ;;
    codex-home)
      AGENT_SELECTION="codex"
      CODEX_TARGET_MODE="home"
      ;;
    all)
      AGENT_SELECTION="all"
      CODEX_TARGET_MODE="project"
      ;;
    *)
      echo "Unsupported --preset value: $preset" >&2
      echo "Supported values: claude, opencode, codex, codex-home, all" >&2
      exit 1
      ;;
  esac

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
    --preset)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --preset"
        print_usage
        exit 1
      fi
      apply_preset "${2:-}"
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
    --codex-target)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --codex-target"
        print_usage
        exit 1
      fi
      CODEX_TARGET_MODE="${2:-}"
      if [[ "$CODEX_TARGET_MODE" != "project" && "$CODEX_TARGET_MODE" != "home" ]]; then
        echo "Unsupported --codex-target value: $CODEX_TARGET_MODE" >&2
        echo "Supported values: project, home" >&2
        exit 1
      fi
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --update)
      UPDATE=1
      shift
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --uninstall)
      UNINSTALL=1
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
  ASSETS=()

  ASSETS+=("${COMMON_ASSETS[@]}")

  local agent
  local has_codex=0
  for agent in "${selected[@]}"; do
    case "$agent" in
      claude)
        ASSETS+=("${CLAUDE_ASSETS[@]}")
        ;;
      codex)
        has_codex=1
        if ((${#CODEX_ASSETS[@]} > 0)); then
          ASSETS+=("${CODEX_ASSETS[@]}")
        fi
        if [[ "$CODEX_TARGET_MODE" == "project" ]]; then
          ASSETS+=("${CODEX_SKILL_ASSETS[@]}")
        fi
        ;;
      opencode)
        ASSETS+=("${OPENCODE_ASSETS[@]}")
        ;;
    esac
  done

  SELECTED_CODEX=$has_codex
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

is_specgate_managed_statusline() {
  local target_path="$1"
  [[ -f "$target_path" ]] && {
    grep -qF "${SPECGATE_STATUSLINE_MARKER}" "$target_path" || \
    grep -qF "Claude Code Statusline - SpecGate Edition" "$target_path"
  }
}

cleanup_tmp() {
  if [[ -n "${TMP_DIR}" ]] && [[ -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup_tmp EXIT

is_empty_dir() {
  local dir_path="$1"
  if [[ ! -d "$dir_path" ]]; then
    return 1
  fi
  local first_entry
  first_entry="$(find "$dir_path" -mindepth 1 -print -quit 2>/dev/null || true)"
  [[ -z "$first_entry" ]]
}

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

if [[ "${#SELECTED_AGENTS[@]}" -eq "${#KNOWN_AGENTS[@]}" ]]; then
  SELECTED_AGENTS_LABEL="all"
else
  SELECTED_AGENTS_LABEL="${SELECTED_AGENTS[*]}"
fi

build_assets "${SELECTED_AGENTS[@]}"

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

mkdir -p "$PREFIX"
TARGET_DIR="$(cd "$PREFIX" && pwd)"

remove_item() {
  local rel_path="$1"
  local target_path="$TARGET_DIR/$rel_path"
  local parent_dir

  if [[ ! -e "$target_path" ]]; then
    echo "SKIP: $rel_path does not exist"
    return 0
  fi

  if [[ "$rel_path" == "$STATUSLINE_PATH" ]] && ! is_specgate_managed_statusline "$target_path"; then
    echo "SKIP: $rel_path is user-managed"
    return 0
  fi

  if (( DRY_RUN == 1 )); then
    echo "DRY-RUN: would remove $rel_path"
    return 0
  fi

  rm -rf "$target_path"
  echo "Removed: $rel_path"

  parent_dir="$(dirname "$target_path")"
  while [[ "$parent_dir" != "$TARGET_DIR" && "$parent_dir" != "/" ]]; do
    if rmdir "$parent_dir" 2>/dev/null; then
      parent_dir="$(dirname "$parent_dir")"
    else
      break
    fi
  done
}

if (( UNINSTALL == 1 )); then
  if (( UPDATE == 1 )); then
    echo "Cannot use --update with --uninstall"
    exit 1
  fi

  echo "Uninstalling SpecGate from $TARGET_DIR"
  echo "Target agents: ${SELECTED_AGENTS_LABEL}"
  for asset in "${ASSETS[@]}"; do
    remove_item "$asset"
  done
  if (( SELECTED_CODEX == 1 )); then
    if [[ "$CODEX_TARGET_MODE" == "home" ]]; then
      if [[ -z "${HOME:-}" ]]; then
        echo "HOME is required when --codex-target home is used." >&2
        exit 1
      fi
      previous_target_dir="${TARGET_DIR}"
      TARGET_DIR="${HOME}"
      for asset in "${CODEX_SKILL_ASSETS[@]}"; do
        remove_item "$asset"
      done
      TARGET_DIR="${previous_target_dir}"
    fi
  fi

  echo "Uninstallation completed."
  exit 0
fi

if (( UPDATE == 1 && CLEAN == 1 )); then
  echo "Cannot use --update with --clean"
  exit 1
fi

if (( UPDATE == 1 && FORCE == 1 )); then
  echo "Cannot use --update with --force"
  exit 1
fi

SCRIPT_SOURCE_DIR="$(resolve_script_source)"

if (( CLEAN == 1 )); then
  echo "Cleaning selected SpecGate assets in $TARGET_DIR"
  for asset in "${ASSETS[@]}"; do
    remove_item "$asset"
  done
  if (( SELECTED_CODEX == 1 )) && [[ "$CODEX_TARGET_MODE" == "home" ]]; then
    if [[ -z "${HOME:-}" ]]; then
      echo "HOME is required when --codex-target home is used." >&2
      exit 1
    fi
    previous_target_dir="${TARGET_DIR}"
    TARGET_DIR="${HOME}"
    for asset in "${CODEX_SKILL_ASSETS[@]}"; do
      remove_item "$asset"
    done
    TARGET_DIR="${previous_target_dir}"
  fi
fi

copy_item() {
  local rel_path="$1"
  local source_path="$SCRIPT_SOURCE_DIR/$rel_path"
  local target_path="$TARGET_DIR/$rel_path"

  if [[ ! -e "$source_path" ]]; then
    echo "SKIP: missing source $rel_path"
    return 0
  fi

  if [[ "$rel_path" == "$STATUSLINE_PATH" ]] && [[ -f "$target_path" ]] && ! is_specgate_managed_statusline "$target_path"; then
    echo "SKIP: $rel_path is user-managed"
    return 0
  fi

  if [[ -e "$target_path" ]] && ! (( CLEAN == 1 && DRY_RUN == 1 )); then
    if (( FORCE == 0 )); then
      if is_empty_dir "$target_path" && [[ -d "$source_path" ]]; then
        rm -rf "$target_path"
      else
        echo "SKIP: $rel_path already exists (use --force)"
        return 0
      fi
    else
      if (( DRY_RUN == 1 )); then
        echo "DRY-RUN: would replace existing $rel_path"
      else
        rm -rf "$target_path"
      fi
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

asset_has_changes() {
  local source_path="$1"
  local target_path="$2"

  if [[ -L "$source_path" ]]; then
    if [[ ! -L "$target_path" ]]; then
      return 1
    fi
    if [[ "$(readlink "$source_path")" == "$(readlink "$target_path" 2>/dev/null)" ]]; then
      return 0
    fi
    return 1
  fi

  if [[ -f "$source_path" ]]; then
    if [[ ! -f "$target_path" ]]; then
      return 1
    fi
    cmp -s "$source_path" "$target_path"
    if (( $? == 0 )); then
      return 0
    fi
    return 1
  fi

  return 1
}

update_item() {
  local rel_path="$1"
  local source_path="$SCRIPT_SOURCE_DIR/$rel_path"
  local target_path="$TARGET_DIR/$rel_path"
  local updated_files=0
  local src_file
  local rel
  local target_file

  if [[ ! -e "$source_path" ]]; then
    echo "SKIP: missing source $rel_path"
    return 0
  fi

  if [[ "$rel_path" == "$STATUSLINE_PATH" ]] && [[ -f "$target_path" ]] && ! is_specgate_managed_statusline "$target_path"; then
    echo "SKIP: $rel_path is user-managed"
    return 0
  fi

  if [[ -d "$source_path" ]]; then
    if [[ -d "$target_path" ]]; then
      while IFS= read -r -d '' src_file; do
        rel="${src_file#${source_path}/}"
        target_file="$target_path/$rel"
        if ! asset_has_changes "$src_file" "$target_file"; then
          if (( DRY_RUN == 1 )); then
            echo "DRY-RUN: would update $rel_path/$rel"
          else
            mkdir -p "$(dirname "$target_file")"
            if [[ -e "$target_file" ]]; then
              rm -rf "$target_file"
            fi
            cp -a "$src_file" "$target_file"
          fi
          ((updated_files += 1))
        fi
      done < <(find "$source_path" \( -type f -o -type l \) -print0)

      if (( DRY_RUN == 1 )); then
        if (( updated_files == 0 )); then
          echo "DRY-RUN: $rel_path already up to date"
        else
          echo "DRY-RUN: would update $rel_path ($updated_files files)"
        fi
        return 0
      fi

      if (( updated_files == 0 )); then
        echo "SKIP: $rel_path is already up to date"
      else
        echo "Updated: $rel_path ($updated_files files)"
      fi
      return 0
    fi

    if (( DRY_RUN == 1 )); then
      echo "DRY-RUN: would install $rel_path"
      return 0
    fi
    if [[ -e "$target_path" ]]; then
      rm -rf "$target_path"
    fi
    mkdir -p "$(dirname "$target_path")"
    cp -a "$source_path" "$target_path"
    echo "Installed: $rel_path"
    return 0
  fi

  if ! asset_has_changes "$source_path" "$target_path"; then
    if (( DRY_RUN == 1 )); then
      echo "DRY-RUN: would update $rel_path"
      return 0
    fi
    if [[ -e "$target_path" ]]; then
      rm -rf "$target_path"
    fi
    mkdir -p "$(dirname "$target_path")"
    cp -a "$source_path" "$target_path"
    echo "Updated: $rel_path"
    return 0
  fi

  if (( DRY_RUN == 1 )); then
    echo "DRY-RUN: $rel_path is already up to date"
    return 0
  fi

  echo "SKIP: $rel_path is already up to date"
}

if (( UPDATE == 1 )); then
  echo "Updating SpecGate in $TARGET_DIR"
else
  echo "Installing SpecGate into $TARGET_DIR"
fi
echo "Target agents: ${SELECTED_AGENTS_LABEL}"
for asset in "${ASSETS[@]}"; do
  if (( UPDATE == 1 )); then
    update_item "$asset"
  else
    copy_item "$asset"
  fi
done
if (( SELECTED_CODEX == 1 )) && [[ "$CODEX_TARGET_MODE" == "home" ]]; then
  if [[ -z "${HOME:-}" ]]; then
    echo "HOME is required when --codex-target home is used." >&2
    exit 1
  fi
  previous_target_dir="${TARGET_DIR}"
  TARGET_DIR="${HOME}"
  for asset in "${CODEX_SKILL_ASSETS[@]}"; do
    if (( UPDATE == 1 )); then
      update_item "$asset"
    else
      copy_item "$asset"
    fi
  done
  TARGET_DIR="${previous_target_dir}"
fi

echo "Installation completed."
