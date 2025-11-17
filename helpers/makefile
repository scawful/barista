# Makefile for C-based performance widgets

CC = clang
CXX = clang++
CFLAGS = -O2 -Wall -Wextra
CXXFLAGS = -O2 -std=c++17 -Wall -Wextra
INSTALL_DIR = $(HOME)/.config/sketchybar/bin

TARGETS = clock_widget system_info_widget space_manager submenu_hover popup_anchor popup_hover popup_manager popup_guard menu_action

all: $(TARGETS)

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

install: $(TARGETS)
	mkdir -p $(INSTALL_DIR)
	install -m 755 clock_widget $(INSTALL_DIR)/
	install -m 755 system_info_widget $(INSTALL_DIR)/
	install -m 755 space_manager $(INSTALL_DIR)/
	install -m 755 submenu_hover $(INSTALL_DIR)/
	install -m 755 popup_anchor $(INSTALL_DIR)/
	install -m 755 popup_hover $(INSTALL_DIR)/
	install -m 755 popup_manager $(INSTALL_DIR)/
	install -m 755 popup_guard $(INSTALL_DIR)/
	install -m 755 menu_action $(INSTALL_DIR)/
	@echo "C widgets and tools installed to $(INSTALL_DIR)"
	@echo "Update your main.lua to use:"
	@echo "  - $(INSTALL_DIR)/clock_widget"
	@echo "  - $(INSTALL_DIR)/system_info_widget"
	@echo "  - $(INSTALL_DIR)/popup_hover"
	@echo "  - $(INSTALL_DIR)/popup_manager (for global popup dismissal)"
	@echo "  - $(INSTALL_DIR)/space_manager (for fast space operations)"

clean:
	rm -f $(TARGETS)

.PHONY: all install clean
