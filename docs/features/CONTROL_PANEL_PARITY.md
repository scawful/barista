# Control Panel & Helper Parity — 2025-11-18

## Overview
Restored the enhanced Objective-C control panel suite and the high-performance C helpers from `~/src/lab/barista` into `~/src/sketchybar` so both repositories now share the same tooling baseline.

## Actions
- `rsync -a /Users/scawful/src/barista/gui/ /Users/scawful/src/sketchybar/gui/`
  - Brings over `config_menu.m`, `config_menu_v2.m`, `config_menu_enhanced.m`, `icon_browser.m`, `help_center.m`, `gui/Makefile`, and rebuilt `gui/bin/*`.
- `rsync -a /Users/scawful/src/barista/helpers/ /Users/scawful/src/sketchybar/helpers/`
  - Restores `menu_action.cpp`, `menu_renderer.c`, `popup_*`, `space_manager.c`, `state_manager.c`, `widget_manager.c`, `system_info_widget.c`, `icon_manager.c`, etc., plus the enhanced helper `makefile`.
- Rebuilt GUI apps:
  - `cd ~/src/sketchybar/gui && make all` → regenerates `bin/config_menu`, `bin/config_menu_v2`, `bin/config_menu_enhanced`, `bin/icon_browser`, `bin/help_center`.
- Rebuilt helper binaries:
  - `cd ~/src/sketchybar/helpers && make all && make install`
  - Installs binaries to `~/.config/sketchybar/bin` (same as `~/src/sketchybar/bin` via symlink) so Lua scripts can call them with `compiled_script(...)`.

## Resulting Binaries (`~/.config/sketchybar/bin`)
- `config_menu`, `config_menu_v2`, `config_menu_enhanced`
- `icon_browser`, `help_center`
- `menu_action`, `menu_renderer`
- `popup_anchor`, `popup_hover`, `popup_manager`, `popup_guard`, `submenu_hover`
- `space_manager`, `state_manager`, `widget_manager`
- `clock_widget`, `system_info_widget`, `icon_manager`

All compiled successfully with `clang`/`clang++` (warnings remain for unused parameters in legacy widgets but match the barista build). The control panel feature set—including live appearance controls, widget configuration sliders, icon browser, and cached menu rendering—is now available inside `~/src/sketchybar`.
