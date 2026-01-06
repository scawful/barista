#!/usr/bin/env bash
# deploy.sh - Deploy barista config to ~/.config/sketchybar
#
# Usage:
#   ./scripts/deploy.sh                 # Full deploy with restart
#   ./scripts/deploy.sh --dry-run       # Preview what would be synced
#   ./scripts/deploy.sh --no-restart    # Deploy without restarting sketchybar
#   ./scripts/deploy.sh --no-backup     # Skip runtime backup
#   ./scripts/deploy.sh --note "text"   # Attach a note to the deploy record
#
# Env:
#   BARISTA_SOURCE_DIR  Override repo source (defaults to git root)
#   BARISTA_CONFIG_DIR  Override config destination (defaults to ~/.config/sketchybar)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${BARISTA_SOURCE_DIR:-}"
if [[ -z "$SOURCE" ]]; then
  if command -v git >/dev/null 2>&1; then
    SOURCE="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
fi
if [[ -z "$SOURCE" ]]; then
  SOURCE="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

DEST="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
  echo "Usage: $0 [--dry-run] [--no-restart] [--no-backup] [--note <text>]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  --dry-run     Preview changes without applying" >&2
  echo "  --no-restart  Deploy without restarting sketchybar" >&2
  echo "  --no-backup   Skip backup of runtime state" >&2
  echo "  --note        Attach a note to the deploy record" >&2
  echo "" >&2
  echo "Env overrides:" >&2
  echo "  BARISTA_SOURCE_DIR  Source repo directory" >&2
  echo "  BARISTA_CONFIG_DIR  Destination config directory" >&2
}

# Parse arguments
DRY_RUN=false
NO_RESTART=false
NO_BACKUP=false
NOTE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-restart)
      NO_RESTART=true
      shift
      ;;
    --no-backup)
      NO_BACKUP=true
      shift
      ;;
    --note)
      if [[ $# -lt 2 ]]; then
        echo -e "${RED}Missing value for --note${NC}" >&2
        exit 1
      fi
      NOTE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      usage
      exit 1
      ;;
  esac
done

echo -e "${BLUE}Barista Deploy${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Source: ${GREEN}$SOURCE${NC}"
echo -e "Dest:   ${GREEN}$DEST${NC}"
if [[ -n "$NOTE" ]]; then
  echo -e "Note:   ${GREEN}$NOTE${NC}"
fi
echo ""

# Verify source exists
if [ ! -d "$SOURCE" ]; then
  echo -e "${RED}Error: Source directory not found: $SOURCE${NC}"
  exit 1
fi

# Create destination if needed
if [ ! -d "$DEST" ]; then
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN] Would create: $DEST${NC}"
  else
    echo -e "${YELLOW}Creating destination directory...${NC}"
    mkdir -p "$DEST"
  fi
fi

backup_config() {
  if [ "$NO_BACKUP" = true ]; then
    return 0
  fi
  if [ ! -d "$DEST" ]; then
    return 0
  fi

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_dir="${DEST}.backup.${timestamp}"

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN] Would create backup: $backup_dir${NC}"
    return 0
  fi

  echo -e "${BLUE}Backing up runtime config...${NC}"
  mkdir -p "$backup_dir"

  cp -f "$DEST/state.json" "$backup_dir/" 2>/dev/null || true
  cp -f "$DEST/icon_map.json" "$backup_dir/" 2>/dev/null || true
  cp -f "$DEST/sketchybarrc" "$backup_dir/" 2>/dev/null || true
  cp -r "$DEST/profiles" "$backup_dir/" 2>/dev/null || true
  cp -r "$DEST/themes" "$backup_dir/" 2>/dev/null || true

  shopt -s nullglob
  for file in "$DEST"/*.local.lua; do
    cp -f "$file" "$backup_dir/" 2>/dev/null || true
  done
  for file in "$DEST"/plugins/*.local.sh; do
    cp -f "$file" "$backup_dir/" 2>/dev/null || true
  done
  shopt -u nullglob

  echo -e "${GREEN}Backup created: $backup_dir${NC}"
}

# Build rsync options
RSYNC_OPTS="-av --delete"

# Exclude patterns:
# - .git: version control
# - build/: CMake build artifacts
# - .context/: AFS context (session-specific)
# - *.o, *.dSYM: compiled objects
# - .DS_Store: macOS metadata
# - __pycache__: Python cache
# - state.json/icon_map.json: runtime state
EXCLUDES=(
  ".git"
  "build"
  ".context"
  "cache"
  "*.o"
  "*.dSYM"
  ".DS_Store"
  "__pycache__"
  "*.pyc"
  ".idea"
  ".vscode"
  "state.json"
  "icon_map.json"
  ".barista_version"
  ".barista_deploy.json"
  ".deployments.log"
  "*.local.lua"
  "plugins/*.local.sh"
)

for pattern in "${EXCLUDES[@]}"; do
  RSYNC_OPTS="$RSYNC_OPTS --exclude=$pattern"
done

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}[DRY RUN] Would sync:${NC}"
  rsync $RSYNC_OPTS --dry-run "$SOURCE/" "$DEST/" 2>/dev/null | head -50
  echo ""
  echo -e "${YELLOW}(Showing first 50 files, use without --dry-run to apply)${NC}"
  exit 0
fi

backup_config

# Perform sync
echo -e "${BLUE}Syncing files...${NC}"
rsync $RSYNC_OPTS "$SOURCE/" "$DEST/"

# Seed icon map if missing
if [ ! -f "$DEST/icon_map.json" ] && [ -f "$SOURCE/config/icon_map.json" ]; then
  cp -f "$SOURCE/config/icon_map.json" "$DEST/icon_map.json"
fi

write_deploy_metadata() {
  local meta_file="$DEST/.barista_deploy.json"
  local log_file="$DEST/.deployments.log"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local git_commit="unknown"
  local git_branch="unknown"
  local git_describe="unknown"
  local git_dirty="unknown"

  if command -v git >/dev/null 2>&1; then
    if git -C "$SOURCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git_commit=$(git -C "$SOURCE" rev-parse --short HEAD 2>/dev/null || echo "unknown")
      git_branch=$(git -C "$SOURCE" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
      git_describe=$(git -C "$SOURCE" describe --tags --dirty --always 2>/dev/null || echo "$git_commit")
      if git -C "$SOURCE" diff --quiet 2>/dev/null; then
        git_dirty="false"
      else
        git_dirty="true"
      fi
    fi
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$meta_file" "$log_file" "$now" "$SOURCE" "$git_commit" "$git_branch" "$git_describe" "$git_dirty" "$NOTE" <<'PY'
import json
import sys

meta_file = sys.argv[1]
log_file = sys.argv[2]
now = sys.argv[3]
source = sys.argv[4]
commit = sys.argv[5]
branch = sys.argv[6]
describe = sys.argv[7]
dirty = sys.argv[8].lower() == "true"
note = sys.argv[9]

entry = {
    "timestamp": now,
    "source": source,
    "git": {
        "commit": commit,
        "branch": branch,
        "describe": describe,
        "dirty": dirty,
    },
    "note": note,
}

with open(meta_file, "w", encoding="utf-8") as fh:
    json.dump(entry, fh, indent=2, ensure_ascii=False)

with open(log_file, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY
  else
    echo "{\"timestamp\":\"$now\",\"source\":\"$SOURCE\"}" > "$meta_file"
  fi
}

write_deploy_metadata

echo ""
echo -e "${GREEN}Deploy complete!${NC}"

# Restart sketchybar unless --no-restart
if [ "$NO_RESTART" = false ]; then
  echo ""
  echo -e "${BLUE}Restarting sketchybar...${NC}"

  if command -v sketchybar &> /dev/null; then
    sketchybar --reload
    echo -e "${GREEN}SketchyBar reloaded!${NC}"
  else
    echo -e "${YELLOW}Warning: sketchybar command not found${NC}"
  fi
else
  echo ""
  echo -e "${YELLOW}Skipping restart (--no-restart)${NC}"
  echo "Run 'sketchybar --reload' to apply changes"
fi
