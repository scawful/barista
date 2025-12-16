# Barista Update Guide

Keep Barista current with safe backups and minimal downtime. Choose the path that matches how you installed it.

## Quick Commands
- Homebrew: `brew upgrade barista && ~/.config/sketchybar/helpers/post_update.sh && ~/.config/sketchybar/launch_agents/barista-launch.sh restart`
- Git clone: `~/.config/sketchybar/bin/barista-update`
- Skip restarts (corporate): `BARISTA_SKIP_RESTART=1 ~/.config/sketchybar/bin/barista-update`

## What `barista-update` Does (Git installs)
- Backs up `state.json`, `profiles/`, and `themes/` to `~/.config/sketchybar.backup.<timestamp>`
- Fetches `${BARISTA_REMOTE:-origin}/${BARISTA_BRANCH:-main}` and merges safely
- Rebuilds helpers/GUI with CMake when available
- Runs `helpers/migrate.sh` and `helpers/post_update.sh` if present
- Restarts SketchyBar, yabai, and skhd via `launch_agents/barista-launch.sh` (falls back to `brew services`), unless `BARISTA_SKIP_RESTART=1`

## Homebrew Workflow
1) Upgrade: `brew upgrade barista`
2) Sync config: `~/.config/sketchybar/helpers/post_update.sh`
3) Restart services:
   - Preferred: `~/.config/sketchybar/launch_agents/barista-launch.sh restart`
   - Fallback: `brew services restart sketchybar` (and `yabai`/`skhd` if used)

## Git Clone Workflow
1) Update: `~/.config/sketchybar/bin/barista-update`
   - Use `BARISTA_REMOTE` / `BARISTA_BRANCH` to track a fork or branch
   - Use `BARISTA_SKIP_RESTART=1` if restarts are blocked on corporate laptops
2) Verify: `sketchybar --reload` (also `yabai -m query --spaces` / `skhd --reload` if running)

## Recovery
- Backups live at `~/.config/sketchybar.backup.<timestamp>`
- Restore example: `cp -r ~/.config/sketchybar.backup.20250101_120000/* ~/.config/sketchybar/`

## Work Laptop Notes (Google)
- Run behind VPN/proxy if needed; the updater only hits Git remotes and Homebrew
- If IT tools manage services, set `BARISTA_SKIP_RESTART=1` and restart via company tooling after the update
