#!/bin/bash
# deploy.sh - Deploy barista config to ~/.config/sketchybar
#
# Usage:
#   ./deploy.sh           # Full deploy with restart
#   ./deploy.sh --dry-run # Preview what would be synced
#   ./deploy.sh --no-restart # Deploy without restarting sketchybar

set -e

SOURCE="$HOME/Code/barista"
DEST="$HOME/.config/sketchybar"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
NO_RESTART=false
for arg in "$@"; do
  case $arg in
    --dry-run)
      DRY_RUN=true
      ;;
    --no-restart)
      NO_RESTART=true
      ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--no-restart]"
      echo ""
      echo "Options:"
      echo "  --dry-run     Preview changes without applying"
      echo "  --no-restart  Deploy without restarting sketchybar"
      exit 0
      ;;
  esac
done

echo -e "${BLUE}Barista Deploy${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Source: ${GREEN}$SOURCE${NC}"
echo -e "Dest:   ${GREEN}$DEST${NC}"
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

# Build rsync options
RSYNC_OPTS="-av --delete"

# Exclude patterns:
# - .git: version control
# - build/: CMake build artifacts
# - .context/: AFS context (session-specific)
# - *.o, *.dSYM: compiled objects
# - .DS_Store: macOS metadata
# - __pycache__: Python cache
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

# Perform sync
echo -e "${BLUE}Syncing files...${NC}"
rsync $RSYNC_OPTS "$SOURCE/" "$DEST/"

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
