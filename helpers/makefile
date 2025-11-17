# Enhanced Makefile for C-based performance widgets and icon management

CC = clang
CXX = clang++
CFLAGS = -O2 -Wall -Wextra -framework CoreFoundation -framework IOKit
CXXFLAGS = -O2 -std=c++17 -Wall -Wextra
INSTALL_DIR = $(HOME)/.config/sketchybar/bin

# Original targets
ORIGINAL_TARGETS = clock_widget system_info_widget space_manager submenu_hover \
                   popup_anchor popup_hover popup_manager popup_guard menu_action

# New enhanced targets
NEW_TARGETS = icon_manager state_manager widget_manager menu_renderer

TARGETS = $(ORIGINAL_TARGETS) $(NEW_TARGETS)

all: $(TARGETS)

# Original programs
clock_widget: clock_widget.c
	$(CC) $(CFLAGS) -o $@ $<

system_info_widget: system_info_widget.c
	$(CC) $(CFLAGS) -o $@ $<

space_manager: space_manager.c
	$(CC) $(CFLAGS) -o $@ $<

submenu_hover: submenu_hover.c
	$(CC) $(CFLAGS) -o $@ $<

popup_anchor: popup_anchor.c
	$(CC) $(CFLAGS) -o $@ $<

popup_hover: popup_hover.c
	$(CC) $(CFLAGS) -o $@ $<

popup_manager: popup_manager.c
	$(CC) $(CFLAGS) -o $@ $<

popup_guard: popup_guard.c
	$(CC) $(CFLAGS) -o $@ $<

menu_action: menu_action.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

# New enhanced programs
icon_manager: icon_manager.c
	$(CC) $(CFLAGS) -o $@ $<

state_manager: state_manager.c
	$(CC) $(CFLAGS) -lpthread -o $@ $<

widget_manager: widget_manager.c
	$(CC) $(CFLAGS) -lpthread -o $@ $<

menu_renderer: menu_renderer.c
	$(CC) $(CFLAGS) -o $@ $<

install: $(TARGETS)
	mkdir -p $(INSTALL_DIR)
	@echo "Installing original components..."
	install -m 755 clock_widget $(INSTALL_DIR)/
	install -m 755 system_info_widget $(INSTALL_DIR)/
	install -m 755 space_manager $(INSTALL_DIR)/
	install -m 755 submenu_hover $(INSTALL_DIR)/
	install -m 755 popup_anchor $(INSTALL_DIR)/
	install -m 755 popup_hover $(INSTALL_DIR)/
	install -m 755 popup_manager $(INSTALL_DIR)/
	install -m 755 popup_guard $(INSTALL_DIR)/
	install -m 755 menu_action $(INSTALL_DIR)/
	@echo "Installing enhanced components..."
	install -m 755 icon_manager $(INSTALL_DIR)/
	install -m 755 state_manager $(INSTALL_DIR)/
	install -m 755 widget_manager $(INSTALL_DIR)/
	install -m 755 menu_renderer $(INSTALL_DIR)/
	@echo ""
	@echo "=== Installation Complete ==="
	@echo ""
	@echo "Enhanced C components installed to $(INSTALL_DIR)"
	@echo ""
	@echo "New features available:"
	@echo "  • icon_manager    - Fast icon lookups and management"
	@echo "  • state_manager   - Shared memory state with real-time updates"
	@echo "  • widget_manager  - High-performance widget updates and daemon mode"
	@echo "  • menu_renderer   - Cached menu rendering with batch operations"
	@echo ""
	@echo "To use the new components:"
	@echo "  1. Initialize state: $(INSTALL_DIR)/state_manager init"
	@echo "  2. Start widget daemon: $(INSTALL_DIR)/widget_manager daemon &"
	@echo "  3. Update your main.lua to use the new C APIs"
	@echo ""

clean:
	rm -f $(TARGETS)

# Development targets
test: $(TARGETS)
	@echo "Testing icon manager..."
	./icon_manager categories
	@echo ""
	@echo "Testing state manager..."
	./state_manager init
	./state_manager stats
	@echo ""
	@echo "Testing widget manager..."
	./widget_manager stats
	@echo ""
	@echo "Tests complete!"

.PHONY: all install clean test
