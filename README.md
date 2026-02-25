# Barista ☕️

**The Cozy macOS Status Bar.**

Barista is a curated configuration for [SketchyBar](https://github.com/FelixKratz/SketchyBar) that balances aesthetics with power-user features. It is designed to be shared, easy to install, and configurable for different environments (Work vs. Home).

## Features

- **Dynamic Island**: Context-aware popups for volume, brightness, and music.
- **Profiles**: Switch between "Work", "Personal", and "Cozy" modes instantly.
- **Integrations**: Optional support for Yabai (tiling), Skhd (hotkeys), Journal (org-mode capture/inbox), NERV (transfer queue + host monitoring), and Halext-org (task dashboard). Integrations are toggled per profile.
- **Extensible**: Lua-based configuration system.

## Quick Install

To install Barista and its dependencies:

```bash
# Clone the repo
git clone https://github.com/scawful/barista.git ~/.local/share/barista

# Run the installer
~/.local/share/barista/scripts/install.sh
```

The installer will guide you through:
1. Installing dependencies (SketchyBar, Lua, Fonts).
2. Choosing a **Profile** (see below).
3. Configuring **Yabai/Skhd** (optional).

## Profiles

| Profile | Description | Yabai | Vibe |
| :--- | :--- | :--- | :--- |
| **Minimal** | Clean, distraction-free. Good for new users. | Optional | ⚪️ Clean |
| **Girlfriend** | Warm colors, larger text, simplified metrics. No scary tiling. | **Disabled** | 🧸 Cozy |
| **Work** | High info density, meeting indicators, calendar integration. | Required | 💼 Pro |
| **Personal** | The default dev setup. Code, media, and tiling. | Required | ⚡️ Fast |

## Window Management (Yabai)

Barista includes optimized configurations for **Yabai** (window manager) and **Skhd** (hotkeys).
The installer can automatically set these up for you.

- **Enable**: Run installer and select "Window Manager Mode: Required".
- **Disable**: Run `./scripts/set_mode.sh <profile> disabled`.

## Source universe: runtime and overlay

**Recommended:** Make the SketchyBar runtime a symlink to the Barista repo so edits are live:

```bash
# If ~/.config/sketchybar already exists, back it up first
mv ~/.config/sketchybar ~/.config/sketchybar.bak
ln -s ~/src/lab/barista ~/.config/sketchybar
```

**Personal overlay:** For per-machine additions (e.g. Oracle of Secrets integration, workflow shortcuts), use the overlay in `~/src/config/dotfiles/sketchybar-overlay/`. Apply it with:
`~/src/config/dotfiles/scripts/apply_sketchybar_overlay.sh`
Optionally pass the target dir (default: `~/.config/sketchybar`). If the runtime is a symlink to lab/barista, the overlay is written into the repo. See `config/dotfiles/sketchybar-overlay/README.md`.

**Skhd and yabai_control:** Space/layout keybindings in skhd call `yabai_control.sh`. To support both "Barista deploy" and "dotfiles-only" setups, use the wrapper: `~/.local/bin/yabai_control_wrapper.sh` (from `config/dotfiles/bin/yabai_control_wrapper.sh`). Ensure that wrapper is on your PATH and installed (e.g. dotfiles link `bin/` to `~/.local/bin`).

**LaunchAgents:** The single place to edit the Barista orchestrator (SketchyBar + yabai + skhd at login) is `lab/barista/launch_agents/`. See [launch_agents/README.md](launch_agents/README.md). Recommended: use either this LaunchAgent or `brew services` for the three daemons, not both.

## Customization

### Switching Profiles
```bash
# Switch to Cozy mode
./scripts/set_mode.sh girlfriend disabled

# Switch to Work mode
./scripts/set_mode.sh work required
```

### Configuration
Edit `~/.config/sketchybar/state.json` to toggle widgets and appearance, or use `barista_config.lua` for overrides that survive the GUI. See [docs/guides/CUSTOMIZATION.md](docs/guides/CUSTOMIZATION.md) for state.json, profiles, themes, and fonts; [docs/architecture/SKETCHYBAR_LAYOUT.md](docs/architecture/SKETCHYBAR_LAYOUT.md) for which file defines each bar item. To validate theme files: `lua scripts/validate_theme.lua [theme_name]`.

```json
{
  "profile": "minimal",
  "widgets": {
    "battery": true,
    "wifi": false
  }
}
```

### Work Google Apps Menu
Populate customizable Work Google app entries in the Apple menu:

```bash
# Use defaults
./scripts/configure_work_google_apps.sh --replace

# Use workspace domain routes
./scripts/configure_work_google_apps.sh --domain yourcompany.com --replace

# Use custom app list
./scripts/configure_work_google_apps.sh --from-file ./data/work_google_apps.example.json --replace
```

### Fonts + Alternate Panel
Install missing fonts and set a preferred alternate control panel mode:

```bash
./scripts/install_missing_fonts_and_panel.sh --yes --panel-mode tui
```

### Update Another Mac
Push the latest repo changes to a remote Mac and apply work profile extras:

```bash
./scripts/update_work_mac.sh \
  --host user@work-mac.local \
  --target origin/main \
  --work-domain yourcompany.com \
  --panel-mode tui
```

## Performance

- **Hover animation:** In `state.json` or in `modules/state.lua` defaults, `hover_animation_duration` (default 8) and `hover_animation_curve` (default `sin`) control popup hover speed. Lower duration (e.g. 6) for even snappier feel.
- **Heavy menus:** If a menu is slow to open, check the integration module (e.g. `modules/integrations/*.lua`) and any scripts run on open; add caching or lazy loading. Prefer C/Lua for hot paths; avoid long shell commands on every bar update.
- **Tuning:** See `docs/workflow/HANDOFF_SOURCE_UNIVERSE_CLI_AGENT.md` for a stability/performance checklist and where to look (menu_renderer, popup_hover, state.lua).

## Troubleshooting

- **Bar not showing?** Run `sketchybar --reload`.
- **Icons missing?** Ensure you installed the Nerd Fonts prompted by the installer.
- **Yabai acting weird?** Check `System Settings > Privacy & Security > Accessibility`.

---
*Maintained by Scawful. Part of the Halext ecosystem.*
