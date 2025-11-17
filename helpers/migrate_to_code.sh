#!/bin/bash
set -euo pipefail

SOURCE="${HOME}/.config/sketchybar"
DEFAULT_TARGET="${HOME}/Code/sketchybar"
TARGET="${1:-$DEFAULT_TARGET}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${SOURCE}.backup.${TIMESTAMP}"

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

if [ ! -d "$SOURCE" ]; then
  die "Expected source directory at $SOURCE"
fi

if [ -L "$SOURCE" ]; then
  die "$SOURCE is already a symlink; aborting to avoid confusing state."
fi

if [ -e "$TARGET" ]; then
  if [ ! -d "$TARGET" ]; then
    die "Target $TARGET exists and is not a directory."
  fi
  if [ "$(ls -A "$TARGET")" ]; then
    die "Target $TARGET already exists and is not empty. Pass a different destination."
  fi
else
  mkdir -p "$TARGET"
fi

PARENT="$(dirname "$TARGET")"
mkdir -p "$PARENT"

if command -v rsync >/dev/null 2>&1; then
  log "Copying $SOURCE → $TARGET via rsync…"
  rsync -a --delete "$SOURCE"/ "$TARGET"/
else
  log "rsync not found; falling back to tar copy…"
  (cd "$SOURCE" && tar -cf - .) | (cd "$TARGET" && tar -xf -)
fi

START_DIR=$(pwd)
if [ "$START_DIR" = "$SOURCE" ]; then
  cd /
fi

log "Backing up original directory to $BACKUP"
mv "$SOURCE" "$BACKUP"

log "Linking $TARGET → $SOURCE"
ln -s "$TARGET" "$SOURCE"

log "Done!"
cat <<EOF

New layout:
  - Active repo: $TARGET
  - Previous contents kept at $BACKUP
  - Symlink created at $SOURCE

Restart SketchyBar/yabai/skhd so they pick up the symlinked path. Once you're
happy with the migration you can remove $BACKUP.
EOF
