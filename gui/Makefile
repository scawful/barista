SRC_CONFIG=config_menu.m
SRC_ICONS=icon_browser.m
SRC_HELP=help_center.m
BIN_DIR=bin
BIN_CONFIG=$(BIN_DIR)/config_menu
BIN_ICONS=$(BIN_DIR)/icon_browser
BIN_HELP=$(BIN_DIR)/help_center
CFLAGS=-fobjc-arc -framework Cocoa -framework Foundation

all: $(BIN_CONFIG) $(BIN_ICONS) $(BIN_HELP)

$(BIN_CONFIG): $(SRC_CONFIG)
	mkdir -p $(BIN_DIR)
	clang $(CFLAGS) $(SRC_CONFIG) -o $(BIN_CONFIG)

$(BIN_ICONS): $(SRC_ICONS)
	mkdir -p $(BIN_DIR)
	clang $(CFLAGS) $(SRC_ICONS) -o $(BIN_ICONS)

$(BIN_HELP): $(SRC_HELP)
	mkdir -p $(BIN_DIR)
	clang $(CFLAGS) $(SRC_HELP) -o $(BIN_HELP)

config: $(BIN_CONFIG)

icons: $(BIN_ICONS)

help: $(BIN_HELP)

clean:
	rm -rf $(BIN_DIR)

.PHONY: all config icons help clean
