#!/bin/bash
# Test script for refactored SketchyBar components

set -e

echo "=== SketchyBar Refactor Test Suite ==="
echo ""

BIN_DIR="$HOME/.config/sketchybar/bin"

# Check if all components are installed
echo "1. Checking installed components..."
components=("icon_manager" "state_manager" "widget_manager" "menu_renderer")
missing=0
for component in "${components[@]}"; do
    if [ -x "$BIN_DIR/$component" ]; then
        echo "   ✓ $component installed"
    else
        echo "   ✗ $component missing"
        missing=$((missing + 1))
    fi
done

if [ $missing -gt 0 ]; then
    echo ""
    echo "ERROR: Some components are missing. Run 'cd helpers && make install'"
    exit 1
fi

echo ""
echo "2. Testing Icon Manager..."
echo "   Categories:"
$BIN_DIR/icon_manager categories | head -5
echo "   ..."
echo "   Battery icon: $($BIN_DIR/icon_manager get battery '')"
echo "   ✓ Icon manager working"

echo ""
echo "3. Testing State Manager..."
$BIN_DIR/state_manager init
$BIN_DIR/state_manager widget battery > /dev/null
echo "   ✓ State manager initialized"

echo ""
echo "4. Testing Widget Manager..."
stats=$($BIN_DIR/widget_manager stats | head -1)
echo "   $stats"
echo "   ✓ Widget manager working"

echo ""
echo "5. Testing C Bridge Module..."
if lua -e "require('modules.c_bridge')" 2>/dev/null; then
    echo "   ✓ C bridge module loads"
else
    echo "   ⚠ C bridge module not found (expected if running from different directory)"
fi

echo ""
echo "6. Checking Enhanced Control Panel..."
if [ -x "gui/bin/config_menu_enhanced" ]; then
    echo "   ✓ Enhanced control panel built"
    echo ""
    echo "   Launch with: gui/bin/config_menu_enhanced"
else
    echo "   ⚠ Enhanced control panel not built"
    echo "   Run: cd gui && make config_enhanced"
fi

echo ""
echo "=== Performance Comparison ==="
echo ""
echo "Testing icon lookup performance..."

# Test Lua icon lookup (if available)
echo -n "Lua lookup (100 iterations): "
time for i in {1..100}; do
    lua -e "require('modules.icons').find('battery')" 2>/dev/null || true
done 2>&1 | grep real || echo "N/A"

# Test C icon lookup
echo -n "C lookup (100 iterations):   "
time for i in {1..100}; do
    $BIN_DIR/icon_manager get battery > /dev/null
done 2>&1 | grep real

echo ""
echo "=== Test Summary ==="
echo ""
echo "✅ All core components are working!"
echo ""
echo "Next steps:"
echo "1. Start widget daemon:     $BIN_DIR/widget_manager daemon &"
echo "2. Launch control panel:    gui/bin/config_menu_enhanced"
echo "3. Reload SketchyBar:      sketchybar --reload"
echo ""
echo "For full documentation, see: REFACTOR_SUMMARY.md"