# Sync Audit — 2025-11-18

## Repository Status
- `~/Code/barista`  
  - Branch: `main` tracking `origin/main` (clean except untracked `MIGRATION_NOTES.md`).  
  - Latest fetch: `git fetch --all --prune` (completed before audit).
- `~/Code/sketchybar`  
  - Active branch: `fusion/restore-ui` (no upstream set).  
  - `git status -sb` shows large pending deletions and modifications across `components/`, `docs/`, `gui/`, `helpers/`, `modules/`, `plugins/`, `themes/`, etc., plus replacement additions like `docs/guides/TESTING_AND_VERSIONING.md`.  
  - Notable untracked artifacts: `helpers/build/`, `helpers/menu_action.c`, `stage_changes.sh`.

## Missing From `~/Code/sketchybar` vs `~/Code/barista`
Derived by comparing directory structures and key helper targets:
- Top-level: `build/`, `data/`, `profiles/`.
- GUI: `gui/config_menu_enhanced.m`, `gui/config_menu_v2.m`, `gui/bin/help_center`, `gui/bin/icon_browser`.
- Helpers: `helpers/menu_action`, `helpers/menu_renderer`, `helpers/popup_guard`, `helpers/popup_hover`, `helpers/popup_manager`, `helpers/submenu_hover`, `helpers/system_info_widget`, `helpers/space_manager`, `helpers/state_manager`, `helpers/widget_manager`.
- Modules: `modules/integrations/*`, `modules/profile.lua`, `modules/shortcuts.lua`.

These paths exist in `~/Code/barista` but are currently absent (deleted or missing) under `~/Code/sketchybar`, so they must be restored to achieve parity.

## Config Symlink
`ls -l ~/.config/sketchybar` → `/Users/scawful/.config/sketchybar -> /Users/scawful/Code/sketchybar`.  
The live SketchyBar setup is still bound to `~/Code/sketchybar`; do *not* switch to `~/Code/barista` until the parity work above is complete.

## Next Actions
1. Restore the missing directories/files in `~/Code/sketchybar` from the `barista` baseline.  
2. Rebuild helper binaries (`make config_enhanced icons help` and helper targets) once sources are copied.  
3. After verification, update the symlink to point at `~/Code/barista` (per `MIGRATION_NOTES.md`) and restart the launch agent.

