#!/bin/bash
# SketchyBar Configuration Installer
# Portable setup script for any macOS user

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="${HOME}/.config/sketchybar"
REPO_URL="https://github.com/scawful/barista"  # TODO: Update when uploaded
DEFAULT_PROFILE="minimal"

echo_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

echo_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check dependencies
check_dependencies() {
  echo_info "Checking dependencies..."

  # Check SketchyBar
  if ! command -v sketchybar &> /dev/null; then
    echo_error "SketchyBar is not installed. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
      echo_error "Homebrew is not installed. Please install from https://brew.sh"
      exit 1
    fi
    brew install felixkratz/formulae/sketchybar
  fi

  # Check Lua
  if ! command -v lua &> /dev/null; then
    echo_warning "Lua not found, installing..."
    brew install lua
  fi

  # Check jq (for JSON manipulation)
  if ! command -v jq &> /dev/null; then
    echo_warning "jq not found, installing..."
    brew install jq
  fi

  # Check optional dependencies
  echo_info "Checking optional dependencies..."

  if ! command -v yabai &> /dev/null; then
    echo_warning "Yabai not installed (optional but recommended)"
    echo_warning "Install: brew install koekeishiya/formulae/yabai"
  fi

  if ! command -v skhd &> /dev/null; then
    echo_warning "skhd not installed (optional but recommended)"
    echo_warning "Install: brew install koekeishiya/formulae/skhd"
  fi

  echo_success "Dependency check complete"
}

# Backup existing configuration
backup_existing() {
  if [ -d "$INSTALL_DIR" ]; then
    BACKUP_DIR="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    echo_warning "Existing configuration found"
    echo_info "Creating backup at $BACKUP_DIR"
    mv "$INSTALL_DIR" "$BACKUP_DIR"
    echo_success "Backup created"
  fi
}

# Install configuration
install_config() {
  echo_info "Installing SketchyBar configuration..."

  # Create directory
  mkdir -p "$INSTALL_DIR"

  # Clone or copy files
  if [ -d "$(dirname "$0")" ] && [ -f "$(dirname "$0")/main.lua" ]; then
    # Installing from local directory
    echo_info "Copying files from local directory..."
    cp -R "$(dirname "$0")"/* "$INSTALL_DIR/"
  else
    # Clone from GitHub
    echo_info "Cloning from GitHub..."
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi

  echo_success "Configuration files installed"
}

# Build C helpers
build_helpers() {
  echo_info "Building C helper programs..."

  cd "$INSTALL_DIR/helpers"
  if ! make clean && make; then
    echo_error "Failed to build C helpers"
    exit 1
  fi

  echo_success "C helpers built successfully"
}

# Build GUI tools
build_gui() {
  echo_info "Building GUI control panel..."

  cd "$INSTALL_DIR/gui"
  if ! make clean && make all; then
    echo_error "Failed to build GUI tools"
    exit 1
  fi

  echo_success "GUI tools built successfully"
}

# Setup profile
setup_profile() {
  echo ""
  echo "Available profiles:"
  echo "  1) minimal  - Clean, basic setup (recommended for new users)"
  echo "  2) personal - Full featured with integrations"
  echo "  3) work     - Work-focused setup"
  echo "  4) custom   - Create your own from template"
  echo ""

  read -p "Select profile [1]: " profile_choice
  profile_choice=${profile_choice:-1}

  case $profile_choice in
    1)
      SELECTED_PROFILE="minimal"
      ;;
    2)
      SELECTED_PROFILE="personal"
      ;;
    3)
      SELECTED_PROFILE="work"
      ;;
    4)
      read -p "Enter custom profile name: " custom_name
      SELECTED_PROFILE="$custom_name"

      # Create from template
      if [ ! -f "$INSTALL_DIR/profiles/$SELECTED_PROFILE.lua" ]; then
        echo_info "Creating profile from minimal template..."
        cp "$INSTALL_DIR/profiles/minimal.lua" "$INSTALL_DIR/profiles/$SELECTED_PROFILE.lua"
        echo_info "Edit your profile at: $INSTALL_DIR/profiles/$SELECTED_PROFILE.lua"
      fi
      ;;
    *)
      echo_warning "Invalid choice, using minimal profile"
      SELECTED_PROFILE="minimal"
      ;;
  esac

  # Create state.json with selected profile
  echo_info "Creating initial state.json with profile: $SELECTED_PROFILE"

  cat > "$INSTALL_DIR/state.json" <<EOF
{
  "profile": "$SELECTED_PROFILE",
  "widgets": {
    "clock": true,
    "battery": true,
    "network": true,
    "system_info": true,
    "volume": true,
    "yabai_status": true
  },
  "appearance": {
    "bar_height": 32,
    "corner_radius": 9,
    "bar_color": "0xC021162F",
    "blur_radius": 30,
    "widget_scale": 1.0
  },
  "integrations": {
    "yaze": {
      "enabled": false
    },
    "emacs": {
      "enabled": false
    },
    "halext": {
      "enabled": false,
      "server_url": "",
      "api_key": "",
      "sync_interval": 300
    }
  }
}
EOF

  echo_success "Profile configured: $SELECTED_PROFILE"
}

# Configure SketchyBar to use this config
configure_sketchybar() {
  echo_info "Configuring SketchyBar..."

  # Create/update sketchybarrc
  cat > "${HOME}/.config/sketchybar/sketchybarrc" <<'EOF'
#!/usr/bin/env lua
-- SketchyBar Configuration Entry Point
-- This file is the main entry point for SketchyBar

-- Set up module paths
local HOME = os.getenv("HOME")
local CONFIG_DIR = HOME .. "/.config/sketchybar"

-- Run main configuration
dofile(CONFIG_DIR .. "/main.lua")
EOF

  chmod +x "${HOME}/.config/sketchybar/sketchybarrc"

  echo_success "SketchyBar configured"
}

# Start SketchyBar
start_sketchybar() {
  echo_info "Starting SketchyBar..."

  # Stop existing instance
  brew services stop sketchybar 2>/dev/null || true

  # Start service
  brew services start sketchybar

  sleep 2

  if pgrep -x "sketchybar" > /dev/null; then
    echo_success "SketchyBar started successfully!"
  else
    echo_error "Failed to start SketchyBar"
    echo_info "Try running: sketchybar --reload"
    exit 1
  fi
}

# Print next steps
print_next_steps() {
  echo ""
  echo_success "Installation complete!"
  echo ""
  echo "Next steps:"
  echo "  1. Customize your profile: $INSTALL_DIR/profiles/$SELECTED_PROFILE.lua"
  echo "  2. Edit state.json: $INSTALL_DIR/state.json"
  echo "  3. Open control panel: Shift + Click Apple menu icon"
  echo "  4. Reload SketchyBar: sketchybar --reload"
  echo ""
  echo "Documentation:"
  echo "  - README: $INSTALL_DIR/README.md"
  echo "  - Control Panel: $INSTALL_DIR/docs/CONTROL_PANEL_V2.md"
  echo "  - Improvements: $INSTALL_DIR/docs/IMPROVEMENTS.md"
  echo ""
  echo "Enjoy your new status bar!"
}

# Main installation flow
main() {
  echo ""
  echo "╔═══════════════════════════════════════╗"
  echo "║  SketchyBar Configuration Installer   ║"
  echo "╚═══════════════════════════════════════╝"
  echo ""

  check_dependencies
  backup_existing
  install_config
  build_helpers
  build_gui
  setup_profile
  configure_sketchybar
  start_sketchybar
  print_next_steps
}

# Run installation
main
