#!/usr/bin/env lua
-- Comprehensive Icon Fix Script
-- Repairs all icon issues in SketchyBar configuration

-- Add project paths to Lua path
local script_dir = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_dir .. "helpers/lib/?.lua"

local HOME = os.getenv("HOME")
local CONFIG_DIR = HOME .. "/.config/sketchybar"

local json = require("json")
local STATE_FILE = CONFIG_DIR .. "/state.json"
local BACKUP_FILE = CONFIG_DIR .. "/state.json.icon_fix_backup"

-- Correct icon definitions from Nerd Fonts
local CORRECT_ICONS = {
  -- System icons (FontAwesome)
  apple = "",          -- F179
  apple_alt = "",      -- Devicons E711
  settings = "",       -- F013
  gear = "",           -- F013
  power = "",          -- F011

  -- Time icons
  clock = "",          -- F017
  calendar = "",       -- F073

  -- Hardware icons
  battery = "",        -- F240
  battery_charging = "", -- F1E6
  wifi = "󰖩",          -- Material Design F05A9
  wifi_off = "󰖪",      -- Material Design F05AA
  bluetooth = "󰂯",     -- Material Design F00AF
  volume = "",         -- F028
  volume_mute = "󰝟",   -- Material Design F075F

  -- Development (FontAwesome + Material Design)
  terminal = "",       -- F120
  code = "",           -- F121
  git = "",            -- F1D3
  github = "",         -- F113
  vscode = "󰨞",        -- Material Design F0A1E
  vim = "",            -- Seti E62B
  emacs = "",          -- Seti E632

  -- Files
  folder = "",         -- F07B
  folder_open = "",    -- F07C
  file = "",           -- F15B
  finder = "󰀶",        -- Material Design F0036

  -- Apps
  safari = "󰀹",        -- Material Design F0039
  chrome = "",         -- Devicons E743
  firefox = "",        -- Devicons E745
  messages = "󰍦",      -- Material Design F0366
  mail = "󰇮",          -- Material Design F01EE
  music = "",          -- F001

  -- Window Management
  tile = "󰆾",          -- Material Design F01BE
  stack = "󰓩",         -- Material Design F04E9
  float = "󰒄",         -- Material Design F0484
  fullscreen = "󰊓",    -- Material Design F0293

  -- Gaming
  gamepad = "󰍳",       -- Material Design F0373
  quest = "󰊠",         -- Material Design F02A0 (Triforce)
  triforce = "󰊠",      -- Material Design F02A0
  controller = "󰖺",    -- Material Design F05BA

  -- Status
  success = "",        -- F00C
  error = "",          -- F00D
  warning = "",        -- F071
  info = "",           -- F05A
  loading = "󰔟",       -- Material Design F051F

  -- System info
  cpu = "󰻠",           -- Material Design F0EE0
  memory = "󰘚",        -- Material Design F061A
  disk = "󰋊",          -- Material Design F02CA
  network = "󰖩",       -- Material Design F05A9
}

-- Menu action icons from Nerd Fonts
local MENU_ICONS = {
  -- Window actions
  show = "󰖯",          -- Material Design window
  hide = "󰍤",          -- Material Design eye-off
  quit = "",           -- FontAwesome times-circle
  force_quit = "",    -- FontAwesome bolt

  -- Window layout
  float = "󰒄",         -- Material Design float
  sticky = "󰐊",        -- Material Design pin
  fullscreen = "󰊓",    -- Material Design fullscreen
  center = "󰘍",        -- Material Design center
  zoom = "",           -- FontAwesome search-plus
  rotate = "󰑓",        -- Material Design rotate
  balance = "󰕰",       -- Material Design grid

  -- Display/Space
  display = "󰍹",       -- Material Design monitor
  space = "󱂬",         -- Material Design workspace
  send_to = "󰁔",       -- Material Design arrow-right

  -- Layout modes
  bsp = "󰆾",           -- Material Design tile
  stack_mode = "󰓩",   -- Material Design stack
  float_mode = "󰒄",   -- Material Design float
}

print("=== Comprehensive Icon Fix ===\n")

-- Backup existing state
print("1. Creating backup...")
local backup_cmd = string.format("cp %s %s", STATE_FILE, BACKUP_FILE)
os.execute(backup_cmd)
print("   ✓ Backup created: " .. BACKUP_FILE .. "\n")

-- Load current state
print("2. Loading state.json...")
local state_data
local file = io.open(STATE_FILE, "r")
if file then
  local contents = file:read("*a")
  file:close()

  local ok, data = pcall(json.decode, contents)
  if ok and type(data) == "table" then
    state_data = data
    print("   ✓ State loaded successfully\n")
  else
    print("   ✗ Failed to parse state.json")
    os.exit(1)
  end
else
  print("   ✗ Failed to read state.json")
  os.exit(1)
end

-- Fix icons section
print("3. Fixing icons...")
if not state_data.icons then
  state_data.icons = {}
end

local fixed_count = 0
local empty_icons = {}

-- Check all icons and fix empty ones
for name, icon in pairs(state_data.icons) do
  if icon == "" or icon == nil then
    table.insert(empty_icons, name)
  end
end

-- Replace empty icons with correct ones
for _, name in ipairs(empty_icons) do
  if CORRECT_ICONS[name] then
    state_data.icons[name] = CORRECT_ICONS[name]
    fixed_count = fixed_count + 1
    print(string.format("   ✓ Fixed '%s': '' → '%s'", name, CORRECT_ICONS[name]))
  else
    print(string.format("   ⚠ No replacement found for '%s'", name))
  end
end

-- Add missing essential icons
local essential_icons = {"apple", "quest", "settings", "clock", "battery"}
for _, name in ipairs(essential_icons) do
  if not state_data.icons[name] or state_data.icons[name] == "" then
    if CORRECT_ICONS[name] then
      state_data.icons[name] = CORRECT_ICONS[name]
      fixed_count = fixed_count + 1
      print(string.format("   ✓ Added '%s': '%s'", name, CORRECT_ICONS[name]))
    end
  end
end

print(string.format("\n   Total icons fixed: %d\n", fixed_count))

-- Validate icon encoding
print("4. Validating icon encoding...")
local invalid_count = 0
for name, icon in pairs(state_data.icons) do
  if icon and icon ~= "" then
    -- Check if icon is valid UTF-8
    local byte1 = icon:byte(1)
    if byte1 then
      if byte1 >= 0xF0 then
        -- Valid 4-byte UTF-8 character (Nerd Font range)
        print(string.format("   ✓ '%s': Valid UTF-8 (%d bytes)", name, #icon))
      elseif byte1 >= 0xE0 then
        -- Valid 3-byte UTF-8 character
        print(string.format("   ✓ '%s': Valid UTF-8 (%d bytes)", name, #icon))
      else
        print(string.format("   ⚠ '%s': Unexpected encoding (%d bytes)", name, #icon))
        invalid_count = invalid_count + 1
      end
    end
  end
end

if invalid_count == 0 then
  print("\n   ✓ All icons have valid encoding\n")
else
  print(string.format("\n   ⚠ %d icons have unexpected encoding\n", invalid_count))
end

-- Save fixed state
print("5. Saving fixed state...")
local ok, encoded = pcall(json.encode, state_data)
if ok then
  local out_file = io.open(STATE_FILE, "w")
  if out_file then
    out_file:write(encoded)
    out_file:close()
    print("   ✓ State saved successfully\n")
  else
    print("   ✗ Failed to write state.json")
    os.exit(1)
  end
else
  print("   ✗ Failed to encode state")
  os.exit(1)
end

-- Print summary
print("=== Fix Summary ===\n")
print(string.format("Icons fixed: %d", fixed_count))
print(string.format("Backup file: %s", BACKUP_FILE))
print("\nCurrent icon configuration:")
for name, icon in pairs(state_data.icons) do
  local bytes = #icon
  print(string.format("  %s = '%s' (%d bytes)", name, icon, bytes))
end

print("\n=== Additional Fixes Required ===\n")
print("The following files may need manual fixes:")
print("\n1. main.lua:")
print("   Change icon lookups from:")
print("     state_module.get_icon(state, 'apple', '')")
print("   To:")
print("     icon_for('apple', '')")
print("")
print("2. modules/menu.lua:")
print("   Restore icons for front_app menu items (lines 412-439)")
print("   Use MENU_ICONS table above as reference")
print("")
print("3. After fixes, reload SketchyBar:")
print("   sketchybar --reload")
print("\n=== Icon Reference ===\n")
print("Common icons available:")
for name, icon in pairs(CORRECT_ICONS) do
  if name == "apple" or name == "quest" or name == "settings" or
     name == "clock" or name == "battery" or name == "wifi" then
    print(string.format("  %s = '%s'", name, icon))
  end
end

print("\nMenu icons available:")
for name, icon in pairs(MENU_ICONS) do
  if name == "show" or name == "hide" or name == "quit" or
     name == "fullscreen" or name == "bsp" or name == "stack_mode" then
    print(string.format("  %s = '%s'", name, icon))
  end
end

print("\n✅ Icon fix complete!")
print("Restart SketchyBar to see changes: sketchybar --reload")