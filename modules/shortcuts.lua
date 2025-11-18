-- Keyboard Shortcut Management Module
-- Centralized shortcut definitions with fn-key support
-- Non-conflicting shortcuts for global operations

local shortcuts = {}

-- Modifier key symbols and their skhd representations
shortcuts.modifiers = {
  cmd = "cmd",      -- ⌘  Command
  ctrl = "ctrl",    -- ⌃  Control
  alt = "alt",      -- ⌥  Option/Alt
  shift = "shift",  -- ⇧  Shift
  fn = "fn",        -- 🌐 Function/Globe key (macOS Ventura+)
  hyper = "hyper",  -- ⌃⌥⇧⌘ All modifiers
}

-- Key symbols for display
shortcuts.symbols = {
  cmd = "⌘",
  ctrl = "⌃",
  alt = "⌥",
  shift = "⇧",
  fn = "🌐",
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

-- Function key mappings (fn + letter = function key behavior)
shortcuts.fn_mappings = {
  -- Non-conflicting fn-key combinations for global operations
  -- Using fn key to avoid conflicts with app shortcuts

  -- Window Management (fn + vim keys)
  ["fn-h"] = "focus_window_west",
  ["fn-j"] = "focus_window_south",
  ["fn-k"] = "focus_window_north",
  ["fn-l"] = "focus_window_east",

  -- Space Navigation (fn + number)
  ["fn-1"] = "focus_space_1",
  ["fn-2"] = "focus_space_2",
  ["fn-3"] = "focus_space_3",
  ["fn-4"] = "focus_space_4",
  ["fn-5"] = "focus_space_5",
  ["fn-6"] = "focus_space_6",
  ["fn-7"] = "focus_space_7",
  ["fn-8"] = "focus_space_8",
  ["fn-9"] = "focus_space_9",
  ["fn-0"] = "focus_space_10",

  -- Quick Actions (fn + key)
  ["fn-t"] = "toggle_layout",          -- Toggle BSP/Float
  ["fn-f"] = "toggle_fullscreen",      -- Fullscreen current window
  ["fn-r"] = "rotate_layout",          -- Rotate windows
  ["fn-b"] = "balance_windows",        -- Balance window sizes
  ["fn-m"] = "minimize_window",        -- Minimize
  ["fn-c"] = "center_window",          -- Center floating window
  ["fn-space"] = "toggle_float",       -- Toggle float

  -- Display Management (fn + arrow)
  ["fn-right"] = "window_display_next",
  ["fn-left"] = "window_display_prev",
  ["fn-up"] = "maximize_window",
  ["fn-down"] = "restore_window",
}

-- Global shortcuts (using ctrl+alt to avoid conflicts)
shortcuts.global = {
  -- SketchyBar Controls
  {
    mods = {"ctrl", "alt"},
    key = "r",
    action = "reload_sketchybar",
    desc = "Reload SketchyBar",
    symbol = "⌃⌥R"
  },
  {
    mods = {"ctrl", "alt", "shift"},
    key = "r",
    action = "rebuild_and_reload",
    desc = "Rebuild + Reload SketchyBar",
    symbol = "⌃⌥⇧R"
  },
  {
    mods = {"ctrl", "alt"},
    key = "p",
    action = "open_control_panel",
    desc = "Open Control Panel",
    symbol = "⌃⌥P"
  },
  {
    mods = {"ctrl", "alt"},
    key = "/",
    action = "toggle_control_center",
    desc = "Toggle Control Center",
    symbol = "⌃⌥/"
  },

  -- Yabai Controls
  {
    mods = {"ctrl", "alt"},
    key = "y",
    action = "toggle_yabai_shortcuts",
    desc = "Toggle Yabai Shortcuts",
    symbol = "⌃⌥Y"
  },
  {
    mods = {"ctrl", "alt"},
    key = "l",
    action = "toggle_layout",
    desc = "Toggle Layout Mode",
    symbol = "⌃⌥L"
  },
  {
    mods = {"ctrl", "alt"},
    key = "b",
    action = "balance_windows",
    desc = "Balance Windows",
    symbol = "⌃⌥B"
  },

  -- Window Operations
  {
    mods = {"ctrl", "alt"},
    key = "f",
    action = "toggle_float",
    desc = "Toggle Float",
    symbol = "⌃⌥F"
  },
  {
    mods = {"ctrl", "alt"},
    key = "return",
    action = "toggle_fullscreen",
    desc = "Toggle Fullscreen",
    symbol = "⌃⌥↩"
  },
  {
    mods = {"ctrl", "alt"},
    key = "t",
    action = "open_terminal",
    desc = "Open Terminal",
    symbol = "⌃⌥T"
  },

  -- Display Management
  {
    mods = {"ctrl", "alt"},
    key = "right",
    action = "window_display_next",
    desc = "Send to Next Display",
    symbol = "⌃⌥→"
  },
  {
    mods = {"ctrl", "alt"},
    key = "left",
    action = "window_display_prev",
    desc = "Send to Prev Display",
    symbol = "⌃⌥←"
  },

  -- Space Movement (ctrl+alt+cmd to avoid conflicts)
  {
    mods = {"ctrl", "alt", "cmd"},
    key = "right",
    action = "window_space_next",
    desc = "Send to Next Space",
    symbol = "⌃⌥⌘→"
  },
  {
    mods = {"ctrl", "alt", "cmd"},
    key = "left",
    action = "window_space_prev",
    desc = "Send to Prev Space",
    symbol = "⌃⌥⌘←"
  },

  -- Space focus with number keys (ctrl+alt+cmd+num)
  {
    mods = {"ctrl", "alt", "cmd"},
    key = "1",
    action = "send_window_space_1",
    desc = "Send to Space 1",
    symbol = "⌃⌥⌘1"
  },
  {
    mods = {"ctrl", "alt", "cmd"},
    key = "2",
    action = "send_window_space_2",
    desc = "Send to Space 2",
    symbol = "⌃⌥⌘2"
  },
  {
    mods = {"ctrl", "alt", "cmd"},
    key = "3",
    action = "send_window_space_3",
    desc = "Send to Space 3",
    symbol = "⌃⌥⌘3"
  },
  {
    mods = {"ctrl", "alt", "cmd"},
    key = "4",
    action = "send_window_space_4",
    desc = "Send to Space 4",
    symbol = "⌃⌥⌘4"
  },
  {
    mods = {"ctrl", "alt", "cmd"},
    key = "5",
    action = "send_window_space_5",
    desc = "Send to Space 5",
    symbol = "⌃⌥⌘5"
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
  reload_sketchybar = "~/.config/sketchybar/bin/rebuild_sketchybar.sh --reload-only",
  rebuild_and_reload = "~/.config/sketchybar/bin/rebuild_sketchybar.sh",
  open_control_panel = "~/.config/sketchybar/bin/open_control_panel.sh",
  toggle_control_center = "/opt/homebrew/opt/sketchybar/bin/sketchybar --set control_center popup.drawing=toggle",

  -- Yabai
  toggle_yabai_shortcuts = "~/.config/scripts/toggle_shortcuts.sh toggle",
  toggle_layout = "~/.config/scripts/yabai_control.sh toggle-layout",
  balance_windows = "~/.config/scripts/yabai_control.sh balance",
  rotate_layout = "~/.config/scripts/yabai_control.sh space-rotate",

  -- Window
  toggle_float = "~/.config/scripts/yabai_control.sh window-toggle-float",
  toggle_fullscreen = "~/.config/scripts/yabai_control.sh window-toggle-fullscreen",
  center_window = "~/.config/scripts/yabai_control.sh window-center",
  minimize_window = "yabai -m window --minimize",
  maximize_window = "yabai -m window --toggle zoom-fullscreen",
  restore_window = "yabai -m window --toggle zoom-fullscreen",

  -- Display
  window_display_next = "~/.config/scripts/yabai_control.sh window-display-next",
  window_display_prev = "~/.config/scripts/yabai_control.sh window-display-prev",

  -- Space Movement
  window_space_next = "~/.config/scripts/yabai_control.sh window-space-next",
  window_space_prev = "~/.config/scripts/yabai_control.sh window-space-prev",
  send_window_space_1 = "~/.config/scripts/yabai_control.sh window-space 1",
  send_window_space_2 = "~/.config/scripts/yabai_control.sh window-space 2",
  send_window_space_3 = "~/.config/scripts/yabai_control.sh window-space 3",
  send_window_space_4 = "~/.config/scripts/yabai_control.sh window-space 4",
  send_window_space_5 = "~/.config/scripts/yabai_control.sh window-space 5",

  -- Layout Modes
  set_layout_float = "~/.config/scripts/space_mode.sh current float",
  set_layout_bsp = "~/.config/scripts/space_mode.sh current bsp",
  set_layout_stack = "~/.config/scripts/space_mode.sh current stack",

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

-- Get shortcut by action name
function shortcuts.get(action_name)
  for _, shortcut in ipairs(shortcuts.global) do
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
    "# SketchyBar Global Shortcuts",
    "# Generated by barista shortcuts module",
    "# Non-conflicting shortcuts using ctrl+alt combinations",
    "",
  }

  for _, shortcut in ipairs(shortcuts.global) do
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
  for _, shortcut in ipairs(shortcuts.global) do
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

  for _, shortcut in ipairs(shortcuts.global) do
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
