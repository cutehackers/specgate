#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH=""
DRY_RUN=0
APPLY=0
INSTALL_PREFIX=""
REMOTE="origin"

print_usage() {
  cat <<'USAGE'
Usage: sync.sh [options]

Check remote update status and optionally apply updates.

Options:
  --branch <name>          Local branch to compare against (default: current branch)
  --remote <name>          Git remote (default: origin)
  --dry-run                Show pending updates only
  --apply                  Apply update after checks
  --install-prefix <path>   Install updated engine into consumer path after apply
  -h, --help               Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --remote)
      REMOTE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --install-prefix)
      INSTALL_PREFIX="${2:-}"
      shift 2
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

if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
  echo "sync.sh requires this repo to be a git worktree"
  exit 1
fi

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git -C "$SCRIPT_DIR" symbolic-ref --short HEAD 2>/dev/null || echo main)"
fi

REMOTE_REF="$REMOTE/$BRANCH"

git -C "$SCRIPT_DIR" fetch --all --prune --tags

if ! git -C "$SCRIPT_DIR" show-ref --verify --quiet "refs/remotes/$REMOTE_REF"; then
  echo "Remote ref not found: $REMOTE_REF"
  exit 1
fi

local_sha="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
remote_sha="$(git -C "$SCRIPT_DIR" rev-parse --short "$REMOTE_REF")"
ahead="$(git -C "$SCRIPT_DIR" rev-list --count "$REMOTE_REF..HEAD")"
behind="$(git -C "$SCRIPT_DIR" rev-list --count "HEAD..$REMOTE_REF")"

cat <<STATUS
Current branch : $BRANCH
Local HEAD     : $local_sha
Remote HEAD    : $remote_sha
Ahead         : $ahead
Behind        : $behind
STATUS

if [[ "$behind" == "0" ]]; then
  echo "No updates available from $REMOTE_REF"
  exit 0
fi

echo "Preview updates (latest 10):"
git -C "$SCRIPT_DIR" log --oneline "HEAD..$REMOTE_REF" --max-count=10

echo "Changes exist: $behind commit(s) behind remote"

if (( DRY_RUN == 1 )); then
  echo "Dry run only. Use --apply to pull and refresh pointers."
  exit 0
fi

if (( APPLY == 0 )); then
  echo "Run with --apply to synchronize now"
  exit 0
fi

if (( ahead != 0 )); then
  echo "Local branch has $ahead commit(s) not on $REMOTE_REF"
  echo "Sync is configured for fast-forward-only pull. Reconcile history first."
  exit 1
fi

git -C "$SCRIPT_DIR" pull --ff-only "$REMOTE" "$BRANCH"

echo "Engine updated successfully."

if [[ -n "$INSTALL_PREFIX" ]]; then
  "$SCRIPT_DIR/install.sh" --prefix "$INSTALL_PREFIX" --force
  echo "Installed updated engine into $INSTALL_PREFIX"
fi

