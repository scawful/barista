# Portability Implementation Summary

This document summarizes the active portability boundaries used to share and
deploy Barista across different users and machines. Machine-local task paths,
work apps, and integration credentials are intentionally excluded from the
committed defaults.

## 🎯 Goals Achieved

### 1. ✅ Profile Variant Support
- **Minimal**: Clean baseline with no personal integrations
- **Cozy**: Warm, low-maintenance setup with yabai disabled
- **Personal**: Full ROM hacking + Emacs setup
- **Work**: Emacs + work-oriented spaces, with personal integrations off
- **Restricted Work**: Script-only work-laptop setup without yabai or compiled helpers

### 2. ✅ Multi-Machine Support
- Same user, different machines (personal laptop, work computer)
- Profile selection via `state.json` or environment variable
- Clean separation of machine-specific vs. user-specific config

### 3. ✅ Easy Installation
- One-command installer: `./scripts/install.sh`
- Automatic dependency checking
- Interactive profile selection
- Builds all components automatically

### 4. ✅ GitHub-Ready
- Focused README and install guidance
- MIT License
- Architecture and troubleshooting documentation
- Clean .gitignore

## 📂 Profile System

### Architecture

```
profiles/
├── minimal.lua      # Template - Clean, no integrations
├── cozy.lua         # Warm, simple setup
├── personal.lua     # scawful personal - ROM hacking + Emacs
└── work.lua         # Work - Emacs + work spaces; local extras opt in
```

### How It Works

1. **Profile Selection**:
   ```json
   // state.json
   {
     "profile": "minimal"
   }
   ```

2. **Or via Environment for one reload**:
   ```bash
   export SKETCHYBAR_PROFILE=work
   ./plugins/reload_sketchybar.sh
   ```

3. **Profile Loading** (`modules/profile.lua`):
   - Loads selected profile
   - Merges appearance/widgets/integrations
   - Applies profile appearance, widget, integration, mode, and space defaults

### Profile Structure

```lua
-- Example: profiles/custom.lua
local profile = {}

profile.name = "custom"
profile.description = "Custom setup"

-- Integration toggles
profile.integrations = {
  yaze = false,
  emacs = true,
  halext = false,
}

-- Appearance
profile.appearance = {
  bar_height = 32,
  corner_radius = 9,
  bar_color = "0xC021162F",
}

-- Widgets
profile.widgets = {
  clock = true,
  battery = true,
}

-- Spaces
profile.spaces = {
  count = 5,
  default_mode = "bsp",
  icons = {
    ["1"] = "",
    ["2"] = "",
  }
}

return profile
```

## 🚀 Installation Workflow

### For a Low-Maintenance Mac:

```bash
# Clone repository
git clone https://github.com/scawful/barista ~/.config/sketchybar
cd ~/.config/sketchybar

# Run installer
./scripts/install.sh
# Select minimal or cozy profile

# Done! SketchyBar starts with clean config
```

### Install a New Work Computer:

Run `./scripts/install.sh` and select Work when prompted. The installer owns
dependencies, the initial build, service configuration, and startup.

### Apply Work Defaults to an Existing Runtime:

```bash
# Apply normal Work defaults
./scripts/setup_machine.sh --yes \
  --profile-variant work \
  --panel-mode tui \
  --runtime-backend auto \
  --skip-fonts \
  --report
```

Work setup explicitly disables personal Oracle/Music/Journal/NERV/Yaze state,
sets the task provider to `files`, clears task, syshelp, and meeting-cache
paths, removes stale generated task-capture bindings, and leaves Task Pulse
off. Halext is an opt-in local integration, not a Work-profile requirement.
Use `--restricted-work` instead for the Lua-only/no-yabai lane.

### Creating Custom Profile:

```bash
# Copy template
cp profiles/minimal.lua profiles/design.lua

# Edit profile
vim profiles/design.lua

# Activate without replacing the rest of state.json; this reloads safely.
./scripts/set_mode.sh design
```

## 🔧 Technical Implementation

### Profile Module (`modules/profile.lua`)

```lua
-- Load profile
local profile = require("profile")
local user_profile = profile.load("minimal")

-- Merge with state
state = profile.merge_config(state, user_profile)

-- Get integration flags
local flags = profile.get_integration_flags(user_profile)

-- Get custom menu sections
local sections = profile.get_menu_sections(user_profile)
```

### Integration with main.lua

```lua
-- Load state and profile
local state = state_module.load()
local profile_name = profile_module.get_selected_profile(state)
local user_profile = profile_module.load(profile_name)

-- Merge profile configuration
if user_profile then
  state = profile_module.merge_config(state, user_profile)
  print("Loaded profile: " .. user_profile.name)
end
```

## 📊 What's Personal vs. Shared

### Personal (profiles/personal.lua)
- ✅ ROM hacking (Yaze integration)
- ✅ Personal Emacs workflows
- ✅ Custom space icons
- ✅ Specific paths (~/src/yaze, ~/src/docs)

### Work (profiles/work.lua)
- ❌ No ROM hacking
- ✅ Emacs for org-mode
- ❌ Halext and dormant experimental integration flags stay off until locally enabled
- ❌ No shared task source or Task Pulse state
- ✅ Work-appropriate space setup

### Machine-local task tracking

Committed task defaults are portable: `menus.calendar.task_sources=[]`,
`menus.calendar.task_provider="files"`, and `widgets.task_focus=false`. A
personal or work Mac can opt in through ignored `state.json` or
`barista_config.lua`:

```json
{
  "widgets": { "task_focus": true },
  "menus": {
    "calendar": {
      "task_provider": "files",
      "task_sources": ["~/path/to/tasks.md"]
    }
  }
}
```

Use `task_provider="syshelp"` only on a machine that intentionally provides the
`syshelp plan tasks` CLI. The conditional `⌘⌥N` capture shortcut is generated
only when a source exists; fresh and Work installs do not expose it. If launchd
cannot find `syshelp`, set ignored local `menus.calendar.syshelp_path` to its
absolute executable path rather than committing that machine-specific path.

The schema v2 upgrade removes only the exact former two-path personal default
from non-Personal states without an explicit task or meeting opt-in. It
preserves Personal states and custom source lists; applying the Work variant is
the deliberate operation that clears any remaining local task and meeting
configuration.

### Cozy (profiles/cozy.lua)
- ❌ No required window manager
- ✅ Warm, larger-feeling defaults
- ✅ Simple widgets

### Minimal (profiles/minimal.lua)
- ❌ No personal integrations
- ✅ Conservative core-widget defaults
- ✅ Sensible defaults
- ✅ Clean starting point

## 🚀 Current Distribution

The repository is already published at `scawful/barista` and uses GitHub
Actions. Install through `scripts/install.sh`; use `bin/barista-update` only
when the live runtime itself is a Git checkout. A copied install should be
updated from its source checkout by rerunning the installer. Use
`scripts/work_mac_sync.sh` or
`scripts/update_work_mac.sh` for an explicitly targeted work Mac. Do not copy
ignored `state.json`, `barista_config.lua`, task paths, or local extension files
between personal and work machines.

## 📈 Benefits Summary

### For You
- ✅ Clean separation of personal/work configs
- ✅ Easy deployment to new machines
- ✅ Version-controlled profiles
- ✅ No need to maintain separate forks

### For Work Setups
- ✅ One-command installation
- ✅ No confusing ROM hacking stuff
- ✅ Clean minimal setup
- ✅ Machine-local customization without leaking personal paths

### For Community
- ✅ Professional open-source project
- ✅ Easy to contribute
- ✅ Template for others to fork
- ✅ Documented and tested

## 🎉 Success Metrics

- **Portability**: five profile variants, including a restricted work lane
- **Performance**: event-driven popup detail paths plus optional compiled helpers
- **Privacy**: shared defaults contain no task source or personal integration state
- **Code Quality**: Clean, modular, well-tested
- **User Experience**: installer, machine-profile setup, native/TUI configuration

## Maintenance Boundaries

- Keep committed task sources empty.
- Keep personal workflow paths in ignored local config or interface extensions.
- Treat Halext and workspace status as opt-in until their active runtime paths
  and credential handling are verified.
- Re-run the Work privacy setup when preparing a managed or shared machine.
