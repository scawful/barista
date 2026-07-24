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
REQUIREMENTS_FILE="$REPO_DIR/config/requirements.txt"
AUTO_YES=0
PYTHON_BIN="${BARISTA_PYTHON:-python3}"

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
    if command -v "$PYTHON_BIN" &> /dev/null; then
        PYTHON_VERSION=$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
        MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
        
        if [ "$MAJOR" -gt 3 ] || { [ "$MAJOR" -eq 3 ] && [ "$MINOR" -ge 9 ]; }; then
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
    "$PYTHON_BIN" -c "import $1" 2>/dev/null
}

# Print an installed package version and require it to meet a minimum.
check_package_version() {
    "$PYTHON_BIN" - "$1" "$2" <<'PY' 2>/dev/null
import importlib
import re
import sys

package, minimum = sys.argv[1:]

try:
    module = importlib.import_module(package)
except (ImportError, OSError):
    raise SystemExit(2)

installed = str(getattr(module, "__version__", ""))
print(installed or "unknown")


def release(version):
    match = re.match(r"^\s*(\d+(?:\.\d+)*)", version)
    if match is None:
        return None
    parts = tuple(int(part) for part in match.group(1).split("."))
    return parts, version[match.end():]


installed_release = release(installed)
minimum_release = release(minimum)
if installed_release is None or minimum_release is None:
    raise SystemExit(1)

installed_parts, installed_suffix = installed_release
minimum_parts, _ = minimum_release
width = max(len(installed_parts), len(minimum_parts))
installed_parts += (0,) * (width - len(installed_parts))
minimum_parts += (0,) * (width - len(minimum_parts))
is_floor_prerelease = (
    installed_parts == minimum_parts
    and re.search(r"(?:a|b|rc|dev|alpha|beta|pre|preview)", installed_suffix, re.I)
)
raise SystemExit(
    0
    if installed_parts > minimum_parts
    or (installed_parts == minimum_parts and not is_floor_prerelease)
    else 1
)
PY
}

# Check all dependencies
check_deps() {
    local all_ok=true
    
    echo ""
    echo "Checking dependencies..."
    
    if TEXTUAL_VERSION=$(check_package_version "textual" "0.52.1"); then
        echo -e "${GREEN}✓${NC} textual ($TEXTUAL_VERSION)"
    elif [ -n "${TEXTUAL_VERSION:-}" ]; then
        echo -e "${RED}✗${NC} textual 0.52.1+ required (found $TEXTUAL_VERSION)"
        all_ok=false
    else
        echo -e "${RED}✗${NC} textual not installed"
        all_ok=false
    fi
    
    if PYDANTIC_VERSION=$(check_package_version "pydantic" "2.0.0"); then
        echo -e "${GREEN}✓${NC} pydantic ($PYDANTIC_VERSION)"
    elif [ -n "${PYDANTIC_VERSION:-}" ]; then
        echo -e "${RED}✗${NC} pydantic 2+ required (found $PYDANTIC_VERSION)"
        all_ok=false
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
    
    if [ -f "$REQUIREMENTS_FILE" ]; then
        "$PYTHON_BIN" -m pip install -r "$REQUIREMENTS_FILE"
    else
        "$PYTHON_BIN" -m pip install "textual>=0.52.1" "pydantic>=2.0.0" "pyyaml>=6.0.0"
    fi
    
    echo ""
    echo -e "${GREEN}Dependencies installed!${NC}"
}

# Create virtual environment
create_venv() {
    VENV_DIR="$REPO_DIR/.venv"
    
    echo ""
    echo "Creating virtual environment at $VENV_DIR..."
    
    "$PYTHON_BIN" -m venv "$VENV_DIR"
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"

    python3 -m pip install --upgrade pip
    if [ -f "$REQUIREMENTS_FILE" ]; then
        python3 -m pip install -r "$REQUIREMENTS_FILE"
    else
        python3 -m pip install "textual>=0.52.1" "pydantic>=2.0.0" "pyyaml>=6.0.0"
    fi
    
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
        --yes)
            AUTO_YES=1
            if check_deps; then
                echo ""
                echo "Run barista with: $REPO_DIR/bin/barista"
            else
                install_deps
                echo ""
                echo "Run barista with: $REPO_DIR/bin/barista"
            fi
            ;;
        *)
            if check_deps; then
                echo ""
                echo "Run barista with: $REPO_DIR/bin/barista"
            else
                echo ""
                if [[ "${BARISTA_INSTALL_TUI_YES:-0}" == "1" || "$AUTO_YES" == "1" ]]; then
                    install_deps
                    echo ""
                    echo "Run barista with: $REPO_DIR/bin/barista"
                else
                    read -p "Install missing dependencies? [Y/n] " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                        install_deps
                        echo ""
                        echo "Run barista with: $REPO_DIR/bin/barista"
                    fi
                fi
            fi
            ;;
    esac
}

main "$@"
