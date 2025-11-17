SRC_CONFIG=config_menu.m
SRC_CONFIG_V2=config_menu_v2.m
SRC_CONFIG_ENHANCED=config_menu_enhanced.m
SRC_ICONS=icon_browser.m
SRC_HELP=help_center.m
BIN_DIR=bin
BIN_CONFIG=$(BIN_DIR)/config_menu
BIN_CONFIG_V2=$(BIN_DIR)/config_menu_v2
BIN_CONFIG_ENHANCED=$(BIN_DIR)/config_menu_enhanced
BIN_ICONS=$(BIN_DIR)/icon_browser
BIN_HELP=$(BIN_DIR)/help_center
CFLAGS=-fobjc-arc -framework Cocoa -framework Foundation

all: $(BIN_CONFIG) $(BIN_CONFIG_V2) $(BIN_CONFIG_ENHANCED) $(BIN_ICONS) $(BIN_HELP)

$(BIN_CONFIG): $(SRC_CONFIG)
	mkdir -p $(BIN_DIR)
	clang $(CFLAGS) $(SRC_CONFIG) -o $(BIN_CONFIG)

$(BIN_CONFIG_V2): $(SRC_CONFIG_V2)
	mkdir -p $(BIN_DIR)
	clang $(CFLAGS) $(SRC_CONFIG_V2) -o $(BIN_CONFIG_V2)

$(BIN_CONFIG_ENHANCED): $(SRC_CONFIG_ENHANCED)
	mkdir -p $(BIN_DIR)
	clang $(CFLAGS) $(SRC_CONFIG_ENHANCED) -o $(BIN_CONFIG_ENHANCED)
	@echo ""
	@echo "=== Enhanced Control Panel Built ==="
	@echo ""
	@echo "New features in enhanced control panel:"
	@echo "  • Advanced appearance customization with live preview"
	@echo "  • Per-widget configuration (scale, color, icon, update rate)"
	@echo "  • Comprehensive icon browser with search and categories"
	@echo "  • Space-specific icon and mode management"
	@echo "  • Performance monitoring and daemon control"
	@echo "  • Theme selection and font customization"
	@echo ""
	@echo "Launch with: $(BIN_CONFIG_ENHANCED)"

$(BIN_ICONS): $(SRC_ICONS)
	mkdir -p $(BIN_DIR)
	clang $(CFLAGS) $(SRC_ICONS) -o $(BIN_ICONS)

$(BIN_HELP): $(SRC_HELP)
	mkdir -p $(BIN_DIR)
	clang $(CFLAGS) $(SRC_HELP) -o $(BIN_HELP)

config: $(BIN_CONFIG)

config_v2: $(BIN_CONFIG_V2)

config_enhanced: $(BIN_CONFIG_ENHANCED)

icons: $(BIN_ICONS)

help: $(BIN_HELP)

clean:
	rm -rf $(BIN_DIR)

.PHONY: all config config_v2 config_enhanced icons help clean
