local project_shortcuts = {}

local locator = require("tool_locator")
local utf8lib = utf8

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

local function valid_utf8(value)
  if type(value) ~= "string" or value == "" then
    return false
  end
  if not utf8lib or type(utf8lib.len) ~= "function" then
    return true
  end
  return pcall(utf8lib.len, value)
end

local function shell_quote(value)
  return string.format("%q", tostring(value or ""))
end

local function open_terminal(command)
  if not command or command == "" then
    return ""
  end
  return string.format("osascript -e 'tell application \"Terminal\" to do script %q'", command)
end

local function load_json_array_file(path)
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

  return data, true
end

local function pretty_label(value)
  local raw = tostring(value or "")
  raw = raw:gsub("^%./", "")
  raw = raw:gsub(".*/", "")
  raw = raw:gsub("[_-]+", " ")
  raw = raw:gsub("%s+", " ")
  raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
  if raw == "" then
    return "Project"
  end
  raw = raw:gsub("(%a)([%w']*)", function(first, rest)
    return first:upper() .. rest
  end)
  raw = raw:gsub("Afs", "AFS")
  raw = raw:gsub("Ui", "UI")
  raw = raw:gsub("Ai", "AI")
  raw = raw:gsub("Oos", "OoS")
  return raw
end

local function entry_id(entry, index)
  local raw = entry.id or entry.name or entry.label or entry.path or ("project_" .. tostring(index))
  raw = tostring(raw):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if raw == "" then
    raw = "project_" .. tostring(index)
  end
  return raw
end

local function default_icon(entry)
  local path = tostring(entry.path or entry.rel_path or entry.label or ""):lower()
  if path:match("afs") then
    return "󰈙"
  end
  if path:match("yaze") then
    return "󰯙"
  end
  if path:match("oracle") then
    return "󰊕"
  end
  if path:match("premia") then
    return "󰃬"
  end
  if path:match("halext") then
    return "󰖟"
  end
  if path:match("janice") then
    return "󰭹"
  end
  if path:match("echo") then
    return "󰊠"
  end
  if path:match("barista") then
    return "󰓹"
  end
  if path:match("mesen") then
    return "󰁆"
  end
  if path:match("manual") then
    return "󰋜"
  end
  if path == "ai" or path:match("/ai$") or path:match("/ai/") then
    return "󰚩"
  end
  return "󰉋"
end

local function project_palette(entry)
  local key = tostring(entry.id or entry.path or entry.rel_path or entry.label or ""):lower()
  if key:match("afs_suite") then
    return "0xff89dceb", "0xffbfeaf4"
  end
  if key:match("afs") then
    return "0xff74c7ec", "0xffa9dbf1"
  end
  if key:match("janice") then
    return "0xfff5c2e7", "0xfff8d6ee"
  end
  if key:match("yaze") then
    return "0xff89b4fa", "0xffb6d0fb"
  end
  if key:match("oracle") then
    return "0xffa6e3a1", "0xffc5edc1"
  end
  if key:match("premia") then
    return "0xff94e2d5", "0xffc7eee8"
  end
  if key:match("barista") then
    return "0xfffab387", "0xfff8ceb4"
  end
  if key == "ai" or key:match("/ai$") or key:match("/ai/") then
    return "0xffcba6f7", "0xffdfc9f7"
  end
  return "0xffcdd6f4", "0xffe8edf7"
end

local function normalize_section(section)
  local value = tostring(section or ""):lower()
  if value == "" or value == "projects" then
    return "apps"
  end
  return value
end

function project_shortcuts.resolve_data_path(config_dir, raw_path)
  if type(raw_path) ~= "string" or raw_path == "" then
    return nil
  end

  local expanded = locator.expand_path(raw_path)
  if expanded and expanded:match("^/") then
    return expanded
  end

  return string.format("%s/%s", config_dir, raw_path)
end

function project_shortcuts.resolve_project_path(code_dir, raw_path)
  if type(raw_path) ~= "string" or raw_path == "" then
    return nil
  end

  local expanded = locator.expand_path(raw_path)
  if expanded and expanded:match("^/") then
    return expanded
  end

  if raw_path:sub(1, 2) == "./" then
    raw_path = raw_path:sub(3)
  end

  return string.format("%s/%s", code_dir, raw_path)
end

function project_shortcuts.action_for_path(path, mode)
  if not path or path == "" then
    return ""
  end

  local selected_mode = tostring(mode or "terminal"):lower()
  if selected_mode == "finder" or selected_mode == "open" then
    return string.format("open %s", shell_quote(path))
  end

  if selected_mode == "code" then
    local code_cmd = locator.command_path("code")
    if code_cmd then
      return string.format("%s %s", shell_quote(code_cmd), shell_quote(path))
    end
    return string.format("open %s", shell_quote(path))
  end

  return open_terminal(string.format("cd %s", shell_quote(path)))
end

function project_shortcuts.normalize_entry(code_dir, default_action, entry, index)
  entry = type(entry) == "table" and entry or {}
  local raw_path = entry.path or entry.rel_path
  local resolved_path = project_shortcuts.resolve_project_path(code_dir, raw_path)
  local path_available = resolved_path and (
    locator.path_exists(resolved_path, true) or locator.path_exists(resolved_path, false)
  ) or false

  local action = entry.action or entry.command or ""
  if action == "" and path_available then
    action = project_shortcuts.action_for_path(
      resolved_path,
      entry.open_mode or entry.action_mode or default_action
    )
  end

  local label = entry.label or entry.name or pretty_label(raw_path or entry.id or tostring(index))
  local available = action ~= "" and (path_available or not raw_path)
  local enabled = normalize_bool(entry.enabled)
  local default_icon_color, default_label_color = project_palette(entry)
  if enabled == nil then
    enabled = true
  end

  return {
    id = entry_id(entry, index),
    label = label,
    icon = valid_utf8(entry.icon) and entry.icon or default_icon(entry),
    icon_color = entry.icon_color or entry.color or default_icon_color,
    label_color = entry.label_color or default_label_color,
    action = action,
    shortcut = entry.shortcut,
    section = normalize_section(entry.section),
    available = available,
    missing = raw_path ~= nil and raw_path ~= "" and not path_available,
    enabled = enabled,
    order = tonumber(entry.order) or (100 + index),
    path = resolved_path,
    raw_path = raw_path,
  }
end

function project_shortcuts.load(config_dir, code_dir, state)
  local menus = type(state) == "table" and type(state.menus) == "table" and state.menus or {}
  local menu_state = type(menus.apps) == "table" and menus.apps
    or (type(menus.projects) == "table" and menus.projects)
    or {}

  local file_path = menu_state.file or "data/project_shortcuts.json"
  local resolved_file = project_shortcuts.resolve_data_path(config_dir, file_path)
  local file_entries, file_loaded = load_json_array_file(resolved_file)
  local items = type(menu_state.items) == "table" and menu_state.items or {}
  if file_loaded then
    items = file_entries
  end

  local normalized = {}
  for index, entry in ipairs(items or {}) do
    local item = project_shortcuts.normalize_entry(
      code_dir,
      menu_state.default_action or "terminal",
      entry,
      index
    )
    if item.enabled ~= false then
      table.insert(normalized, item)
    end
  end

  return {
    enabled = menu_state.enabled ~= false,
    file = file_path,
    resolved_file = resolved_file,
    default_action = menu_state.default_action or "terminal",
    items = normalized,
  }
end

return project_shortcuts
