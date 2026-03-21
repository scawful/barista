# Barista ☕️

**The Cozy macOS Status Bar.**

Barista is a curated configuration for [SketchyBar](https://github.com/FelixKratz/SketchyBar) that balances aesthetics with power-user features. It is designed to be shared, easy to install, and configurable for different environments (Work vs. Home).

## Features

- **Dynamic Island**: Context-aware popups for volume, brightness, and music.
- **Profiles**: Switch between "Work", "Personal", and "Cozy" modes instantly.
- **Modular Architecture**: Lua-based configuration system decomposed for high performance and testability.
- **Integrations**: Optional support for Yabai (tiling), Skhd (hotkeys), Journal (org-mode capture/inbox), NERV (transfer queue + host monitoring), and Halext-org (task dashboard). Integrations are toggled per profile.

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
Install missing fonts, repair `state.json` to match available families, and set a preferred alternate control panel mode:

```bash
./scripts/install_missing_fonts_and_panel.sh --yes --panel-mode tui
```

For managed/work Macs that should avoid compiled helpers entirely:

```bash
./scripts/setup_machine.sh --yes --panel-mode tui --runtime-backend lua
./scripts/barista-debug.sh --lua-only --reload
```

See [docs/guides/WORK_MACHINE_GEMINI.md](docs/guides/WORK_MACHINE_GEMINI.md) for the Gemini-first upgrade flow.

### Update Another Mac
Push the latest repo changes to a remote Mac and apply work profile extras:

```bash
./scripts/update_work_mac.sh \
  --host user@work-mac.local \
  --target origin/main \
  --work-domain yourcompany.com \
  --panel-mode tui \
  --runtime-backend lua
```

- **Hover animation:** In `state.json` or in `modules/state.lua` defaults, `hover_animation_duration` (default 8) and `hover_animation_curve` (default `sin`) control popup hover speed. Lower duration (e.g. 6) for even snappier feel.
- **Process Batching:** Barista minimizes process forks. Space switching uses a batched diff-update path (40+ forks reduced to 1). C helpers like `system_info_widget` batch multiple updates into a single call.
- **Direct Execution:** Hot-path C helpers use `execlp()` instead of `system()` to eliminate shell overhead and unnecessary forks.
- **Modular Load:** Configuration logic is split across focused modules (`shell_utils`, `paths`, `binary_resolver`) to ensure fast initialization.
- **Tuning:** See [docs/PERFORMANCE_AUDIT.md](docs/PERFORMANCE_AUDIT.md) for a stability/performance checklist and detailed audit results.

## Testing

Barista includes a comprehensive test suite of **94+ tests** across its Lua modules.

```bash
./scripts/barista-verify.sh          # Full smoke test (binaries, shell, lua)
lua tests/run_tests.lua              # Run Lua unit tests only
./scripts/rebuild.sh --verify       # Rebuild all and run tests
```

## Troubleshooting

- **Bar not showing?** Run `sketchybar --reload`.
- **Icons missing?** Run `./scripts/barista-fonts.sh --apply-state --report` and re-run `./scripts/barista-doctor.sh --fix`.
- **Need to debug without C/C++ helpers?** Run `./scripts/barista-debug.sh --lua-only --reload`.
- **Yabai acting weird?** Check `System Settings > Privacy & Security > Accessibility`.

---
*Maintained by Scawful. Part of the Halext ecosystem.*
