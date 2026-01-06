# Migration Guide: Objective-C Control Panel → barista_config (C++ ImGui)

**Last Updated:** 2026-01-01
**Status:** Planning Phase
**Target Date:** April 2026

## Overview

This guide outlines the migration from barista's native Objective-C control panel to the new cross-platform `barista_config` tool built with C++ and ImGui (halext::gui framework).

**Why Migrate?**
- **Cross-platform:** Works on macOS, Linux, and Windows
- **Modern UI:** ImGui provides more flexibility and customization
- **Halext Ecosystem:** Integrates with other halext tools
- **Maintainability:** Easier to extend and contribute to
- **Performance:** Lighter weight than full Cocoa application
- **Unified Codebase:** Single C++ codebase instead of Objective-C + Lua

---

## Feature Comparison Table

| Feature | Objective-C Panel | barista_config | Status |
|---------|------------------|----------------|--------|
| **Appearance** | | | |
| Bar height slider | ✅ 20-50px | ✅ 0-60px | Complete |
| Corner radius slider | ✅ 0-16px | ✅ 0-30px | Complete |
| Blur radius slider | ✅ 0-80px | ✅ 0-100px | Complete |
| Widget scale slider | ✅ 0.85-1.25x | ✅ 0.5-2.0x | Complete |
| Bar color picker | ✅ Visual + hex | ✅ Visual + hex | Complete |
| Color presets | ❌ | ✅ Catppuccin, Nord, Dracula | Complete |
| Live preview | ✅ | ⏳ Planned | Pending |
| | | | |
| **Widgets** | | | |
| Toggle widget visibility | ✅ Clock, Battery, etc. | ⏳ Planned | Pending |
| Per-widget colors | ✅ | ⏳ Planned | Pending |
| Per-widget scale | ❌ | ⏳ Planned | Pending |
| Update interval | ❌ | ⏳ Planned | Pending |
| Reorder widgets | ❌ | ⏳ Planned | Pending |
| | | | |
| **Spaces** | | | |
| Per-space icons | ✅ 1-10 spaces | ⏳ Planned | Pending |
| Layout modes | ✅ BSP, Stack, Float | ⏳ Planned | Pending |
| Space naming | ❌ | ⏳ Planned | Pending |
| | | | |
| **Icons** | | | |
| Icon browser | ✅ 40+ icons | ✅ Expandable | In Progress |
| Search/filter | ✅ | ✅ | Complete |
| Categories | ✅ | ✅ | Complete |
| One-click copy | ✅ | ❌ | Pending |
| Visual preview | ✅ Large glyph | ✅ Grid view | Complete |
| Custom icons | ❌ | ⏳ Planned | Pending |
| | | | |
| **Integrations** | | | |
| Yaze integration | ✅ | ⏳ Planned | Pending |
| Emacs integration | ✅ | ⏳ Planned | Pending |
| halext-org (future) | ✅ UI ready | ⏳ Planned | Pending |
| Cortex integration | ❌ | ⏳ Planned | Pending |
| | | | |
| **Advanced** | | | |
| Raw JSON editor | ✅ | ⏳ Planned | Pending |
| Syntax highlighting | ✅ | ⏳ Planned | Pending |
| Backup/restore | ⏳ Planned | ⏳ Planned | Both pending |
| Scripts directory override | ✅ | ⏳ Planned | Pending |
| | | | |
| **Platform** | | | |
| macOS support | ✅ | ✅ | Complete |
| Linux support | ❌ | ✅ | Complete |
| Windows support | ❌ | ✅ (planned) | Pending |
| | | | |
| **Architecture** | | | |
| Language | Objective-C | C++17 | ✅ |
| Framework | Cocoa | ImGui | ✅ |
| Persistent app | ✅ Dock app | ❌ Standalone | Different |
| Always on top | ✅ | ✅ | Complete |
| Multi-space aware | ✅ | ⏳ Planned | Pending |

**Legend:**
- ✅ Complete
- ⏳ Planned
- ❌ Not available

---

## Migration Timeline

### Phase 1: Foundation (Complete ✅)
**Timeline:** Dec 2025
**Status:** Complete

- [x] Project structure created
- [x] ConfigManager implemented
- [x] Basic window with sidebar navigation
- [x] Integration with halext::gui framework
- [x] Appearance view (complete feature parity)

### Phase 2: Core Features (Jan 2026)
**Timeline:** Weeks 1-4
**Status:** In Progress

- [ ] Widgets view (toggle, colors, scale)
- [ ] Icons view (browser integration, assignment)
- [ ] Integrations view (Yaze, Emacs, halext-org)
- [ ] Live preview (if feasible)

### Phase 3: Advanced Features (Feb 2026)
**Timeline:** Weeks 1-4
**Status:** Planned

- [ ] Spaces view (per-space configuration)
- [ ] Raw JSON editor (advanced tab)
- [ ] Export/import configurations
- [ ] Undo/redo system

### Phase 4: Polish & Testing (Mar 2026)
**Timeline:** Weeks 1-4
**Status:** Planned

- [ ] User testing with 5+ beta testers
- [ ] Bug fixes and refinements
- [ ] Documentation completion
- [ ] Migration scripts

### Phase 5: Deployment (Apr 2026)
**Timeline:** Weeks 1-2
**Status:** Planned

- [ ] barista_config becomes default
- [ ] Objective-C panel deprecated
- [ ] Release notes and migration guide
- [ ] Support for rollback if issues arise

---

## Step-by-Step Migration Process

### For Users

#### Step 1: Install barista_config
```bash
# From barista directory
cd ~/src/lab/barista_config
mkdir build && cd build
cmake ..
make
sudo make install  # Installs to ~/.local/bin
```

Alternatively, use the `ws` tool:
```bash
ws build barista_config
ws install barista_config
```

#### Step 2: Launch for First Time
```bash
barista_config
```

Or from cortex menu (if integrated):
- Click cortex icon
- Select "SketchyBar Config"

#### Step 3: Verify Configuration Loaded
The app should automatically load your existing configuration from:
```
~/.config/sketchybar/state.json
```

If the file doesn't exist, default settings will be used.

#### Step 4: Test Basic Functionality
1. Navigate to Appearance tab
2. Adjust bar height
3. Click "Apply"
4. Verify SketchyBar reloads correctly

#### Step 5: Explore New Features
- Try color presets (Catppuccin, Nord, Dracula)
- Browse the icon library
- Configure widgets (once implemented)

#### Step 6: Report Issues
If you encounter problems:
1. Check logs: `~/.config/barista_config/logs/`
2. Open issue on GitHub
3. Rollback if needed (see below)

---

### For Developers

#### Step 1: Understand Architecture Differences

**Objective-C Panel:**
```objc
// Old: AppDelegate.m
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTabView *tabView;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  [self setupWindow];
  [self loadState];
}
@end
```

**barista_config (C++ ImGui):**
```cpp
// New: app.cc
class BaristaConfigApp : public halext::gui::Application {
public:
  BaristaConfigApp() : Application("Barista Config", 1280, 720) {}

  void OnStart() override {
    halext::gui::ApplyTheme(halext::gui::ThemeProfile::Catppuccin);
    config_manager_.Load();
  }

  void OnRender() override {
    RenderSidebar();
    RenderActiveView();
  }

private:
  ConfigManager config_manager_;
};
```

#### Step 2: Map Existing Features

| Objective-C Component | barista_config Equivalent |
|-----------------------|---------------------------|
| `AppDelegate.m` | `app.cc` (Application class) |
| `AppearanceViewController.m` | `views/appearance.cc` |
| `WidgetsViewController.m` | `views/widgets.cc` |
| `IconsViewController.m` | `views/icons.cc` |
| `state.json` reading | `ConfigManager::Load()` |
| `state.json` writing | `ConfigManager::Save()` |
| Color picker (NSColorPanel) | `halext::widgets::ColorPicker` |
| Icon grid (NSCollectionView) | `halext::widgets::IconBrowser` |

#### Step 3: Port View Logic

**Example: Appearance View**

Old (Objective-C):
```objc
// AppearanceViewController.m
- (IBAction)barHeightChanged:(NSSlider *)sender {
  float height = [sender floatValue];
  [self updateBarHeight:height];
  [self reloadSketchyBar];
}
```

New (C++):
```cpp
// views/appearance.cc
void RenderAppearanceView(ConfigManager& config) {
  int height = config.GetInt("bar.height", 32);

  if (ImGui::SliderInt("Bar Height", &height, 0, 60)) {
    config.SetInt("bar.height", height);
  }

  if (ImGui::Button("Apply")) {
    config.Save();
    ReloadSketchyBar();
  }
}
```

#### Step 4: Test Parity
For each feature:
1. Test in Objective-C panel
2. Test in barista_config
3. Verify same result in `state.json`
4. Verify SketchyBar applies changes correctly

#### Step 5: Document Differences
Update this guide with any differences found:
- Behavioral changes
- UI/UX differences
- Performance comparisons

---

## Configuration File Format

Both panels use the same `state.json` format, ensuring seamless compatibility:

**Location:** `~/.config/sketchybar/state.json`

**Example:**
```json
{
  "profile": "personal",
  "appearance": {
    "theme": "catppuccin",
    "bar_height": 32,
    "corner_radius": 10,
    "blur_radius": 20,
    "widget_scale": 1.0,
    "bar_color": "0xC0181825"
  },
  "widgets": {
    "clock": { "enabled": true, "color": "0xFFCDD6F4" },
    "battery": { "enabled": true, "color": "0xFFA6E3A1" },
    "network": { "enabled": true, "color": "0xFF89B4FA" }
  },
  "integrations": {
    "yaze": {
      "enabled": true,
      "build_dir": "~/src/hobby/yaze/build"
    },
    "emacs": {
      "enabled": true,
      "workspace": "~/src"
    }
  }
}
```

**Important:** Both applications read and write to the same file, so you can switch between them without losing settings.

---

## Rollback Instructions

If you need to revert to the Objective-C panel:

### Option 1: Keep Both Installed
```bash
# Launch Objective-C panel
open ~/.config/sketchybar/gui/SketchyBarControlPanel.app

# Or launch barista_config
barista_config
```

Both tools can coexist. Just don't run them simultaneously.

### Option 2: Uninstall barista_config
```bash
# Remove barista_config binary
rm ~/.local/bin/barista_config

# Remove config (optional)
rm -rf ~/.config/barista_config
```

Your `state.json` remains intact, so the Objective-C panel will work as before.

### Option 3: Restore Backup
If you made a backup before migrating:
```bash
# Restore state.json backup
cp ~/.config/sketchybar/state.json.backup ~/.config/sketchybar/state.json

# Reload SketchyBar
sketchybar --reload
```

---

## Deprecation Timeline

### January 2026: Beta Testing
- barista_config released as beta
- Objective-C panel remains default
- Users invited to test and provide feedback

### February 2026: Public Announcement
- Announce deprecation of Objective-C panel
- Document migration path
- Encourage users to switch

### March 2026: Transition Period
- barista_config becomes recommended option
- Objective-C panel still available
- Both maintained for bug fixes

### April 2026: barista_config Becomes Default
- barista_config installed by default
- Objective-C panel moved to `legacy/` directory
- No new features for Objective-C panel

### May 2026: Objective-C Panel Archived
- Objective-C panel code moved to archive branch
- Removed from main branch
- Still available via Git history if needed

---

## Known Issues & Workarounds

### Issue 1: No Live Preview
**Problem:** barista_config doesn't have live preview bar yet (Objective-C panel does)

**Workaround:** Click "Apply" to reload SketchyBar and see changes

**Status:** Live preview planned for Week 2-3 (Jan 2026)

### Issue 2: Limited Icon Library
**Problem:** IconBrowser currently uses hardcoded icons

**Workaround:** Icons will be expanded once JSON loading is implemented

**Status:** IconBrowser JSON loading planned for Week 1-2 (Jan 2026)

### Issue 3: No Multi-Space Awareness
**Problem:** Window doesn't follow you across spaces like Objective-C panel

**Workaround:** Keep barista_config on a dedicated space or use Cmd+Tab to switch

**Status:** Multi-space awareness planned for Feb 2026

### Issue 4: Missing Dock Integration
**Problem:** barista_config doesn't stay in Dock like Objective-C panel

**Workaround:** Pin to Dock manually or launch from cortex

**Status:** Will remain different (by design, barista_config is standalone tool)

---

## FAQ

### Q: Will I lose my settings when migrating?
**A:** No. Both tools use the same `state.json` file, so your settings are preserved.

### Q: Can I use both tools at the same time?
**A:** Technically yes, but not recommended. They both write to the same config file, which could cause conflicts.

### Q: What if I prefer the Objective-C panel?
**A:** You can continue using it until May 2026. After that, it will be archived but still available via Git history.

### Q: Will barista_config work on Linux?
**A:** Yes! That's one of the main benefits of the migration. However, SketchyBar itself is macOS-only, so you'd need a compatible status bar on Linux.

### Q: What about Windows support?
**A:** barista_config is built to be cross-platform, but integration with a Windows status bar is not currently planned. The tool itself will compile and run on Windows.

### Q: How do I report bugs?
**A:** Open an issue on GitHub with:
- Steps to reproduce
- Expected behavior
- Actual behavior
- Logs (if applicable)

### Q: Can I contribute to barista_config?
**A:** Absolutely! See `/Users/scawful/src/shared/cpp/halext/QUICKSTART.md` for development setup.

---

## Resources

### Documentation
- [barista_config README](/Users/scawful/src/lab/barista_config/README.md)
- [halext QUICKSTART](/Users/scawful/src/shared/cpp/halext/QUICKSTART.md)
- [halext ROADMAP](/Users/scawful/src/shared/cpp/halext/docs/ROADMAP.md)
- [barista README](/Users/scawful/src/lab/barista/README.md)
- [Objective-C Panel Docs](/Users/scawful/src/lab/barista/docs/features/CONTROL_PANEL_V2.md)

### Code Repositories
- barista_config: `/Users/scawful/src/lab/barista_config/`
- halext library: `/Users/scawful/src/shared/cpp/halext/`
- barista (SketchyBar config): `/Users/scawful/src/lab/barista/`

### Issue Tracking
- GitHub Issues: (URL when public)
- Feature Requests: (URL when public)

---

## Support

### Getting Help
1. Check this migration guide first
2. Search GitHub issues
3. Ask in GitHub Discussions
4. Open a new issue if needed

### Providing Feedback
We want to hear from you! Please provide feedback on:
- Missing features
- Bugs or unexpected behavior
- UI/UX improvements
- Performance issues

---

**Last Updated:** 2026-01-01
**Next Review:** 2026-02-01
**Maintainer:** @scawful
