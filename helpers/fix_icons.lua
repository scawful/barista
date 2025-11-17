#!/usr/bin/env lua

-- Fix Icons Script
-- Properly populate icons.lua with correct Nerd Font glyphs

local function utf8_char(codepoint)
  if codepoint < 0x80 then
    return string.char(codepoint)
  elseif codepoint < 0x800 then
    return string.char(
      0xC0 + math.floor(codepoint / 0x40),
      0x80 + (codepoint % 0x40)
    )
  elseif codepoint < 0x10000 then
    return string.char(
      0xE0 + math.floor(codepoint / 0x1000),
      0x80 + (math.floor(codepoint / 0x40) % 0x40),
      0x80 + (codepoint % 0x40)
    )
  else
    return string.char(
      0xF0 + math.floor(codepoint / 0x40000),
      0x80 + (math.floor(codepoint / 0x1000) % 0x40),
      0x80 + (math.floor(codepoint / 0x40) % 0x40),
      0x80 + (codepoint % 0x40)
    )
  end
end

-- Nerd Font icon mappings (codepoints in hex)
local icon_fixes = {
  -- System icons that need fixing
  {category = "system", name = "apple", codepoint = 0xF179},
  {category = "system", name = "apple_alt", codepoint = 0xF302},
  {category = "system", name = "settings", codepoint = 0xF493},
  {category = "system", name = "gear", codepoint = 0xF013},
  {category = "system", name = "power", codepoint = 0xF011},
  {category = "system", name = "bell", codepoint = 0xF0F3},
  {category = "system", name = "calendar", codepoint = 0xF073},
  {category = "system", name = "clock", codepoint = 0xF017},
  {category = "system", name = "battery", codepoint = 0xF240},
  {category = "system", name = "battery_charging", codepoint = 0xF1E6},
  {category = "system", name = "volume", codepoint = 0xF027},

  -- Development icons
  {category = "development", name = "code", codepoint = 0xF121},
  {category = "development", name = "terminal", codepoint = 0xF120},
  {category = "development", name = "vim", codepoint = 0xF1C5},
  {category = "development", name = "emacs", codepoint = 0xF268},
  {category = "development", name = "git", codepoint = 0xF1D3},
  {category = "development", name = "github", codepoint = 0xF09B},
  {category = "development", name = "gitlab", codepoint = 0xF296},
  {category = "development", name = "branch", codepoint = 0xF126},
  {category = "development", name = "commit", codepoint = 0xF417},
  {category = "development", name = "pull_request", codepoint = 0xF3E9},
  {category = "development", name = "bug", codepoint = 0xF188},
  {category = "development", name = "debug", codepoint = 0xF05E},
  {category = "development", name = "build", codepoint = 0xF0AD},
  {category = "development", name = "package", codepoint = 0xF187},
  {category = "development", name = "docker", codepoint = 0xF308},
  {category = "development", name = "database", codepoint = 0xF1C0},
  {category = "development", name = "json", codepoint = 0xF668},
}

-- Load current icons module
package.path = package.path .. ";../modules/?.lua"
local icons = require("icons")

print("Fixing icons...")
local fixed_count = 0

for _, fix in ipairs(icon_fixes) do
  if icons.categories[fix.category] then
    local current = icons.categories[fix.category][fix.name]
    if not current or current == "" then
      local glyph = utf8_char(fix.codepoint)
      icons.categories[fix.category][fix.name] = glyph
      print(string.format("  Fixed: %s.%s = U+%04X", fix.category, fix.name, fix.codepoint))
      fixed_count = fixed_count + 1
    end
  end
end

print(string.format("\nFixed %d icons", fixed_count))

-- Write back to file
local output = io.open("../modules/icons.lua", "w")
output:write("-- Icon Library Module\n")
output:write("-- Comprehensive Nerd Font icon library with categories\n")
output:write("\n")
output:write("local icons = {}\n")
output:write("\n")
output:write("-- Icon categories for easy browsing\n")
output:write("icons.categories = {\n")

local categories = {}
for cat in pairs(icons.categories) do
  table.insert(categories, cat)
end
table.sort(categories)

for _, category in ipairs(categories) do
  output:write(string.format("  %s = {\n", category))

  local icon_names = {}
  for name in pairs(icons.categories[category]) do
    table.insert(icon_names, name)
  end
  table.sort(icon_names)

  for _, name in ipairs(icon_names) do
    local glyph = icons.categories[category][name]
    output:write(string.format("    %s = \"%s\",\n", name, glyph))
  end

  output:write("  },\n\n")
end

output:write("}\n")
output:write("\n")

-- Add all the functions back
output:write([[
-- Flattened icon list for searching
function icons.get_all()
  local all = {}
  for category, category_icons in pairs(icons.categories) do
    for name, glyph in pairs(category_icons) do
      table.insert(all, {
        name = name,
        glyph = glyph,
        category = category,
      })
    end
  end
  return all
end

-- Search icons by name
function icons.search(query)
  if not query or query == "" then
    return icons.get_all()
  end

  local results = {}
  local lower_query = query:lower()

  for category, category_icons in pairs(icons.categories) do
    for name, glyph in pairs(category_icons) do
      if name:lower():find(lower_query, 1, true) or category:lower():find(lower_query, 1, true) then
        table.insert(results, {
          name = name,
          glyph = glyph,
          category = category,
        })
      end
    end
  end

  return results
end

-- Get icon by category and name
function icons.get(category, name)
  if icons.categories[category] then
    return icons.categories[category][name]
  end
  return nil
end

-- Get icon by name (searches all categories)
function icons.find(name)
  for category, category_icons in pairs(icons.categories) do
    if category_icons[name] then
      return category_icons[name]
    end
  end
  return nil
end

-- Get all icons from a category
function icons.get_category(category)
  return icons.categories[category] or {}
end

-- List all category names
function icons.list_categories()
  local categories = {}
  for category, _ in pairs(icons.categories) do
    table.insert(categories, category)
  end
  table.sort(categories)
  return categories
end

-- Check if an icon exists
function icons.exists(category, name)
  return icons.get(category, name) ~= nil
end

-- Get a random icon from a category
function icons.random(category)
  local category_icons = icons.get_category(category)
  local icon_list = {}
  for _, glyph in pairs(category_icons) do
    table.insert(icon_list, glyph)
  end
  if #icon_list > 0 then
    math.randomseed(os.time())
    return icon_list[math.random(#icon_list)]
  end
  return nil
end

-- Export for GUI/scripts
function icons.export_json()
  local json = require("json")
  local all_icons = icons.get_all()
  return json.encode(all_icons)
end

-- Common icon sets for quick access
icons.common = {
  -- Menu icons
  menu_apple = icons.categories.system.apple,
  menu_settings = icons.categories.system.settings,
  menu_power = icons.categories.system.power,

  -- Status icons
  status_ok = icons.categories.status.success,
  status_error = icons.categories.status.error,
  status_warning = icons.categories.status.warning,

  -- App icons
  app_terminal = icons.categories.apps.terminal_app,
  app_finder = icons.categories.apps.finder,
  app_vscode = icons.categories.development.vscode,

  -- Window management
  wm_tile = icons.categories.window_management.tile,
  wm_stack = icons.categories.window_management.stack,
  wm_float = icons.categories.window_management.float,
}

return icons
]])

output:close()

print("\n✅ Icons module updated successfully!")
print("Run: sketchybar --reload")
