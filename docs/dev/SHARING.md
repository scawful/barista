# Sharing This Sketchybar Setup

## Goals
- Keep the core layout and customization tooling you use every day.
- Let another person (e.g. a partner) install the bar on their Mac without the ROM-hacking/Emacs specific workflows.
- Provide clear onboarding steps plus a switch to re-enable your heavy integrations when you need them.

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
5. **Apply the shared profile** (disables ROM hacking + Emacs integrations and keeps spaces floating by default):
   ```sh
   cd ~/src/sketchybar
   ./bin/apply_profile.sh shared
   ```
6. Launch Sketchybar (or `sketchybar --reload`). The control panel now exposes the same customization options without the Zelda-specific menu items.

## Toggling Integrations Later
- To re-enable everything on your own machine, run `./bin/apply_profile.sh full`.
- Inside the GUI control panel, the *Integration Status* box now has switches for **Enable Yaze** and **Enable Emacs** so you can flip them on/off without editing config files.
- The helper script behind the scenes (`plugins/set_integration_enabled.sh`) updates `state.json` and tells Sketchybar to refresh immediately.

## Customization Notes for New Users
- **Docs + Actions**: edit `data/workflow_shortcuts.json` to point to your own org files, quick actions, and repo list. Those entries feed the control panel, the WhichKey HUD, and the new Help Center.
- **Help Center**: run `gui/bin/help_center` for a native macOS window that lists shortcuts, quick actions, and repo statuses. Nothing opens Parallels/VSCode automatically anymore.
- **Space Behavior**: spaces default to floating windows unless you explicitly pick BSP/Stack from the Yabai widget popup or via `set_space_mode.sh`. That keeps macOS feeling native for users who don’t want tiling.

## Sharing Tips
- Keep personal scripts (Yaze build helpers, Emacs workflow notes, etc.) out of the shared profile by default. Use the integration toggles if/when she wants to explore them.
- Encourage customizing the *Workflow Shortcuts* box and WhichKey HUD so her favorite apps / repos appear first.
- If she creates her own profile, `bin/apply_profile.sh` can be extended with more cases—e.g. `./bin/apply_profile.sh design` to toggle different integrations/colors.
