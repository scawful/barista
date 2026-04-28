local interface_extensions = {}

local locator = require("tool_locator")
local shell_utils = require("shell_utils")

local HOME = os.getenv("HOME") or ""

local function normalize_bool(value)
  if type(value) == "boolean" then
    return value
  end
  if type(value) == "number" then
    return value ~= 0
  end
  if type(value) == "string" then
    local lowered = value:lower()
    if lowered == "true" or lowered == "yes" or lowered == "1" or lowered == "on" then
      return true
    end
    if lowered == "false" or lowered == "no" or lowered == "0" or lowered == "off" then
      return false
    end
  end
  return nil
end

local function normalize_section(section)
  local value = tostring(section or ""):lower()
  if value == "" then
    return "extensions"
  end
  return value
end

local function sanitize_id(value, fallback)
  local raw = tostring(value or fallback or "extension")
  raw = raw:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if raw == "" then
    raw = tostring(fallback or "extension")
  end
  return raw
end

local function list_contains(list, value)
  if type(list) ~= "table" or value == nil or value == "" then
    return false
  end
  for _, candidate in ipairs(list) do
    if tostring(candidate) == tostring(value) then
      return true
    end
  end
  return false
end

local function merge_pack_list(target, list)
  if type(list) ~= "table" then
    return target
  end
  for _, pack in ipairs(list) do
    if pack ~= nil and pack ~= "" and not list_contains(target, pack) then
      table.insert(target, tostring(pack))
    end
  end
  return target
end

local function enabled_packs(state, extension_state)
  local packs = {}
  local machine = type(state) == "table" and type(state.machine) == "table" and state.machine or {}
  merge_pack_list(packs, machine.menu_packs)
  merge_pack_list(packs, extension_state and extension_state.packs)
  return packs
end

local function resolve_data_path(config_dir, raw_path)
  if type(raw_path) ~= "string" or raw_path == "" then
    return nil
  end
  local expanded = locator.expand_path(raw_path)
  if expanded and expanded:match("^/") then
    return expanded
  end
  return string.format("%s/%s", config_dir, raw_path)
end

local function resolve_script_path(config_dir, code_dir, raw_path)
  if type(raw_path) ~= "string" or raw_path == "" then
    return nil
  end
  local expanded = locator.expand_path(raw_path)
  if expanded and expanded:match("^/") then
    return expanded
  end
  if raw_path:sub(1, 2) == "./" then
    return string.format("%s/%s", config_dir, raw_path:sub(3))
  end
  if raw_path:match("^scripts/") or raw_path:match("^plugins/") or raw_path:match("^bin/") then
    return string.format("%s/%s", config_dir, raw_path)
  end
  return string.format("%s/%s", code_dir, raw_path)
end

local function load_json_items(path)
  if not path then
    return nil, false
  end
  local ok_json, json = pcall(require, "json")
  if not ok_json then
    return nil, false
  end
  local file = io.open(path, "r")
  if not file then
    return nil, false
  end
  local contents = file:read("*a")
  file:close()
  local ok_decode, data = pcall(json.decode, contents)
  if not ok_decode or type(data) ~= "table" then
    return nil, false
  end
  if type(data.items) == "table" then
    return data.items, true
  end
  return data, true
end

local function apply_templates(value, config_dir, code_dir)
  if type(value) ~= "string" or value == "" then
    return value
  end
  local result = value
  result = result:gsub("%%CONFIG%%", config_dir)
  result = result:gsub("%%CODE%%", code_dir)
  result = result:gsub("%%HOME%%", HOME)
  result = result:gsub("%${CONFIG_DIR}", config_dir)
  result = result:gsub("%${CODE_DIR}", code_dir)
  result = result:gsub("%${HOME}", HOME)
  return result
end

local function quoted_args(args, config_dir, code_dir)
  local parts = {}
  for _, arg in ipairs(args or {}) do
    table.insert(parts, shell_utils.shell_quote(apply_templates(tostring(arg), config_dir, code_dir)))
  end
  return table.concat(parts, " ")
end

local function action_for_entry(config_dir, code_dir, entry)
  local command = entry.command or entry.action
  if type(command) == "string" and command ~= "" then
    return apply_templates(command, config_dir, code_dir)
  end

  if type(entry.url) == "string" and entry.url ~= "" then
    return string.format("open %s", shell_utils.shell_quote(apply_templates(entry.url, config_dir, code_dir)))
  end

  if type(entry.path) == "string" and entry.path ~= "" then
    local resolved = resolve_script_path(config_dir, code_dir, apply_templates(entry.path, config_dir, code_dir))
    return string.format("open %s", shell_utils.shell_quote(resolved))
  end

  if type(entry.script) == "string" and entry.script ~= "" then
    local script_path = resolve_script_path(config_dir, code_dir, apply_templates(entry.script, config_dir, code_dir))
    local prefix = string.format(
      "env BARISTA_EXTENSION_ID=%s BARISTA_EXTENSION_PACK=%s",
      shell_utils.shell_quote(entry.id or ""),
      shell_utils.shell_quote(entry.pack or "")
    )
    local args = quoted_args(entry.args, config_dir, code_dir)
    if args ~= "" then
      return string.format("%s bash %s %s", prefix, shell_utils.shell_quote(script_path), args)
    end
    return string.format("%s bash %s", prefix, shell_utils.shell_quote(script_path))
  end

  return ""
end

local function entry_surfaces(entry)
  if type(entry.surfaces) == "table" then
    return entry.surfaces
  end
  if type(entry.surface) == "table" then
    return entry.surface
  end
  if type(entry.surface) == "string" and entry.surface ~= "" then
    return { entry.surface }
  end
  return { "apple_menu" }
end

local function surface_matches(entry, surface)
  for _, candidate in ipairs(entry_surfaces(entry)) do
    local normalized = tostring(candidate):lower()
    if normalized == "all" or normalized == tostring(surface or ""):lower() then
      return true
    end
  end
  return false
end

local function pack_allowed(entry, packs)
  local entry_packs = {}
  if type(entry.packs) == "table" then
    entry_packs = entry.packs
  elseif type(entry.pack) == "string" and entry.pack ~= "" then
    entry_packs = { entry.pack }
  end
  if #entry_packs == 0 then
    return true
  end
  for _, pack in ipairs(entry_packs) do
    if list_contains(packs, pack) then
      return true
    end
  end
  return false
end

local function normalize_entry(config_dir, code_dir, entry, index)
  if type(entry) ~= "table" then
    return nil
  end
  local enabled = normalize_bool(entry.enabled)
  if enabled == false then
    return nil
  end

  local id = sanitize_id(entry.id or entry.name or entry.label or entry.title, index)
  local action = action_for_entry(config_dir, code_dir, entry)
  local explicit_available = normalize_bool(entry.available)
  local available = action ~= ""
  if explicit_available ~= nil then
    available = explicit_available
  end

  return {
    id = id,
    label = entry.label or entry.title or entry.name or ("Extension " .. tostring(index)),
    icon = entry.icon or "󰐕",
    icon_color = entry.icon_color or entry.color or "0xff89dceb",
    label_color = entry.label_color,
    action = action,
    build_action = apply_templates(entry.build_action or "", config_dir, code_dir),
    build_label = entry.build_label,
    missing_label = entry.missing_label,
    missing_message = entry.missing_message,
    missing_title = entry.missing_title,
    missing_action = apply_templates(entry.missing_action or "", config_dir, code_dir),
    shortcut = entry.shortcut,
    section = normalize_section(entry.section),
    available = available,
    enabled = enabled ~= false,
    order = tonumber(entry.order) or (1000 + index),
    pack = entry.pack,
    packs = entry.packs,
    surfaces = entry_surfaces(entry),
  }
end

function interface_extensions.load(config_dir, code_dir, state)
  config_dir = config_dir or locator.resolve_config_dir()
  code_dir = code_dir or locator.resolve_code_dir({ state = state })
  local menus = type(state) == "table" and type(state.menus) == "table" and state.menus or {}
  local extension_state = type(menus.extensions) == "table" and menus.extensions or {}
  if extension_state.enabled == false then
    return {
      enabled = false,
      items = {},
      files = {},
      packs = enabled_packs(state, extension_state),
    }
  end

  local raw_items = {}
  local files = {}

  local function append_file(raw_path)
    local resolved = resolve_data_path(config_dir, raw_path)
    if not resolved then
      return
    end
    table.insert(files, resolved)
    local file_items, loaded = load_json_items(resolved)
    if loaded and type(file_items) == "table" then
      for _, item in ipairs(file_items) do
        table.insert(raw_items, item)
      end
    end
  end

  if type(extension_state.file) == "string" and extension_state.file ~= "" then
    append_file(extension_state.file)
  else
    append_file("data/interface_extensions.local.json")
  end
  if type(extension_state.files) == "table" then
    for _, raw_path in ipairs(extension_state.files) do
      append_file(raw_path)
    end
  end
  if type(extension_state.items) == "table" then
    for _, item in ipairs(extension_state.items) do
      table.insert(raw_items, item)
    end
  end

  local packs = enabled_packs(state, extension_state)
  local normalized = {}
  for index, entry in ipairs(raw_items) do
    if pack_allowed(entry, packs) then
      local item = normalize_entry(config_dir, code_dir, entry, index)
      if item then
        table.insert(normalized, item)
      end
    end
  end

  table.sort(normalized, function(a, b)
    if a.section ~= b.section then
      return a.section < b.section
    end
    if a.order == b.order then
      return a.label < b.label
    end
    return a.order < b.order
  end)

  return {
    enabled = true,
    file = extension_state.file or "data/interface_extensions.local.json",
    files = files,
    packs = packs,
    items = normalized,
  }
end

function interface_extensions.for_surface(config_dir, code_dir, state, surface)
  local loaded = interface_extensions.load(config_dir, code_dir, state)
  local items = {}
  for _, item in ipairs(loaded.items or {}) do
    if surface_matches(item, surface) then
      table.insert(items, item)
    end
  end
  table.sort(items, function(a, b)
    if a.order == b.order then
      return a.label < b.label
    end
    return a.order < b.order
  end)
  return items
end

return interface_extensions
