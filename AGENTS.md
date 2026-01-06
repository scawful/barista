# Barista Agent Instructions

Bucket: **lab** (non-commercial). This repo is the source of truth for SketchyBar, yabai, and skhd integration configs.

## Source of Truth + Sync
- Edit files in this repo only; do **not** edit `~/.config/sketchybar` directly unless the user explicitly asks.
- Sync repo → runtime with `./scripts/deploy.sh` (use `--no-restart` if restarts are not desired).
- `deploy.sh` excludes runtime state (`state.json`, `icon_map.json`, `*.local.lua`); change those via the control panel or with explicit user approval.

## Shortcuts Workflow
- Update `modules/shortcuts.lua` (bindings) and `data/workflow_shortcuts.json` (help center keymap/actions).
- Regenerate skhd file: `BARISTA_CONFIG_DIR=/path/to/repo lua helpers/generate_shortcuts.lua`
- Reload skhd: `skhd --reload`
- Ensure `~/.config/skhd/skhdrc` includes `.load "/Users/<user>/.config/skhd/barista_shortcuts.conf"` (absolute path + double quotes required by skhd).

## Control Panel + Paths
- `BARISTA_CONFIG_DIR` selects the config root for the GUI and helpers.
- `BARISTA_CODE_DIR` (or `paths.code_dir` in `state.json`) controls repo paths for Yaze/Cortex/Halext/AFS.
- For source GUI builds: set `BARISTA_USE_SOURCE_GUI=1` and `BARISTA_SOURCE_DIR` to this repo.

## Menu Data
- Menu/help entries live in `data/menu_help.json` and `data/workflow_shortcuts.json`.
- Use `%CONFIG%` and `%CODE%` tokens in JSON paths; GUI helpers expand them.

## Experiments
- Use `ws fork` for experimental changes and merge only with user approval.
