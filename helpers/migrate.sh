#!/bin/bash
# Configuration migration system
# Handles breaking changes between versions

set -euo pipefail

CONFIG_DIR="${HOME}/.config/sketchybar"
STATE_FILE="$CONFIG_DIR/state.json"
VERSION_FILE="$CONFIG_DIR/.barista_version"

# Get current version
CURRENT_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0")
NEW_VERSION="2.0.0"

# Migration functions
migrate_1_0_to_2_0() {
  echo "Migrating from 1.0.x to 2.0.0..."
  
  if [[ ! -f "$STATE_FILE" ]]; then
    return
  fi
  
  # Use Python for JSON manipulation
  python3 <<EOF
import json
import sys
import os

state_file = "$STATE_FILE"

try:
    with open(state_file, "r") as f:
        state = json.load(f)
    
    migrated = False
    
    # Example migrations
    # Rename old keys to new structure
    if "widgets" in state:
        # Migrate old network widget structure if needed
        if "network" in state.get("widgets", {}):
            # Keep as-is, no migration needed yet
            pass
    
    # Add version field if missing
    if "version" not in state:
        state["version"] = "2.0.0"
        migrated = True
    
    # Save if migrated
    if migrated:
        with open(state_file, "w") as f:
            json.dump(state, f, indent=2)
        print("✅ Configuration migrated")
    else:
        print("✅ Configuration already up to date")
        
except Exception as e:
    print(f"⚠️  Migration error: {e}")
    sys.exit(1)
EOF
}

# Run migrations based on version
if [[ "$CURRENT_VERSION" != "$NEW_VERSION" ]]; then
  echo "Running migrations from $CURRENT_VERSION to $NEW_VERSION..."
  
  # Version-specific migrations
  case "$CURRENT_VERSION" in
    0.0.0|1.*)
      migrate_1_0_to_2_0
      ;;
    *)
      echo "No migration needed for version $CURRENT_VERSION"
      ;;
  esac
  
  # Update version file
  echo "$NEW_VERSION" > "$VERSION_FILE"
  echo "✅ Migration complete"
else
  echo "✅ Already at version $NEW_VERSION"
fi

