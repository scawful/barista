#!/bin/bash
# Post-update script for Barista
# Runs after brew upgrade barista or manual updates
# Preserves user customizations

set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
BACKUP_DIR="${CONFIG_DIR}.backup.$(date +%Y%m%d_%H%M%S)"

echo "Running Barista post-update..."

# 1. Backup current configuration
if [[ -d "$CONFIG_DIR" ]]; then
  echo "Creating backup..."
  mkdir -p "$BACKUP_DIR"
  cp "$CONFIG_DIR/state.json" "$BACKUP_DIR/" 2>/dev/null || true
  cp -r "$CONFIG_DIR/profiles" "$BACKUP_DIR/" 2>/dev/null || true
  cp -r "$CONFIG_DIR/themes" "$BACKUP_DIR/" 2>/dev/null || true
  echo "Backup saved to: $BACKUP_DIR"
fi

# 2. Merge new configuration files
# Only copy files that don't exist or are templates
merge_config_files() {
  local source_dir="$1"
  local dest_dir="$2"
  
  if [[ ! -d "$source_dir" ]]; then
    return
  fi
  
  find "$source_dir" -type f | while read -r file; do
    rel_path="${file#$source_dir/}"
    dest_file="$dest_dir/$rel_path"
    
    # Skip user customization files
    if [[ "$rel_path" == "state.json" ]] || \
       [[ "$rel_path" == *.local.lua ]] || \
       [[ "$rel_path" == plugins/*.local.sh ]]; then
      continue
    fi
    
    # If file doesn't exist, copy it
    if [[ ! -f "$dest_file" ]]; then
      mkdir -p "$(dirname "$dest_file")"
      cp "$file" "$dest_file"
      echo "Added: $rel_path"
    # If it's a template file (ends in .template), don't overwrite
    elif [[ "$file" == *.template ]]; then
      echo "Template file: $rel_path (skipping, manual review needed)"
    fi
  done
}

# 3. Update binaries if build directory exists
if [[ -d "$CONFIG_DIR/build" ]] && command -v cmake &> /dev/null; then
  echo "Rebuilding components..."
  cd "$CONFIG_DIR"
  if cmake -B build -S . -DCMAKE_BUILD_TYPE=Release 2>/dev/null && \
     cmake --build build -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4) 2>/dev/null; then
    mkdir -p "$CONFIG_DIR/bin"
    cp -f build/bin/* "$CONFIG_DIR/bin/" 2>/dev/null || true
    echo "Binaries updated"
  else
    echo "Build skipped (no CMakeLists.txt or build failed)"
  fi
fi

# 4. Check for migration needs
if [[ -f "$CONFIG_DIR/helpers/migrate.sh" ]]; then
  echo "Checking for configuration migrations..."
  bash "$CONFIG_DIR/helpers/migrate.sh" || echo "Migration script had issues"
fi

echo "✅ Post-update complete"

