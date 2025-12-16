#!/bin/bash
# install-tui.sh - Install Python dependencies for barista TUI
#
# Usage:
#   ./scripts/install-tui.sh           # Install with pip
#   ./scripts/install-tui.sh --check   # Check if deps are installed
#   ./scripts/install-tui.sh --venv    # Create and use a virtual environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Barista TUI Installer${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check Python version
check_python() {
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
        MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
        
        if [ "$MAJOR" -ge 3 ] && [ "$MINOR" -ge 9 ]; then
            echo -e "${GREEN}✓${NC} Python $PYTHON_VERSION found"
            return 0
        else
            echo -e "${RED}✗${NC} Python 3.9+ required (found $PYTHON_VERSION)"
            return 1
        fi
    else
        echo -e "${RED}✗${NC} Python 3 not found"
        return 1
    fi
}

# Check if a package is installed
check_package() {
    python3 -c "import $1" 2>/dev/null
}

# Check all dependencies
check_deps() {
    local all_ok=true
    
    echo ""
    echo "Checking dependencies..."
    
    if check_package "textual"; then
        TEXTUAL_VERSION=$(python3 -c "import textual; print(textual.__version__)" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓${NC} textual ($TEXTUAL_VERSION)"
    else
        echo -e "${RED}✗${NC} textual not installed"
        all_ok=false
    fi
    
    if check_package "pydantic"; then
        PYDANTIC_VERSION=$(python3 -c "import pydantic; print(pydantic.__version__)" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓${NC} pydantic ($PYDANTIC_VERSION)"
    else
        echo -e "${RED}✗${NC} pydantic not installed"
        all_ok=false
    fi
    
    if check_package "yaml"; then
        echo -e "${GREEN}✓${NC} pyyaml"
    else
        echo -e "${YELLOW}○${NC} pyyaml (optional)"
    fi
    
    if $all_ok; then
        echo ""
        echo -e "${GREEN}All required dependencies are installed!${NC}"
        return 0
    else
        echo ""
        echo -e "${YELLOW}Some dependencies are missing.${NC}"
        return 1
    fi
}

# Install dependencies
install_deps() {
    echo ""
    echo "Installing dependencies..."
    
    if [ -f "$REPO_DIR/requirements.txt" ]; then
        pip3 install -r "$REPO_DIR/requirements.txt"
    else
        pip3 install textual pydantic pyyaml
    fi
    
    echo ""
    echo -e "${GREEN}Dependencies installed!${NC}"
}

# Create virtual environment
create_venv() {
    VENV_DIR="$REPO_DIR/.venv"
    
    echo ""
    echo "Creating virtual environment at $VENV_DIR..."
    
    python3 -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    
    pip install --upgrade pip
    pip install -r "$REPO_DIR/requirements.txt"
    
    echo ""
    echo -e "${GREEN}Virtual environment created!${NC}"
    echo ""
    echo "To activate:"
    echo "  source $VENV_DIR/bin/activate"
    echo ""
    echo "To run barista:"
    echo "  $REPO_DIR/bin/barista"
}

# Main
main() {
    if ! check_python; then
        echo ""
        echo "Please install Python 3.9 or later."
        echo "  macOS: brew install python@3.11"
        exit 1
    fi
    
    case "${1:-}" in
        --check)
            check_deps
            ;;
        --venv)
            create_venv
            ;;
        *)
            if check_deps; then
                echo ""
                echo "Run barista with: $REPO_DIR/bin/barista"
            else
                echo ""
                read -p "Install missing dependencies? [Y/n] " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                    install_deps
                    echo ""
                    echo "Run barista with: $REPO_DIR/bin/barista"
                fi
            fi
            ;;
    esac
}

main "$@"
