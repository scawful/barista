# Sharing This Sketchybar Setup

## Goals
- Keep the core layout and customization tooling you use every day.
- Support another Mac without ROM-hacking/Emacs specific workflows.
- Provide clear onboarding steps plus a switch to re-enable heavy integrations when you need them.

## Installation Flow (New Mac)
1. **Clone the repo** somewhere convenient (e.g. `~/src/sketchybar`).
2. **Install prerequisites** if missing: Homebrew, `sketchybar`, `jq`, and your preferred font (`Hack Nerd Font`).
3. **Link/copy the config** into place:
   ```sh
   mkdir -p ~/.config
   ln -s ~/src/sketchybar ~/.config/sketchybar
   ```
   (Or copy instead of symlink if you prefer.)
4. **Build the GUI tools** (optional but recommended):
   ```sh
   cd ~/src/sketchybar/gui
   make
   ```
5. **Apply the minimal machine variant** (disables ROM hacking + Emacs integrations and keeps window management optional):
   ```sh
   cd ~/src/sketchybar
   ./scripts/setup_machine.sh --profile-variant minimal --skip-fonts --skip-panel --yes
   ```
6. Launch Sketchybar (or `sketchybar --reload`). The control panel now exposes the same customization options without the Zelda-specific menu items.

## Toggling Integrations Later
- To re-enable everything on your own machine, run `./scripts/setup_machine.sh --profile-variant personal --skip-fonts --skip-panel --yes`.
- Inside the GUI control panel, the *Integration Status* box now has switches for **Enable Yaze** and **Enable Emacs** so you can flip them on/off without editing config files.
- The helper script behind the scenes (`plugins/set_integration_enabled.sh`) updates `state.json` and tells Sketchybar to refresh immediately.

## Customization Notes for New Users
- **Docs + Actions**: edit `data/workflow_shortcuts.json` to point to your own org files, quick actions, and repo list. Those entries feed the control panel and the Help Center.
- **Help Center**: run `gui/bin/help_center` for a native macOS window that lists shortcuts, quick actions, and repo statuses. Nothing opens Parallels/VSCode automatically anymore.
- **Space Behavior**: spaces default to floating windows unless you explicitly pick BSP/Stack from the Yabai widget popup or via `set_space_mode.sh`. That keeps macOS feeling native for users who don’t want tiling.

## Sharing Tips
- Keep personal scripts (Yaze build helpers, Emacs workflow notes, etc.) out of shared/minimal variants by default. Use integration toggles when that machine needs more.
- Customize the *Workflow Shortcuts* box and Apple Menu tools so the target Mac's apps and repos appear first.
- If a new profile is needed, add `profiles/<name>.lua` and apply it with `scripts/set_mode.sh <name>`.
