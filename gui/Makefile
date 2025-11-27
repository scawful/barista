BUILD_DIR=build
BIN_DIR=bin

all:
	mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && cmake .. && make

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR)

config: all
	@echo "Config menu built in $(BIN_DIR)/config_menu"

icons: all
	@echo "Icon browser built in $(BIN_DIR)/icon_browser"

help: all
	@echo "Help center built in $(BIN_DIR)/help_center"

.PHONY: all clean config icons help
