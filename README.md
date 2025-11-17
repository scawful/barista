# ☕ barista

> *Brewing the perfect macOS status bar experience*

A powerful, modular, and portable SketchyBar configuration with native macOS control panel, performance optimizations, and extensible integration system.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![SketchyBar](https://img.shields.io/badge/SketchyBar-2.20%2B-green)](https://github.com/FelixKratz/SketchyBar)

## ✨ Features

### 🎨 Native Control Panel
- **6 Specialized Tabs**: Appearance, Widgets, Spaces, Icons, Integrations, Advanced
- **Live Preview**: See changes before applying
- **Native macOS UI**: Built with Cocoa for perfect integration
- **Persistent App**: Stays in Dock, accessible via Shift+Click Apple menu

### ⚡ Performance Optimizations
- **C/C++ Helpers**: 10-50x faster than shell scripts
- **Batched Commands**: Single IPC calls for multiple operations
- **Smart Caching**: 5-minute TTL for external integrations
- **Zero-Latency Feedback**: Instant visual responses

### 🎨 Advanced Icon & Shortcut Management
- **Multi-Font Icon System**: Automatic fallback between Hack Nerd Font, SF Symbols, SF Pro
- **Font-Agnostic**: Icons work regardless of installed fonts
- **Centralized Management**: One place to manage all icons
- **Non-Conflicting Shortcuts**: Using ctrl+alt combinations that don't interfere with apps
- **fn Key Support**: Future-ready for fn-key combinations (macOS Ventura+)
- **19 Global Shortcuts**: Pre-configured, conflict-free keyboard shortcuts

### 🔧 Modular Architecture
- **Profile System**: Easy switching between personal, work, and custom setups
- **Lua Modules**: Clean, maintainable code structure
- **6 Coffee Themes**: Caramel, White Coffee, Chocolate, Mocha, plus Strawberry Matcha
- **Theme Support**: Catppuccin Mocha default, easily customizable
- **State Management**: Centralized JSON-based configuration

### 🔌 Extensible Integrations
- **Yaze** (ROM Hacking): Launch editor, browse ROMs, workflow documentation
- **Emacs**: Org-mode integration, workspace management
- **halext-org**: Task management, calendar, LLM suggestions (ready for future)
- **Easy to Add**: Template system for custom integrations

### 📱 70+ Menu Actions
- System controls (sleep, lock, force quit)
- Window management (float, sticky, fullscreen, move to space/display)
- Yabai controls (layout modes, space operations)
- App launchers and dev utilities
- Comprehensive keyboard shortcuts

## 🚀 Quick Start

### Prerequisites

- macOS 13+ (Ventura or later)
- [SketchyBar](https://github.com/FelixKratz/SketchyBar) 2.20+
- [Homebrew](https://brew.sh/)
- Lua 5.4+ (installed via Homebrew)

**Optional but Recommended**:
- [Yabai](https://github.com/koekeishiya/yabai) (tiling window manager)
- [skhd](https://github.com/koekeishiya/skhd) (hotkey daemon)
- [Nerd Font](https://www.nerdfonts.com/) (for icons)

### Installation

```bash
# One-command install
curl -fsSL https://raw.githubusercontent.com/scawful/barista/master/install.sh | bash

# Or clone and install manually
git clone https://github.com/scawful/barista ~/.config/sketchybar
cd ~/.config/sketchybar
./install.sh
```

The installer will:
1. Check and install dependencies
2. Backup existing configuration
3. Build C helpers and GUI tools
4. Let you choose a profile (minimal, personal, work, custom)
5. Start SketchyBar

### First Steps

After installation:

1. **Access Control Panel**: `Shift + Click` the Apple menu icon
2. **Customize Appearance**: Navigate to Appearance tab
3. **Enable Widgets**: Toggle widgets in Widgets tab
4. **Set Space Icons**: Customize space icons in Spaces tab
5. **Configure Integrations**: Setup external services in Integrations tab

## 📚 Documentation

- **[Control Panel Guide](docs/CONTROL_PANEL_V2.md)**: Complete GUI documentation
- **[Icons & Shortcuts](docs/ICONS_AND_SHORTCUTS.md)**: Icon management and keyboard shortcuts
- **[Themes Guide](docs/THEMES.md)**: Available themes and customization
- **[License Analysis](docs/LICENSE_ANALYSIS.md)**: Commercial use and licensing details
- **[Improvements Overview](docs/IMPROVEMENTS.md)**: Architecture and performance details
- **[Troubleshooting](docs/TROUBLESHOOTING.md)**: Common issues and solutions

## 🎭 Profiles

Choose a profile during installation or switch anytime by editing `state.json`:

### Minimal Profile (Recommended for new users)
```json
{
  "profile": "minimal"
}
```

Clean, simple setup with no integrations. Perfect starting point.

### Personal Profile
```json
{
  "profile": "personal"
}
```

Full-featured with ROM hacking (Yaze), Emacs, custom workflows.

### Work Profile
```json
{
  "profile": "work"
}
```

Work-focused with Emacs, halext-org, no personal integrations.

### Custom Profile

Create your own:
```bash
cp ~/.config/sketchybar/profiles/minimal.lua ~/.config/sketchybar/profiles/myprofile.lua
# Edit myprofile.lua
# Set "profile": "myprofile" in state.json
sketchybar --reload
```

## ☕ Themes

Barista includes 6 carefully crafted color themes inspired by coffee culture:

### Coffee Themes
- **Default** (Catppuccin Mocha): Dark purple-tinted modern theme
- **Caramel**: Warm golden browns and amber tones
- **White Coffee**: Creamy whites and light browns (flat white style)
- **Chocolate**: Rich dark browns and warm chocolatey tones
- **Mocha**: Medium browns with chocolate and coffee accents

### Specialty
- **Strawberry Matcha**: Fresh pinks and vibrant greens

### Switching Themes

Edit `theme.lua`:
```lua
local current_theme = "mocha"  -- or "caramel", "white_coffee", "chocolate", "strawberry_matcha"
local theme = require("themes." .. current_theme)
return theme
```

Then reload: `sketchybar --reload`

**📖 Full Documentation**: See [docs/THEMES.md](docs/THEMES.md) for theme details, customization, and creating your own themes.

## 📊 Performance

| Component | Shell Script | C Helper | Speedup |
|-----------|-------------|----------|---------|
| Hover highlight | 15ms | 1.5ms | **10x** |
| Submenu navigation | 25ms | 1.7ms | **15x** |
| Global dismiss | 100ms | 2ms | **50x** |
| Menu action | 40ms | 2ms | **20x** |

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create feature branch: `git checkout -b feature/my-feature`
3. Make changes and test thoroughly
4. Update documentation
5. Submit pull request

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Credits

- **[SketchyBar](https://github.com/FelixKratz/SketchyBar)** by FelixKratz
- **[Yabai](https://github.com/koekeishiya/yabai)** by koekeishiya
- **[Nerd Fonts](https://www.nerdfonts.com/)** for icons
- **[Catppuccin](https://github.com/catppuccin/catppuccin)** for the theme

---

<div align="center">

**barista** - Brewing the perfect macOS status bar ☕

Made with ❤️ for the macOS community

[Report Bug](https://github.com/scawful/barista/issues) · [Request Feature](https://github.com/scawful/barista/issues) · [Discussions](https://github.com/scawful/barista/discussions)

</div>
