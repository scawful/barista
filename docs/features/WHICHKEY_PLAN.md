# WhichKey Bottom Bar Plan

## Goals
- Present a HUD-style cheat sheet inspired by `which-key` to expose shortcuts, quick actions, and repo health directly inside Sketchybar.
- Avoid opening full-screen apps (VSCode/Parallels) for help content; lean on native macOS UI by reusing the Objective-C helpers.
- Keep data (docs/actions/keymap/repos) in a shared JSON file so Lua modules, shell scripts, and Objective-C panels stay in sync.

## Architecture
1. **Shared Data Layer** – `data/workflow_shortcuts.json` lists docs, quick actions, keymap sections, and repositories.
   - Parsed by Objective-C panels (control panel + help center) and Lua modules.
   - IDs map to selectors (for Cocoa) and action scripts (for Sketchybar plugins).
2. **WhichKey Lua Module** – new `modules/whichkey.lua` creates a center item with a popup styled as a bottom bar.
   - Sections rendered as grouped labels with key/glyph columns.
   - Uses `plugins/whichkey_action.sh` to dispatch actions (reload bar, open docs, repo focus, etc.).
3. **Repo Status Helper** – module shells out to `git` for each declared repo to show branch + dirty state badge.
4. **Objective-C Help Center** – `gui/help_center.m` shares the same JSON to present tabs for shortcuts, docs, and repo statuses.

## Open Questions / Next Iterations
- Hotkey integration: currently triggered by clicking the `?` item; skhd binding `⇧⌥⌘?` should call `sketchybar --trigger whichkey.toggle`.
- Extended repo signals: consider hooking CI/build status or `just` tasks.
- Add search/filter for docs/actions if the list grows.
