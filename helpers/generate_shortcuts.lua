#!/usr/bin/env lua

-- Generate skhd shortcuts plus the Help Center workflow reference.
-- Usage: lua generate_shortcuts.lua [skhd_output] [workflow_json_output]

local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
package.path = package.path
  .. ";" .. CONFIG_DIR .. "/modules/?.lua"
  .. ";" .. CONFIG_DIR .. "/helpers/lib/?.lua"

local shortcuts = require("shortcuts")
local json = require("json")

local output_file = arg[1] or HOME .. "/.config/skhd/barista_shortcuts.conf"
local workflow_extras = os.getenv("BARISTA_WORKFLOW_EXTRAS")
if workflow_extras == "" then
  workflow_extras = nil
end
local workflow_output = arg[2] or os.getenv("BARISTA_WORKFLOW_OUTPUT")
if not workflow_output or workflow_output == "" then
  local filename = workflow_extras
    and "workflow_shortcuts.local.generated.json"
    or "workflow_shortcuts.json"
  workflow_output = CONFIG_DIR .. "/data/" .. filename
end

local function read_json(path)
  local file = io.open(path, "r")
  if not file then
    return nil, "Could not open workflow supplement: " .. path
  end
  local content = file:read("*a")
  file:close()
  local ok, decoded = pcall(json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return nil, "Invalid workflow supplement: " .. path
  end
  return decoded
end

local function is_array(value)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    count = count + 1
  end
  return count == #value
end

local preferred_key_order = {
  generated = 1,
  keymap = 2,
  actions = 3,
  docs = 4,
  generator = 5,
  source = 6,
  supplement = 7,
  section = 8,
  items = 9,
  keys = 10,
  description = 11,
  action = 12,
  id = 13,
  title = 14,
  command = 15,
  path = 16,
}

local function pretty_json(value, depth)
  depth = depth or 0
  local value_type = type(value)
  if value_type ~= "table" then
    return json.encode(value)
  end

  local indent = string.rep("  ", depth)
  local child_indent = string.rep("  ", depth + 1)
  if is_array(value) then
    if #value == 0 then
      return "[]"
    end
    local rows = {}
    for _, item in ipairs(value) do
      table.insert(rows, child_indent .. pretty_json(item, depth + 1))
    end
    return "[\n" .. table.concat(rows, ",\n") .. "\n" .. indent .. "]"
  end

  local keys = {}
  for key in pairs(value) do
    table.insert(keys, key)
  end
  table.sort(keys, function(a, b)
    local rank_a = preferred_key_order[a] or 1000
    local rank_b = preferred_key_order[b] or 1000
    if rank_a == rank_b then
      return tostring(a) < tostring(b)
    end
    return rank_a < rank_b
  end)
  if #keys == 0 then
    return "{}"
  end
  local rows = {}
  for _, key in ipairs(keys) do
    table.insert(rows, string.format(
      "%s%s: %s",
      child_indent,
      json.encode(key),
      pretty_json(value[key], depth + 1)
    ))
  end
  return "{\n" .. table.concat(rows, ",\n") .. "\n" .. indent .. "}"
end

local function build_workflow_data(extras, has_supplement)
  local generated_items = {}
  for _, shortcut in ipairs(shortcuts.list_declared()) do
    local item = {
      keys = shortcut.symbol,
      description = shortcut.desc,
      action = shortcut.action,
    }
    table.insert(generated_items, item)
  end

  local keymap = {
    {
      section = "Barista (generated)",
      source = "modules/shortcuts.lua",
      items = generated_items,
    },
  }
  for _, section in ipairs(extras.keymap or {}) do
    table.insert(keymap, section)
  end

  local generated = {
    generator = "helpers/generate_shortcuts.lua",
    source = "modules/shortcuts.lua",
  }
  if has_supplement then
    generated.supplement = "BARISTA_WORKFLOW_EXTRAS"
  end

  return {
    generated = generated,
    keymap = keymap,
    actions = extras.actions or {},
    docs = extras.docs or {},
  }
end

local function write_atomic(path, content)
  local temp_path = string.format("%s.tmp.%d", path, os.time())
  local file = io.open(temp_path, "w")
  if not file then
    return false, "Could not open file for writing: " .. temp_path
  end
  file:write(content)
  file:write("\n")
  file:close()
  local ok, err = os.rename(temp_path, path)
  if not ok then
    os.remove(temp_path)
    return false, "Could not replace workflow data: " .. tostring(err)
  end
  return true, path
end

local function write_workflow_data()
  local extras = {}
  if workflow_extras then
    local read_error
    extras, read_error = read_json(workflow_extras)
    if not extras then
      return false, read_error
    end
  end
  return write_atomic(
    workflow_output,
    pretty_json(build_workflow_data(extras, workflow_extras ~= nil))
  )
end

print("Generating SketchyBar shortcuts configuration...")
print("Output file: " .. output_file)
print("Workflow data: " .. workflow_output)
print("Workflow supplement: " .. (workflow_extras and "machine-local override" or "none"))

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
local workflow_success, workflow_result = write_workflow_data()

if success and workflow_success then
  print("✅ Successfully generated shortcuts configuration")
  print("📄 File: " .. result)
  print("📄 Workflow: " .. workflow_result)
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
  print("❌ Error: " .. tostring(success and workflow_result or result))
  os.exit(1)
end
