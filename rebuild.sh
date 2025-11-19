#!/bin/bash
# Master rebuild script for Barista
# Rebuilds all components: helpers, GUI, and everything else
# Usage: ./rebuild.sh [clean|rebuild|gui|helpers|all|help]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Function to show help
show_help() {
    cat << EOF
Rebuild Barista Components

Usage: ./rebuild.sh [OPTION]

Options:
  clean       Clean build directory and rebuild everything from scratch
  rebuild     Rebuild all components (default)
  gui         Rebuild only GUI components (config_menu, icon_browser, help_center)
  helpers     Rebuild only helper binaries (C/C++ components)
  all         Rebuild everything (same as rebuild)
  help        Show this help message

Examples:
  ./rebuild.sh           # Quick rebuild everything
  ./rebuild.sh clean     # Clean rebuild everything
  ./rebuild.sh gui       # Rebuild only GUI
  ./rebuild.sh helpers   # Rebuild only helpers

The script will:
  1. Configure CMake (if needed)
  2. Build selected components
  3. Show build status and binary locations

Built binaries will be in: build/bin/
EOF
}

# Function to check prerequisites
check_prerequisites() {
    if ! command -v cmake &> /dev/null; then
        print_error "CMake not found. Install with: brew install cmake"
        exit 1
    fi
    
    if ! command -v clang &> /dev/null; then
        print_error "Clang not found. Install Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi
}

# Function to configure CMake
configure_cmake() {
    if [ ! -d "build" ]; then
        mkdir -p build
    fi
    
    print_info "Configuring CMake..."
    cmake -B build -S . > /dev/null 2>&1 || {
        print_warn "CMake configuration failed, retrying with verbose output..."
        cmake -B build -S .
    }
}

# Function to clean build
clean_build() {
    print_info "Cleaning build directory..."
    rm -rf build
    mkdir -p build
}

# Function to build GUI components
build_gui() {
    print_section "Building GUI Components"
    print_info "Building config_menu, icon_browser, help_center..."
    
    if cmake --build build --target config_menu icon_browser help_center; then
        print_info "✓ GUI build successful!"
    else
        print_error "GUI build failed!"
        return 1
    fi
}

# Function to build helper binaries
build_helpers() {
    print_section "Building Helper Binaries"
    print_info "Building C/C++ helper components..."
    
    if cmake --build build --target clock_widget system_info_widget space_manager \
        submenu_hover popup_anchor popup_hover popup_manager popup_guard \
        icon_manager state_manager widget_manager menu_renderer menu_action; then
        print_info "✓ Helpers build successful!"
    else
        print_error "Helpers build failed!"
        return 1
    fi
}

# Function to build everything
build_all() {
    print_section "Building All Components"
    
    if cmake --build build; then
        print_info "✓ Full build successful!"
    else
        print_error "Build failed!"
        return 1
    fi
}

# Function to show build summary
show_summary() {
    print_section "Build Summary"
    
    if [ -d "build/bin" ]; then
        print_info "Built binaries in build/bin/:"
        ls -lh build/bin/ 2>/dev/null | tail -n +2 | awk '{printf "  %-30s %8s\n", $9, $5}'
        
        echo ""
        print_info "Total binaries: $(ls -1 build/bin/ 2>/dev/null | wc -l | tr -d ' ')"
        print_info "Total size: $(du -sh build/bin/ 2>/dev/null | cut -f1)"
    else
        print_warn "No binaries found in build/bin/"
    fi
}

# Main execution
main() {
    case "${1:-rebuild}" in
        clean)
            check_prerequisites
            clean_build
            configure_cmake
            build_all
            show_summary
            ;;
        rebuild|all)
            check_prerequisites
            configure_cmake
            build_all
            show_summary
            ;;
        gui)
            check_prerequisites
            configure_cmake
            build_gui
            show_summary
            ;;
        helpers)
            check_prerequisites
            configure_cmake
            build_helpers
            show_summary
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"

