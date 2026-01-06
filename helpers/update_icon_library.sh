#!/bin/bash

# Updates the icon library in config_menu.m with more comprehensive icons

CODE_DIR="${BARISTA_CODE_DIR:-$HOME/src}"
SOURCE_DIR="${BARISTA_SOURCE_DIR:-$CODE_DIR/lab/barista}"
CONFIG_FILE="${BARISTA_ICON_CONFIG_FILE:-$SOURCE_DIR/gui/config_menu.m}"
export CONFIG_FILE

# Backup original file
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

# Create a temporary file with the new icon library
cat > /tmp/new_icons.txt << 'EOF'
  self.iconLibrary = @[
    // System & Hardware
    @{ @"title": @"Apple", @"glyph": @"" },
    @{ @"title": @"Apple Alt", @"glyph": @"" },
    @{ @"title": @"CPU Chip", @"glyph": @"󰍛" },
    @{ @"title": @"CPU Hot", @"glyph": @"󰈸" },
    @{ @"title": @"CPU Warm", @"glyph": @"󰔄" },
    @{ @"title": @"Memory", @"glyph": @"󰘚" },
    @{ @"title": @"Disk", @"glyph": @"󰋊" },
    @{ @"title": @"Network", @"glyph": @"󰖩" },
    @{ @"title": @"Network Off", @"glyph": @"󰖪" },
    @{ @"title": @"Battery", @"glyph": @"" },
    @{ @"title": @"Volume", @"glyph": @"󰕾" },
    @{ @"title": @"Settings", @"glyph": @"" },
    // Development
    @{ @"title": @"Terminal", @"glyph": @"" },
    @{ @"title": @"Code", @"glyph": @"" },
    @{ @"title": @"Git", @"glyph": @"" },
    @{ @"title": @"GitHub", @"glyph": @"" },
    @{ @"title": @"VSCode", @"glyph": @"󰨞" },
    @{ @"title": @"Vim", @"glyph": @"" },
    @{ @"title": @"Emacs", @"glyph": @"" },
    // Files & Folders
    @{ @"title": @"Folder", @"glyph": @"" },
    @{ @"title": @"Folder Open", @"glyph": @"" },
    @{ @"title": @"File", @"glyph": @"" },
    @{ @"title": @"Finder", @"glyph": @"󰀶" },
    @{ @"title": @"Document", @"glyph": @"󰈙" },
    // Apps
    @{ @"title": @"Safari", @"glyph": @"󰀹" },
    @{ @"title": @"Chrome", @"glyph": @"" },
    @{ @"title": @"Firefox", @"glyph": @"" },
    @{ @"title": @"Calendar", @"glyph": @"" },
    @{ @"title": @"Clock", @"glyph": @"" },
    @{ @"title": @"Music", @"glyph": @"" },
    @{ @"title": @"Messages", @"glyph": @"󰍦" },
    @{ @"title": @"Mail", @"glyph": @"" },
    // Window Management
    @{ @"title": @"Window BSP", @"glyph": @"󰆾" },
    @{ @"title": @"Window Stack", @"glyph": @"󰓩" },
    @{ @"title": @"Window Float", @"glyph": @"󰒄" },
    @{ @"title": @"Layout Grid", @"glyph": @"󰕰" },
    // Gaming & Entertainment
    @{ @"title": @"Gamepad", @"glyph": @"󰍳" },
    @{ @"title": @"Quest", @"glyph": @"" },
    @{ @"title": @"Triforce", @"glyph": @"󰊠" },
    @{ @"title": @"Controller", @"glyph": @"󰊴" },
    // Misc
    @{ @"title": @"Star", @"glyph": @"" },
    @{ @"title": @"Heart", @"glyph": @"󰣐" },
    @{ @"title": @"Lightning", @"glyph": @"󰷓" },
    @{ @"title": @"Moon", @"glyph": @"󰽤" },
    @{ @"title": @"Sun", @"glyph": @"󰖙" },
    @{ @"title": @"Cloud", @"glyph": @"󰖐" }
  ];
EOF

# Use Python to replace the icon library section
python3 << 'PYTHON_EOF'
import re

import os

config_file = os.environ.get("CONFIG_FILE", os.path.expanduser("~/src/lab/barista/gui/config_menu.m"))

with open(config_file, 'r', encoding='utf-8') as f:
    content = f.read()

# Read new icon library
with open('/tmp/new_icons.txt', 'r', encoding='utf-8') as f:
    new_icons = f.read()

# Replace the icon library section
pattern = r'self\.iconLibrary = @\[.*?\];'
replacement = new_icons.strip()

content = re.sub(pattern, replacement, content, flags=re.DOTALL)

with open(config_file, 'w', encoding='utf-8') as f:
    f.write(content)

print("Icon library updated successfully!")
PYTHON_EOF

rm -f /tmp/new_icons.txt

echo "Done! Backup saved to ${CONFIG_FILE}.bak"
