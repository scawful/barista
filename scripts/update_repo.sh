#!/usr/bin/env bash
# update_repo.sh - Update this repo and optionally deploy to ~/.config/sketchybar.
#
# Usage:
#   ./scripts/update_repo.sh [--target <ref>] [--config-repo <path>] [--no-deploy] [--skip-restart]
#
# Env:
#   BARISTA_REMOTE        Git remote (default: origin)
#   BARISTA_BRANCH        Branch to track (default: main)
#   BARISTA_TARGET        Ref/commit to checkout (default: ${BARISTA_REMOTE}/${BARISTA_BRANCH})
#   BARISTA_CONFIG_REPO   Optional barista_config repo path
#   BARISTA_CONFIG_DIR    Deploy destination (default: ~/.config/sketchybar)
#   BARISTA_SKIP_DEPLOY   Set to 1 to skip deploy
#   BARISTA_SKIP_RESTART  Set to 1 to skip restarts in deploy

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

REMOTE="${BARISTA_REMOTE:-origin}"
BRANCH="${BARISTA_BRANCH:-main}"
TARGET="${BARISTA_TARGET:-${REMOTE}/${BRANCH}}"
CONFIG_REPO="${BARISTA_CONFIG_REPO:-$ROOT/../barista_config}"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
SKIP_DEPLOY="${BARISTA_SKIP_DEPLOY:-0}"
SKIP_RESTART="${BARISTA_SKIP_RESTART:-0}"

usage() {
  cat <<EOF
Usage: $0 [--target <ref>] [--config-repo <path>] [--no-deploy] [--skip-restart]

Options:
  --target <ref>       Git ref/commit to update to (default: ${REMOTE}/${BRANCH})
  --config-repo <path> Optional barista_config repo to update
  --no-deploy          Skip deploy step
  --skip-restart       Pass --no-restart to deploy
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --config-repo)
      CONFIG_REPO="$2"
      shift 2
      ;;
    --no-deploy)
      SKIP_DEPLOY=1
      shift
      ;;
    --skip-restart)
      SKIP_RESTART=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

cd "$ROOT"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree is dirty. Commit or stash changes before updating." >&2
  exit 1
fi

echo "Updating Barista repo..."
echo "  Remote: $REMOTE"
echo "  Target: $TARGET"

git fetch "$REMOTE"

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git checkout "$BRANCH"
fi

git rev-parse --verify "$TARGET" >/dev/null

if [[ "$TARGET" == "$REMOTE/$BRANCH" ]] && git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git merge --ff-only "$TARGET"
else
  git checkout "$TARGET"
  echo "Checked out $TARGET (detached head)."
fi

if [[ -d "$CONFIG_REPO/.git" ]]; then
  echo "Updating barista_config at $CONFIG_REPO..."
  git -C "$CONFIG_REPO" fetch origin
  git -C "$CONFIG_REPO" pull --ff-only
else
  echo "Skipping barista_config update (no git repo at $CONFIG_REPO)."
fi

if [[ "$SKIP_DEPLOY" == "1" ]]; then
  echo "Skipping deploy step."
  exit 0
fi

DEPLOY_ARGS=()
if [[ "$SKIP_RESTART" == "1" ]]; then
  DEPLOY_ARGS+=(--no-restart)
fi

BARISTA_CONFIG_DIR="$CONFIG_DIR" "$ROOT/scripts/deploy.sh" "${DEPLOY_ARGS[@]}"
