# Barista ☕️

**The Cozy macOS Status Bar.**

Barista is a curated configuration for [SketchyBar](https://github.com/FelixKratz/SketchyBar) that balances aesthetics with power-user features. It is designed to be shared, easy to install, and configurable for different environments (Work vs. Home).

![Barista Preview](docs/assets/preview.png)

## Features

- **Dynamic Island**: Context-aware popups for volume, brightness, and music.
- **Profiles**: Switch between "Work", "Personal", and "Cozy" modes instantly.
- **Integrations**: Optional support for Yabai (tiling) and Skhd (hotkeys).
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

## Customization

### Switching Profiles
```bash
# Switch to Cozy mode
./scripts/set_mode.sh girlfriend disabled

# Switch to Work mode
./scripts/set_mode.sh work required
```

### Configuration
Edit `~/.config/sketchybar/state.json` to toggle specific widgets or change colors without touching Lua code.

```json
{
  "profile": "minimal",
  "widgets": {
    "battery": true,
    "wifi": false
  }
}
```

## Troubleshooting

- **Bar not showing?** Run `sketchybar --reload`.
- **Icons missing?** Ensure you installed the Nerd Fonts prompted by the installer.
- **Yabai acting weird?** Check `System Settings > Privacy & Security > Accessibility`.

---
*Maintained by Scawful. Part of the Halext ecosystem.*
