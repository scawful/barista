# Sketchybar Control Panel V2 - Design Document

## Overview
Modern, tabbed macOS configuration panel for Sketchybar with persistent window management and native API integration.

## Architecture

### Window Management
- **Activation Policy**: `NSApplicationActivationPolicyRegular` (shows in Dock, stays open)
- **Window Level**: `NSFloatingWindowLevel` for easy access
- **Lifecycle**: Window hides on close (doesn't terminate app)
- **Collection Behavior**:
  - `NSWindowCollectionBehaviorCanJoinAllSpaces` - visible on all spaces
  - `NSWindowCollectionBehaviorFullScreenAuxiliary` - works with full screen apps

### Configuration Manager
Centralized singleton for state management:
- Load/save state from `~/.config/sketchybar/state.json`
- Key-path based access: `appearance.bar_height`
- Automatic saving on changes
- Sketchybar reload integration

### Tab Structure

#### 1. Appearance Tab
**Purpose**: Visual customization of bar and widgets

**Controls**:
- Bar Height (20-50px) with live preview
- Corner Radius (0-16px) with live preview
- Blur Radius (0-80)
- Widget Scale (0.85-1.25)
- Bar Color (color well + hex input)
- Live Preview Box showing current settings

**Implementation**:
- Real-time preview updates as sliders move
- Hex color field with validation
- Apply & Reload button with visual feedback

#### 2. Widgets Tab
**Purpose**: Enable/disable widgets and customize colors

**Controls**:
- Table view with columns:
  - Icon (Nerd Font glyph)
  - Widget Name
  - Enabled (checkbox toggle)
  - Color (color well)
- Instant save on toggle/color change

**Widgets**:
- Clock
- Battery
- Volume
- Network
- System Info
- Yabai Status (if available)

#### 3. Spaces Tab
**Purpose**: Customize space icons and layout modes

**Controls**:
- Space selector (1-10)
- Icon picker for current space
- Icon preview (large Nerd Font display)
- Layout mode selector:
  - Float (default)
  - BSP Tiling
  - Stack Tiling
- Per-space persistent settings

**Integration**:
- Queries Yabai for active spaces
- Fallback to numbered list if Yabai unavailable
- Icon library browser integration

#### 4. Icons Tab
**Purpose**: Browse and apply icons from library

**Controls**:
- Searchable icon library (500+ Nerd Fonts)
- Category filter:
  - System & Hardware
  - Development
  - Applications
  - UI Elements
  - Arrows & Symbols
- Icon preview (large display)
- Apply to:
  - Apple menu icon
  - Quest/custom icons
  - Specific app in front_app
- Copy glyph to clipboard

**Implementation**:
- Collection view with grid layout
- Search filter updates in real-time
- Category segmented control

#### 5. Integrations Tab
**Purpose**: External service integration and preparation for halext-org

**Current Integrations**:
- **Yaze** (ROM hacking):
  - Enable/disable toggle
  - Status indicator (installed/built/running)
  - Launch button
  - Open repo button
  - Focus space button

- **Emacs**:
  - Enable/disable toggle
  - Status indicator (running/stopped)
  - Launch button
  - Focus space button
  - Recent org files list

**Future Integration - halext-org**:
- **Purpose**: Task management + Calendar + LLM + Emacs
- **Placeholder UI**:
  - Server URL input field
  - API key field (secure text entry)
  - Connection status indicator
  - Test connection button
  - Enable/disable toggle

- **Planned Features**:
  - Sync tasks from halext-org to bar popup
  - Show upcoming calendar events
  - LLM-powered task suggestions
  - Emacs org-mode bidirectional sync
  - Custom menu items from server

**Implementation**:
- Modular integration system
- Each integration has own section
- Status updates in real-time
- Expandable sections for detailed config

#### 6. Advanced Tab
**Purpose**: Raw state editing and system information

**Controls**:
- **State JSON Editor**:
  - Syntax-highlighted text view
  - Save/Reload buttons
  - Validation on save
  - Pretty-print formatting

- **System Information**:
  - Sketchybar version
  - Config path
  - State file path
  - Scripts directory
  - Helper binaries status

- **Actions**:
  - Open config directory
  - Open state.json in editor
  - Reload Sketchybar
  - Restart Sketchybar
  - View logs button

- **Danger Zone**:
  - Reset to defaults button (with confirmation)
  - Clear all customizations
  - Rebuild helper binaries

**Implementation**:
- NSTextView with monospace font
- JSON syntax validation
- Confirmation alerts for destructive actions
- File watchers for external changes

## macOS API Leverage

### NSColorWell
- Native color picker integration
- Live updates on color change
- Hex/RGB/HSB support

### NSTableView / NSCollectionView
- Native list/grid display
- Sorting and filtering
- Selection handling

### NSTabView
- Native tabbed interface
- Keyboard navigation (Cmd+1-6)
- Accessible design

### NSWorkspace
- App launching
- File opening
- Process management

### NSFileManager
- File existence checks
- Directory operations
- Path resolution

### NSTask / NSPipe
- Script execution
- Output capture
- Background processes

### NSSharingService
- Share configurations
- Export settings
- Import from file

## Persistence Strategy

### Window State
- Size and position saved in UserDefaults
- Last selected tab remembered
- Restore on relaunch

### Application Lifecycle
- Don't terminate on window close
- Keep running in background
- Reactivate on menu bar click or hotkey

### Configuration Sync
- Auto-save on every change
- Debounced save for rapid changes
- Conflict detection with external edits

## Accessibility

### Keyboard Navigation
- Tab key navigation through controls
- Return key for default actions
- Escape key to close/cancel
- Cmd+W to hide window
- Cmd+Q to quit application
- Cmd+1-6 for tab switching

### VoiceOver Support
- Proper accessibility labels
- Action descriptions
- State announcements

### Visual
- High contrast support
- Respects system dark mode
- Scalable UI elements
- Clear focus indicators

## Performance

### Lazy Loading
- Tabs load content only when first viewed
- Icon library loads incrementally
- Large lists use virtual scrolling

### Batching
- Multiple state changes batched before reload
- UI updates debounced
- Background operations queued

### Memory Management
- ARC for automatic cleanup
- Weak references for delegates
- Image caching for icons

## Future Enhancements

### Export/Import
- Export configuration as JSON
- Share with other users
- Import preset themes

### Themes
- Visual theme editor
- Theme library
- One-click theme application

### Presets
- Common configurations
- Quick-apply presets
- Save custom presets

### Remote Configuration
- halext-org server integration
- Cloud sync of settings
- Multi-machine management

### Plugin System
- User-defined integrations
- Custom widgets
- External data sources

## Technical Notes

### Build Requirements
- macOS 11.0+ (Big Sur)
- Xcode Command Line Tools
- Cocoa framework
- UniformTypeIdentifiers framework (for file handling)

### Dependencies
- No external libraries
- Pure Objective-C
- Native frameworks only

### File Structure
```
gui/
├── config_menu_v2.m          # Main implementation
├── Makefile                   # Build configuration
└── bin/
    └── config_menu_v2         # Compiled binary
```

### Build Command
```bash
cd gui && make config_v2
```

### Launch
```bash
~/config/sketchybar/gui/bin/config_menu_v2
```

Or via Apple menu: Shift+Click Apple icon

## Integration Points

### With Main Configuration (main.lua)
- Reads from `state.json`
- Triggers `sketchybar --reload`
- No direct Lua interaction needed

### With Helper Scripts
- Calls scripts via NSTask
- Monitors script output
- Handles errors gracefully

### With Yabai
- Queries space information
- Sends yabai commands
- Monitors yabai status

### With halext-org (Future)
- REST API calls (NSURLSession)
- WebSocket for real-time updates
- OAuth2 authentication
- JSON data exchange
- Calendar event subscription (iCal/CalDAV)
- Task sync (org-mode format)
- LLM integration for suggestions

## Security Considerations

### Credentials Storage
- Keychain for API keys
- Secure text entry for passwords
- No plaintext secrets in state.json

### Script Execution
- Whitelist of allowed scripts
- Path validation
- No arbitrary code execution

### Network
- HTTPS only for halext-org
- Certificate validation
- Timeout handling

## Testing Strategy

### Manual Testing
- Each tab functionality
- State persistence
- Error handling
- Edge cases (missing files, invalid JSON)

### Integration Testing
- State changes reflect in Sketchybar
- Reload triggers correctly
- No state corruption

### Performance Testing
- Large icon libraries
- Many spaces configured
- Rapid UI interactions

## Documentation

### User Guide
- README with screenshots
- Feature walkthrough
- Keyboard shortcuts reference
- Troubleshooting section

### Developer Guide
- Architecture explanation
- Adding new tabs
- Integration patterns
- Testing procedures
