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

### 🔧 Modular Architecture
- **Profile System**: Easy switching between personal, work, and custom setups
- **Lua Modules**: Clean, maintainable code structure
- **Theme Support**: Catppuccin Mocha included, easily customizable
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
