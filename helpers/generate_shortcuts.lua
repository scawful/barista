#!/usr/bin/env lua

-- Generate skhd shortcuts configuration
-- Usage: lua generate_shortcuts.lua [output_file]

local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
package.path = package.path .. ";" .. CONFIG_DIR .. "/modules/?.lua"

local shortcuts = require("shortcuts")

-- Get output path
local output_file = arg[1] or HOME .. "/.config/skhd/barista_shortcuts.conf"

print("Generating SketchyBar shortcuts configuration...")
print("Output file: " .. output_file)

-- Check for conflicts
local conflicts = shortcuts.check_conflicts()
if #conflicts > 0 then
  print("\n⚠️  WARNING: Found shortcut conflicts:")
  for _, conflict in ipairs(conflicts) do
    print(string.format("  %s: %s", conflict.combo, table.concat(conflict.actions, ", ")))
  end
  print("")
end

-- Generate and write configuration
local success, result = shortcuts.write_skhd_config(output_file)

if success then
  print("✅ Successfully generated shortcuts configuration")
  print("📄 File: " .. result)
  print("\nTo use these shortcuts:")
  print("1. Include in your ~/.config/skhd/skhdrc:")
  print("   .load \"" .. result .. "\"")
  print("\n2. Restart skhd:")
  print("   brew services restart skhd")
  print("\n3. Or reload configuration:")
  print("   skhd --reload")
  print("\n📋 Available shortcuts:")

  local list = shortcuts.list_all()
  for _, shortcut in ipairs(list) do
    print(string.format("  %s - %s", shortcut.symbol, shortcut.desc))
  end
else
  print("❌ Error: " .. result)
  os.exit(1)
end
