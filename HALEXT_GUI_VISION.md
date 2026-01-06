# Barista Configuration Tool - halext:: ImGui Vision

**Date**: 2026-01-01
**Status**: Planning
**Replaces**: BaristaControlPanel.app (Objective-C, 351KB)

## Overview

Replace the current Objective-C configuration GUI with a modern halext:: ImGui-based tool that provides:
- **Better UI/UX**: Modern Material Design-inspired interface
- **Real-time preview**: See changes immediately in SketchyBar
- **Unified configuration**: Single tool for all barista/sketchybar settings
- **Cross-platform**: Works on macOS/Linux (same as sys_manual)
- **Reusable code**: Shares halext:: infrastructure with sys_manual and future tools

## Current State Analysis

### Existing Objective-C GUI (`config_menu.m`)
**Size**: 70KB source (351KB binary)
**Issues**:
- Outdated UI patterns (NSSlider, NSPopUpButton from 2010s)
- No live preview
- Difficult to maintain/extend
- Fixed 1280x880 window
- Manual color hex field editing
- Icon library browser is clunky

**Features to preserve**:
- Widget toggle controls
- Color picker with hex codes
- Icon browser (Material Design, FontAwesome, etc.)
- Height/corner radius sliders
- Space mode configuration
- Integration toggles (yaze, emacs, cortex, halext)

### New halext:: GUI Architecture

```
~/src/lab/barista_config/
├── src/
│   ├── main.cc                  # Entry point
│   ├── app.{h,cc}               # Main application (extends halext::gui::Application)
│   ├── views/
│   │   ├── appearance.{h,cc}    # Appearance settings (colors, fonts, sizes)
│   │   ├── widgets.{h,cc}       # Widget toggles and configuration
│   │   ├── integrations.{h,cc}  # Integration settings (cortex, yaze, etc.)
│   │   ├── icons.{h,cc}         # Icon browser with preview
│   │   ├── spaces.{h,cc}        # Space mode configuration
│   │   └── preview.{h,cc}       # Live preview of bar appearance
│   ├── state/
│   │   ├── config_manager.{h,cc}  # Read/write state.json
│   │   └── sketchybar_bridge.{h,cc}  # Send updates to SketchyBar
├── CMakeLists.txt
└── README.md
```

## Feature Breakdown

### 1. Appearance Tab
**Color Management**:
- ImGui color picker widgets (HSV/RGB)
- Live hex code display/edit
- Predefined color schemes (Catppuccin, Nord, Dracula, etc.)
- Transparency sliders with live preview

**Bar Settings**:
- Height slider (24-48px) with live value display
- Corner radius slider (0-12px)
- Blur radius slider (0-60px)

**Font Settings**:
- Font family dropdown (SF Pro, JetBrains Mono, etc.)
- Font style dropdown (Regular, Bold, Semibold, etc.)
- Font size slider (8-24pt)

### 2. Widgets Tab
**Toggle Matrix**:
```
┌─────────────────────────────────────┐
│ ☑ Clock        ☑ Battery    ☑ CPU  │
│ ☑ Calendar     ☑ Volume     ☑ Mem  │
│ ☑ Network      ☑ System     ☑ Disk │
│ ☐ Weather      ☑ Actions    ☑ Docs │
└─────────────────────────────────────┘
```

**Widget Colors**:
- Per-widget color customization
- Color presets
- Reset to defaults

### 3. Icons Tab
**Icon Browser**:
- Search bar for icon names
- Grid view with icon previews
- Filter by library (Material Design, FontAwesome, Nerd Font)
- Click to copy glyph/code
- Live preview in context

**Icon Assignment**:
```
Apple Icon:   [  ]  (dropdown or glyph input)
Quest Icon:   [ 󰊠 ]
Clock Icon:   [  ]
Battery Icon: [  ]
...
```

### 4. Integrations Tab
**Service Integration Toggles**:
```
☑ Cortex        [ Configure ]
☑ Yaze          [ Configure ]
☑ Emacs         [ Configure ]
☐ halext-org    [ Configure ]
```

**Cortex Settings**:
- Widget enabled toggle
- Label mode (hafs/training/status/none)
- Label prefix text field
- Icon selection
- Color customization
- Update frequency slider

**Workspace Settings**:
- Default sync type
- Sync direction
- Remote server URL

### 5. Spaces Tab
**Space Mode Grid**:
```
Space 1: [ BSP ▼ ]
Space 2: [ BSP ▼ ]
Space 3: [ BSP ▼ ]
Space 4: [ BSP ▼ ]
...
```

**Per-Space Settings**:
- Layout mode (BSP/Stack/Float)
- Padding configuration
- Gap sizes

### 6. Preview Tab (Stretch Goal)
**Live Preview**:
- Render approximate bar appearance using ImGui
- Show icons, colors, spacing
- Update in real-time as settings change
- "Apply to SketchyBar" button

## Technical Implementation

### halext:: Integration

**Base Class**:
```cpp
#include "halext/gui/application.h"
#include "halext/gui/style.h"
#include "halext/gui/icons.h"

class BaristaConfigApp : public halext::gui::Application {
public:
    BaristaConfigApp() : Application("Barista Config", 1200, 800) {
        halext::gui::ApplyTheme(halext::gui::ThemeProfile::Catppuccin);
    }

    void OnStart() override;
    void OnRender() override;

private:
    enum class View {
        Appearance,
        Widgets,
        Icons,
        Integrations,
        Spaces,
        Preview
    };

    View current_view_ = View::Appearance;
    ConfigManager config_;
    SketchyBarBridge bridge_;
};
```

### State Management

**JSON Configuration** (`~/.config/sketchybar/state.json`):
```cpp
#include <nlohmann/json.hpp>

class ConfigManager {
public:
    ConfigManager(const std::filesystem::path& state_file);

    // Load current state
    void Load();

    // Save changes
    void Save();

    // Get/Set methods
    std::string GetBarColor() const;
    void SetBarColor(const std::string& color);

    int GetBarHeight() const;
    void SetBarHeight(int height);

    bool IsWidgetEnabled(const std::string& widget) const;
    void SetWidgetEnabled(const std::string& widget, bool enabled);

    std::string GetIcon(const std::string& name) const;
    void SetIcon(const std::string& name, const std::string& glyph);

private:
    std::filesystem::path state_file_;
    nlohmann::json state_;
};
```

### SketchyBar Bridge

**Apply changes to running SketchyBar**:
```cpp
class SketchyBarBridge {
public:
    // Send update command to SketchyBar
    void UpdateBarColor(const std::string& color);
    void UpdateBarHeight(int height);
    void ReloadBar();
    void RefreshWidget(const std::string& widget);

private:
    std::string RunCommand(const std::string& cmd);
};
```

### Icon Browser Widget

**Reusable ImGui widget**:
```cpp
namespace halext::widgets {

class IconBrowser {
public:
    struct IconEntry {
        std::string title;
        std::string glyph;
        std::string font;
        std::string code;
    };

    IconBrowser();

    // Render returns true if an icon was selected
    bool Render();

    // Get selected icon
    std::optional<IconEntry> GetSelected() const;

private:
    std::vector<IconEntry> icons_;
    std::string search_query_;
    std::optional<IconEntry> selected_;
};

}  // namespace halext::widgets
```

## UI Mockup (ImGui Pseudo-code)

```cpp
void BaristaConfigApp::OnRender() {
    // Sidebar navigation
    ImGui::Begin("Navigation", nullptr, ImGuiWindowFlags_NoResize);
    ImGui::SetWindowSize(ImVec2(200, 0));

    if (ImGui::Selectable(ICON_MD_PALETTE " Appearance", current_view_ == View::Appearance))
        current_view_ = View::Appearance;
    if (ImGui::Selectable(ICON_MD_WIDGETS " Widgets", current_view_ == View::Widgets))
        current_view_ = View::Widgets;
    if (ImGui::Selectable(ICON_MD_IMAGE " Icons", current_view_ == View::Icons))
        current_view_ = View::Icons;
    if (ImGui::Selectable(ICON_MD_EXTENSION " Integrations", current_view_ == View::Integrations))
        current_view_ = View::Integrations;
    if (ImGui::Selectable(ICON_MD_DASHBOARD " Spaces", current_view_ == View::Spaces))
        current_view_ = View::Spaces;

    ImGui::End();

    // Main content area
    ImGui::Begin("Settings");

    switch (current_view_) {
        case View::Appearance:
            RenderAppearanceView();
            break;
        case View::Widgets:
            RenderWidgetsView();
            break;
        case View::Icons:
            RenderIconsView();
            break;
        case View::Integrations:
            RenderIntegrationsView();
            break;
        case View::Spaces:
            RenderSpacesView();
            break;
        case View::Preview:
            RenderPreviewView();
            break;
    }

    ImGui::End();
}

void BaristaConfigApp::RenderAppearanceView() {
    ImGui::Text(ICON_MD_PALETTE " Appearance Settings");
    ImGui::Separator();

    // Bar color
    ImVec4 bar_color = HexToImVec4(config_.GetBarColor());
    if (ImGui::ColorEdit4("Bar Color", (float*)&bar_color)) {
        config_.SetBarColor(ImVec4ToHex(bar_color));
        bridge_.UpdateBarColor(config_.GetBarColor());
    }

    // Bar height
    int height = config_.GetBarHeight();
    if (ImGui::SliderInt("Bar Height", &height, 24, 48)) {
        config_.SetBarHeight(height);
        bridge_.UpdateBarHeight(height);
    }

    // Corner radius
    int corner_radius = config_.GetCornerRadius();
    if (ImGui::SliderInt("Corner Radius", &corner_radius, 0, 12)) {
        config_.SetCornerRadius(corner_radius);
        bridge_.UpdateCornerRadius(corner_radius);
    }

    ImGui::Separator();

    // Theme presets
    ImGui::Text("Color Schemes");
    if (ImGui::Button("Catppuccin Mocha")) {
        ApplyCatppuccinMocha();
    }
    ImGui::SameLine();
    if (ImGui::Button("Nord")) {
        ApplyNord();
    }
    ImGui::SameLine();
    if (ImGui::Button("Dracula")) {
        ApplyDracula();
    }

    ImGui::Separator();

    // Apply/Save buttons
    if (ImGui::Button("Apply Changes")) {
        bridge_.ReloadBar();
    }
    ImGui::SameLine();
    if (ImGui::Button("Save to File")) {
        config_.Save();
    }
}
```

## Migration Strategy

### Phase 1: Prototype (Current)
- ✅ Create enhanced Control Center Lua module
- ✅ Add cortex and sys_manual to apple menu
- ⬜ Test integration in SketchyBar

### Phase 2: Foundation
- ⬜ Create `barista_config` project structure
- ⬜ Implement ConfigManager for state.json
- ⬜ Implement SketchyBarBridge for updates
- ⬜ Basic window with sidebar navigation

### Phase 3: Core Views
- ⬜ Appearance view (colors, sizes, fonts)
- ⬜ Widgets view (toggles, grid layout)
- ⬜ Icons view (browser, search, preview)

### Phase 4: Advanced Features
- ⬜ Integrations view (cortex, yaze, emacs, etc.)
- ⬜ Spaces view (per-space configuration)
- ⬜ Live preview (stretch goal)

### Phase 5: Deployment
- ⬜ Build as standalone app
- ⬜ Update apple menu to launch new tool
- ⬜ Deprecate old config_menu.m
- ⬜ Document migration process

## Benefits Over Objective-C GUI

### 1. **Better Developer Experience**
- Modern C++17 vs dated Objective-C
- Shared halext:: infrastructure
- Easy to extend with new views
- Hot-reloadable (ImGui supports this)

### 2. **Better User Experience**
- Modern UI with Material Design icons
- Live preview of changes
- Color picker instead of hex fields
- Icon browser with visual search
- Real-time feedback

### 3. **Maintainability**
- Modular architecture (separate views)
- JSON-based configuration (easy to debug)
- Reusable widgets (IconBrowser, ColorPicker, etc.)
- Shared with sys_manual (one codebase to maintain)

### 4. **Integration**
- Seamless integration with cortex
- Same menu system as sys_manual
- Can communicate via distributed notifications
- Shares theme with other halext:: tools

## Integration with Control Center

The new tool will be accessible via:
1. **Apple menu** → "Barista Settings" (current config_menu.m launch point)
2. **Control Center widget** → "Tools & Apps" → "Barista Config"
3. **cortex** → Quick actions → "Configure Barista"

This creates a unified ecosystem:
```
┌─────────────────────────────────────────┐
│ halext:: ImGui Tools Ecosystem          │
├─────────────────────────────────────────┤
│ • sys_manual    - Workspace docs        │
│ • barista_config - SketchyBar settings  │
│ • cortex        - Swift menu bar app    │
│ • (future) afs_studio - HAFS agent UI   │
└─────────────────────────────────────────┘
```

All share:
- Material Design icons
- halext::gui infrastructure
- Consistent theming
- TOML/JSON configuration
- macOS distributed notifications

## Next Steps

1. ⬜ Test enhanced apple menu and control center
2. ⬜ Scaffold barista_config project
3. ⬜ Implement ConfigManager
4. ⬜ Build Appearance view prototype
5. ⬜ Iterate based on user feedback

---

**Status**: Ready for Phase 1 testing
**Date**: 2026-01-01
