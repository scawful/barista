#!/bin/bash
# Rebuild GUI components (config_menu and related tools)
# Usage: ./rebuild_gui.sh [clean|rebuild|help]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Function to show help
show_help() {
    cat << EOF
Rebuild GUI Components for Barista

Usage: ./rebuild_gui.sh [OPTION]

Options:
  clean       Clean build directory and rebuild from scratch
  rebuild     Rebuild GUI components (default)
  help        Show this help message

Examples:
  ./rebuild_gui.sh           # Quick rebuild
  ./rebuild_gui.sh clean     # Clean rebuild
  ./rebuild_gui.sh rebuild   # Explicit rebuild

The script will:
  1. Configure CMake (if needed)
  2. Build config_menu and related GUI tools
  3. Show build status

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
    print_info "Configuring CMake..."
    if [ ! -d "build" ]; then
        mkdir -p build
    fi
    
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

# Function to build GUI
build_gui() {
    print_info "Building GUI components..."
    
    if cmake --build build --target config_menu icon_browser help_center 2>&1 | tee /tmp/barista_gui_build.log; then
        print_info "✓ Build successful!"
        print_info "Binaries are in: build/bin/"
        echo ""
        print_info "Built components:"
        ls -lh build/bin/config_menu build/bin/icon_browser build/bin/help_center 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}'
    else
        print_error "Build failed! Check /tmp/barista_gui_build.log for details"
        exit 1
    fi
}

# Main execution
main() {
    case "${1:-rebuild}" in
        clean)
            check_prerequisites
            clean_build
            configure_cmake
            build_gui
            ;;
        rebuild)
            check_prerequisites
            configure_cmake
            build_gui
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
