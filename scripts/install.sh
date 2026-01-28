#!/bin/bash
# SketchyBar Configuration Installer
# Portable setup script for any macOS user

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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
  local source_dir=""
  if [ -f "$ROOT_DIR/main.lua" ]; then
    source_dir="$ROOT_DIR"
  elif [ -f "$(dirname "$0")/main.lua" ]; then
    source_dir="$(dirname "$0")"
  fi

  if [ -n "$source_dir" ]; then
    # Installing from local directory
    echo_info "Copying files from local directory..."
    rsync -a \
      --exclude ".git" \
      --exclude "build" \
      --exclude "cache" \
      --exclude ".DS_Store" \
      "$source_dir/" "$INSTALL_DIR/"
  else
    # Clone from GitHub
    echo_info "Cloning from GitHub..."
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi

  echo_success "Configuration files installed"
}

# Build all components with CMake
build_components() {
  echo_info "Building components with CMake..."

  cd "$INSTALL_DIR"
  
  # Check for CMake
  if ! command -v cmake &> /dev/null; then
    echo_error "CMake is not installed. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
      echo_error "Homebrew is not installed. Please install from https://brew.sh"
      exit 1
    fi
    brew install cmake
  fi

  # Create build directory
  mkdir -p build
  cd build

  # Configure and build
  if ! cmake .. -DCMAKE_BUILD_TYPE=Release; then
    echo_error "CMake configuration failed"
    exit 1
  fi

  if ! cmake --build . -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4); then
    echo_error "Build failed"
    exit 1
  fi

  # Copy binaries to bin directory
  mkdir -p "$INSTALL_DIR/bin"
  cp -f bin/* "$INSTALL_DIR/bin/" 2>/dev/null || true

  echo_success "All components built successfully"
}

# Setup profile
setup_profile() {
  echo ""
  local profile_env="${BARISTA_PROFILE:-${BARISTA_INSTALL_PROFILE:-}}"
  if [ -n "$profile_env" ]; then
    SELECTED_PROFILE="$profile_env"
    echo_info "Using profile from BARISTA_PROFILE: $SELECTED_PROFILE"
  else
    echo "Available profiles:"
    echo "  1) minimal  - Clean, basic setup (recommended for new users)"
    echo "  2) personal - Full featured with integrations"
    echo "  3) work     - Work-focused setup"
    echo "  4) girlfriend - Warm, cozy setup (friendlier defaults)"
    echo "  5) custom   - Create your own from template"
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
        SELECTED_PROFILE="girlfriend"
        ;;
      5)
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
  fi

  BAR_HEIGHT=32
  CORNER_RADIUS=9
  BAR_COLOR="0xC021162F"
  BLUR_RADIUS=30
  WIDGET_SCALE=1.0
  POPUP_PADDING=8
  POPUP_CORNER_RADIUS=6
  POPUP_BORDER_WIDTH=2
  POPUP_BORDER_COLOR="0x60cdd6f4"
  HOVER_COLOR="0x40f5c2e7"
  INTEGRATION_YAZE=false
  INTEGRATION_EMACS=false
  INTEGRATION_HALEXT=false

  if [ "$SELECTED_PROFILE" = "girlfriend" ]; then
    BAR_HEIGHT=32
    CORNER_RADIUS=12
    BAR_COLOR="0xE04A3426"
    BLUR_RADIUS=26
    WIDGET_SCALE=1.05
    POPUP_PADDING=10
    POPUP_CORNER_RADIUS=10
    POPUP_BORDER_WIDTH=1
    POPUP_BORDER_COLOR="0x40F5E6D3"
    HOVER_COLOR="0x50F5E6D3"
  fi

  if [ "$SELECTED_PROFILE" = "personal" ]; then
    INTEGRATION_YAZE=true
    INTEGRATION_EMACS=true
    INTEGRATION_HALEXT=false
  elif [ "$SELECTED_PROFILE" = "work" ]; then
    INTEGRATION_YAZE=false
    INTEGRATION_EMACS=true
    INTEGRATION_HALEXT=true
  fi

  local window_manager_mode="${BARISTA_WINDOW_MANAGER_MODE:-}"
  if [ -z "$window_manager_mode" ]; then
    case "$SELECTED_PROFILE" in
      girlfriend)
        window_manager_mode="disabled"
        ;;
      minimal)
        window_manager_mode="optional"
        ;;
      personal|work)
        window_manager_mode="required"
        ;;
      *)
        window_manager_mode="auto"
        ;;
    esac

    if [ -z "${BARISTA_INSTALL_NONINTERACTIVE:-}" ]; then
      echo ""
      echo "Window manager modes:"
      echo "  auto     - Enable when yabai is installed"
      echo "  optional - Only show when yabai is running"
      echo "  required - Expect yabai/skhd to be configured"
      echo "  disabled - Hide yabai/skhd features"
      echo ""
      read -p "Select window manager mode [$window_manager_mode]: " wm_choice
      if [ -n "$wm_choice" ]; then
        window_manager_mode="$wm_choice"
      fi
    fi
  fi

  YABAI_STATUS=true
  YABAI_SHORTCUTS=true
  if [ "$window_manager_mode" = "disabled" ]; then
    YABAI_STATUS=false
    YABAI_SHORTCUTS=false
  fi

  # Create state.json with selected profile
  echo_info "Creating initial state.json with profile: $SELECTED_PROFILE"

  cat > "$INSTALL_DIR/state.json" <<EOF
{
  "profile": "$SELECTED_PROFILE",
  "modes": {
    "window_manager": "$window_manager_mode"
  },
  "widgets": {
    "clock": true,
    "battery": true,
    "network": true,
    "system_info": true,
    "volume": true,
    "yabai_status": ${YABAI_STATUS}
  },
  "toggles": {
    "yabai_shortcuts": ${YABAI_SHORTCUTS}
  },
  "appearance": {
    "bar_height": ${BAR_HEIGHT},
    "corner_radius": ${CORNER_RADIUS},
    "bar_color": "${BAR_COLOR}",
    "blur_radius": ${BLUR_RADIUS},
    "widget_scale": ${WIDGET_SCALE},
    "popup_padding": ${POPUP_PADDING},
    "popup_corner_radius": ${POPUP_CORNER_RADIUS},
    "popup_border_width": ${POPUP_BORDER_WIDTH},
    "popup_border_color": "${POPUP_BORDER_COLOR}",
    "hover_color": "${HOVER_COLOR}"
  },
  "integrations": {
    "yaze": {
      "enabled": ${INTEGRATION_YAZE}
    },
    "emacs": {
      "enabled": ${INTEGRATION_EMACS}
    },
    "halext": {
      "enabled": ${INTEGRATION_HALEXT},
      "server_url": "",
      "api_key": "",
      "sync_interval": 300
    }
  }
}
EOF

  echo_success "Profile configured: $SELECTED_PROFILE"
}

# Setup Window Manager (Yabai/Skhd)
setup_window_manager() {
  if [ "$window_manager_mode" = "disabled" ]; then
    return
  fi

  echo ""
  echo "Window Manager Configuration (Yabai + Skhd)"
  echo "-------------------------------------------"
  echo "This can install Scawful's default configurations for:"
  echo "  - Yabai (Tiling Window Manager)"
  echo "  - Skhd (Hotkeys)"
  echo ""
  
  if [ -z "${BARISTA_INSTALL_NONINTERACTIVE:-}" ]; then
    read -p "Install bundled Yabai/Skhd configs? [y/N]: " install_wm
  else
    install_wm="n"
  fi

  if [[ "$install_wm" =~ ^[Yy]$ ]]; then
    echo_info "Installing Window Manager configs..."
    
    # Yabai
    if [ -d "$INSTALL_DIR/extras/yabai" ]; then
      mkdir -p "$HOME/.config/yabai"
      if [ -f "$HOME/.config/yabai/yabairc" ]; then
        cp "$HOME/.config/yabai/yabairc" "$HOME/.config/yabai/yabairc.backup.$(date +%s)"
        echo_warning "Backed up existing yabairc"
      fi
      cp "$INSTALL_DIR/extras/yabai/yabairc" "$HOME/.config/yabai/yabairc"
      chmod +x "$HOME/.config/yabai/yabairc"
      echo_success "Installed yabairc"
      
      # Restart Yabai
      if command -v yabai &> /dev/null; then
        yabai --restart-service || brew services restart yabai
      fi
    fi

    # Skhd
    if [ -d "$INSTALL_DIR/extras/skhd" ]; then
      mkdir -p "$HOME/.config/skhd"
      if [ -f "$HOME/.config/skhd/skhdrc" ]; then
        cp "$HOME/.config/skhd/skhdrc" "$HOME/.config/skhd/skhdrc.backup.$(date +%s)"
        echo_warning "Backed up existing skhdrc"
      fi
      cp "$INSTALL_DIR/extras/skhd/skhdrc" "$HOME/.config/skhd/skhdrc"
      echo_success "Installed skhdrc"
      
      # Restart Skhd
      if command -v skhd &> /dev/null; then
        skhd --restart-service || brew services restart skhd
      fi
    fi
  fi
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
  build_components
  setup_profile
  setup_window_manager
  configure_sketchybar
  start_sketchybar
  print_next_steps
}

# Run installation
main
