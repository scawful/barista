-- Keyboard Shortcut Management Module
-- Centralized shortcut definitions
-- Non-conflicting shortcuts for global operations

local shortcuts = {}
local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")

local function expand_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  end
  return path
end

local function read_state_scripts_dir()
  local ok, json = pcall(require, "json")
  if not ok then
    return nil
  end

  local state_file = CONFIG_DIR .. "/state.json"
  local file = io.open(state_file, "r")
  if not file then
    return nil
  end

  local contents = file:read("*a")
  file:close()

  local ok_decode, data = pcall(json.decode, contents)
  if not ok_decode or type(data) ~= "table" then
    return nil
  end

  if type(data.paths) ~= "table" then
    return nil
  end

  local candidate = data.paths.scripts_dir or data.paths.scripts
  return expand_path(candidate)
end

local function resolve_scripts_dir()
  local override = os.getenv("BARISTA_SCRIPTS_DIR")
  if override and override ~= "" then
    return expand_path(override)
  end

  local state_override = read_state_scripts_dir()
  if state_override and state_override ~= "" then
    return state_override
  end
  local config_scripts = CONFIG_DIR .. "/scripts"
  local probe = io.open(config_scripts .. "/yabai_control.sh", "r")
  if probe then
    probe:close()
    return config_scripts
  end
  local legacy_scripts = HOME .. "/.config/scripts"
  local legacy_probe = io.open(legacy_scripts .. "/yabai_control.sh", "r")
  if legacy_probe then
    legacy_probe:close()
    return legacy_scripts
  end
  return config_scripts
end

local SCRIPTS_DIR = resolve_scripts_dir()

-- Modifier key symbols and their skhd representations
shortcuts.modifiers = {
  cmd = "cmd",      -- ⌘  Command
  ctrl = "ctrl",    -- ⌃  Control
  alt = "alt",      -- ⌥  Option/Alt
  shift = "shift",  -- ⇧  Shift
  hyper = "hyper",  -- ⌃⌥⇧⌘ All modifiers
}

-- Key symbols for display
shortcuts.symbols = {
  cmd = "⌘",
  ctrl = "⌃",
  alt = "⌥",
  shift = "⇧",
  return_key = "↩",
  delete = "⌫",
  escape = "⎋",
  tab = "⇥",
  space = "␣",
  up = "↑",
  down = "↓",
  left = "←",
  right = "→",
}

-- Global shortcuts (cmd/alt focused)
shortcuts.global = {
  -- Barista UI
  {
    mods = {"cmd", "alt"},
    key = "p",
    action = "open_control_panel",
    desc = "Open Control Panel",
    symbol = "⌘⌥P"
  },
  {
    mods = {"cmd", "alt"},
    key = "c",
    action = "toggle_cortex",
    desc = "Toggle Cortex",
    symbol = "⌘⌥C"
  },
  {
    mods = {"cmd", "alt"},
    key = "0x2C",
    action = "toggle_control_center",
    desc = "Toggle Control Center",
    symbol = "⌘⌥/"
  },
  {
    mods = {"cmd", "alt"},
    key = "k",
    action = "toggle_whichkey",
    desc = "Toggle WhichKey HUD",
    symbol = "⌘⌥K"
  },
  {
    mods = {"cmd", "alt"},
    key = "h",
    action = "open_help_center",
    desc = "Open Help Center",
    symbol = "⌘⌥H"
  },
  {
    mods = {"cmd", "alt"},
    key = "i",
    action = "open_icon_browser",
    desc = "Open Icon Browser",
    symbol = "⌘⌥I"
  },
  {
    mods = {"cmd", "alt"},
    key = "r",
    action = "reload_sketchybar",
    desc = "Reload SketchyBar",
    symbol = "⌘⌥R"
  },
  {
    mods = {"cmd", "alt", "shift"},
    key = "r",
    action = "rebuild_and_reload",
    desc = "Rebuild + Reload SketchyBar",
    symbol = "⌘⌥⇧R"
  },

  -- Yabai Controls
  {
    mods = {"cmd", "alt"},
    key = "y",
    action = "toggle_yabai_shortcuts",
    desc = "Toggle Yabai Shortcuts",
    symbol = "⌘⌥Y"
  },

  -- Space Navigation (ctrl + arrows)
  {
    mods = {"ctrl"},
    key = "left",
    action = "space_prev",
    desc = "Previous Space",
    symbol = "⌃←"
  },
  {
    mods = {"ctrl"},
    key = "right",
    action = "space_next",
    desc = "Next Space",
    symbol = "⌃→"
  },

  -- Display Movement (cmd + alt + shift)
  {
    mods = {"cmd", "alt", "shift"},
    key = "left",
    action = "window_display_prev",
    desc = "Send to Prev Display",
    symbol = "⌘⌥⇧←"
  },
  {
    mods = {"cmd", "alt", "shift"},
    key = "right",
    action = "window_display_next",
    desc = "Send to Next Display",
    symbol = "⌘⌥⇧→"
  },

  -- Layout modes (ctrl+shift)
  {
    mods = {"ctrl", "shift"},
    key = "f",
    action = "set_layout_float",
    desc = "Set Float Layout",
    symbol = "⌃⇧F"
  },
  {
    mods = {"ctrl", "shift"},
    key = "b",
    action = "set_layout_bsp",
    desc = "Set BSP Layout",
    symbol = "⌃⇧B"
  },
  {
    mods = {"ctrl", "shift"},
    key = "s",
    action = "set_layout_stack",
    desc = "Set Stack Layout",
    symbol = "⌃⇧S"
  },
}

-- Action handlers (maps action names to actual commands)
shortcuts.actions = {
  -- SketchyBar
  reload_sketchybar = CONFIG_DIR .. "/bin/rebuild_sketchybar.sh --reload-only",
  rebuild_and_reload = CONFIG_DIR .. "/bin/rebuild_sketchybar.sh",
  open_control_panel = CONFIG_DIR .. "/bin/open_control_panel.sh",
  toggle_control_center = "/opt/homebrew/opt/sketchybar/bin/sketchybar --set control_center popup.drawing=toggle",
  toggle_whichkey = "/opt/homebrew/opt/sketchybar/bin/sketchybar --trigger whichkey_toggle",
  open_help_center = CONFIG_DIR .. "/gui/bin/help_center",
  open_icon_browser = CONFIG_DIR .. "/gui/bin/icon_browser",
  toggle_cortex = "~/.local/bin/cortex toggle",

  -- Yabai
  toggle_yabai_shortcuts = SCRIPTS_DIR .. "/toggle_shortcuts.sh toggle",
  toggle_layout = SCRIPTS_DIR .. "/yabai_control.sh toggle-layout",
  balance_windows = SCRIPTS_DIR .. "/yabai_control.sh balance",
  rotate_layout = SCRIPTS_DIR .. "/yabai_control.sh space-rotate",

  -- Window
  toggle_float = SCRIPTS_DIR .. "/yabai_control.sh window-toggle-float",
  toggle_fullscreen = SCRIPTS_DIR .. "/yabai_control.sh window-toggle-fullscreen",
  center_window = SCRIPTS_DIR .. "/yabai_control.sh window-center",
  minimize_window = "yabai -m window --minimize",
  maximize_window = "yabai -m window --toggle zoom-fullscreen",
  restore_window = "yabai -m window --toggle zoom-fullscreen",

  -- Display
  window_display_next = SCRIPTS_DIR .. "/yabai_control.sh window-display-next",
  window_display_prev = SCRIPTS_DIR .. "/yabai_control.sh window-display-prev",

  -- Space Navigation
  space_prev = SCRIPTS_DIR .. "/yabai_control.sh space-prev",
  space_next = SCRIPTS_DIR .. "/yabai_control.sh space-next",
  space_recent = SCRIPTS_DIR .. "/yabai_control.sh space-recent",

  -- Space Movement
  window_space_next = SCRIPTS_DIR .. "/yabai_control.sh window-space-next",
  window_space_prev = SCRIPTS_DIR .. "/yabai_control.sh window-space-prev",
  send_window_space_1 = SCRIPTS_DIR .. "/yabai_control.sh window-space 1",
  send_window_space_2 = SCRIPTS_DIR .. "/yabai_control.sh window-space 2",
  send_window_space_3 = SCRIPTS_DIR .. "/yabai_control.sh window-space 3",
  send_window_space_4 = SCRIPTS_DIR .. "/yabai_control.sh window-space 4",
  send_window_space_5 = SCRIPTS_DIR .. "/yabai_control.sh window-space 5",

  -- Layout Modes
  set_layout_float = SCRIPTS_DIR .. "/space_mode.sh current float",
  set_layout_bsp = SCRIPTS_DIR .. "/space_mode.sh current bsp",
  set_layout_stack = SCRIPTS_DIR .. "/space_mode.sh current stack",

  -- Apps
  open_terminal = "open -a Terminal",

  -- Window Focus (vim keys)
  focus_window_west = "yabai -m window --focus west",
  focus_window_south = "yabai -m window --focus south",
  focus_window_north = "yabai -m window --focus north",
  focus_window_east = "yabai -m window --focus east",

  -- Space Focus
  focus_space_1 = "yabai -m space --focus 1",
  focus_space_2 = "yabai -m space --focus 2",
  focus_space_3 = "yabai -m space --focus 3",
  focus_space_4 = "yabai -m space --focus 4",
  focus_space_5 = "yabai -m space --focus 5",
  focus_space_6 = "yabai -m space --focus 6",
  focus_space_7 = "yabai -m space --focus 7",
  focus_space_8 = "yabai -m space --focus 8",
  focus_space_9 = "yabai -m space --focus 9",
  focus_space_10 = "yabai -m space --focus 10",
}

local function all_shortcuts()
  local list = {}
  for _, shortcut in ipairs(shortcuts.global) do
    table.insert(list, shortcut)
  end
  return list
end

-- Get shortcut by action name
function shortcuts.get(action_name)
  for _, shortcut in ipairs(all_shortcuts()) do
    if shortcut.action == action_name then
      return shortcut
    end
  end
  return nil
end

-- Get shortcut symbol for display
function shortcuts.get_symbol(action_name)
  local shortcut = shortcuts.get(action_name)
  if shortcut and shortcut.symbol then
    return shortcut.symbol
  end
  return ""
end

-- Get command for action
function shortcuts.get_command(action_name)
  return shortcuts.actions[action_name] or ""
end

-- Format shortcut for skhd config
function shortcuts.format_for_skhd(shortcut)
  if not shortcut or not shortcut.mods or not shortcut.key then
    return nil
  end

  local mods_str = table.concat(shortcut.mods, " + ")
  local command = shortcuts.get_command(shortcut.action)

  if command == "" then
    return nil
  end

  return string.format("%s - %s : %s", mods_str, shortcut.key, command)
end

-- Generate skhd configuration
function shortcuts.generate_skhd_config()
  local lines = {
    "# SketchyBar Shortcuts",
    "# Generated by barista shortcuts module",
    "# cmd/alt focused shortcut set",
    "",
  }

  for _, shortcut in ipairs(all_shortcuts()) do
    local formatted = shortcuts.format_for_skhd(shortcut)
    if formatted then
      table.insert(lines, string.format("# %s - %s", shortcut.desc, shortcut.symbol))
      table.insert(lines, formatted)
      table.insert(lines, "")
    end
  end

  return table.concat(lines, "\n")
end

-- Write skhd configuration to file
function shortcuts.write_skhd_config(filepath)
  filepath = filepath or os.getenv("HOME") .. "/.config/skhd/barista_shortcuts.conf"

  local config = shortcuts.generate_skhd_config()
  local file = io.open(filepath, "w")

  if not file then
    return false, "Could not open file for writing: " .. filepath
  end

  file:write(config)
  file:close()

  return true, filepath
end

-- List all shortcuts
function shortcuts.list_all()
  local list = {}
  for _, shortcut in ipairs(all_shortcuts()) do
    table.insert(list, {
      desc = shortcut.desc,
      symbol = shortcut.symbol,
      action = shortcut.action,
      command = shortcuts.get_command(shortcut.action)
    })
  end
  return list
end

-- Check for conflicts (basic check)
function shortcuts.check_conflicts()
  local seen = {}
  local conflicts = {}

  for _, shortcut in ipairs(all_shortcuts()) do
    local key_combo = string.format("%s-%s", table.concat(shortcut.mods, "+"), shortcut.key)
    if seen[key_combo] then
      table.insert(conflicts, {
        combo = key_combo,
        actions = {seen[key_combo], shortcut.action}
      })
    else
      seen[key_combo] = shortcut.action
    end
  end

  return conflicts
end

return shortcuts
