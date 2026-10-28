-- Space management: display list, refresh, and yabai signal wiring.

local function normalize_display_ids(json_text, key, decode)
  if type(json_text) ~= "string" or type(key) ~= "string" or key == "" then
    return nil
  end

  if type(decode) ~= "function" then
    local ok_json, json = pcall(require, "json")
    if not ok_json or type(json.decode) ~= "function" then
      return nil
    end
    decode = json.decode
  end

  local ok_decode, payload = pcall(decode, json_text)
  if not ok_decode or type(payload) ~= "table" then
    return nil
  end

  local seen = {}
  local values = {}

  local function append(raw)
    local numeric = type(raw) == "number" and raw or (type(raw) == "string" and tonumber(raw) or nil)
    if numeric and numeric > 0 and numeric % 1 == 0 and not seen[numeric] then
      seen[numeric] = true
      table.insert(values, numeric)
    end
  end

  local function visit(value)
    if type(value) ~= "table" then
      return
    end
    if value[key] ~= nil then
      append(value[key])
    end
    for child_key, child in pairs(value) do
      if child_key ~= key and type(child) == "table" then
        visit(child)
      end
    end
  end

  visit(payload)
  if #values == 0 then
    return nil
  end
  table.sort(values)
  for index, value in ipairs(values) do
    values[index] = tostring(value)
  end
  return table.concat(values, ",")
end

local function default_signal_replay_path()
  local home = os.getenv("HOME")
  return home and (home .. "/.local/state/barista/yabai_signals.sh") or nil
end

local function create(CONFIG_DIR, PLUGIN_DIR, SKETCHYBAR_BIN, YABAI_BIN, shell_exec, yabai_available, lua_only,
                      signal_replay_path)
  signal_replay_path = signal_replay_path or default_signal_replay_path()
  local last_display_state = nil
  local display_refresh_pending = false
  local runtime_prefix = lua_only and "/usr/bin/env BARISTA_LUA_ONLY=1 " or ""

  local function get_display_state()
    if not yabai_available() then
      return nil
    end
    local cmd = string.format("%q -m query --displays 2>/dev/null", YABAI_BIN or "yabai")
    local handle = io.popen(cmd)
    if not handle then return nil end
    local result = handle:read("*a") or ""
    handle:close()
    return normalize_display_ids(result, "index")
  end

  local function get_associated_spaces()
    local function parse_space_indexes(cmd)
      local handle = io.popen(cmd)
      if not handle then
        return nil
      end
      local output = handle:read("*a") or ""
      handle:close()
      if output == "" then
        return nil
      end
      local ok_json, json = pcall(require, "json")
      if not ok_json or type(json.decode) ~= "function" then
        return nil
      end
      local ok, decoded = pcall(json.decode, output)
      if not ok or type(decoded) ~= "table" then
        return nil
      end
      local ids = {}
      local seen = {}
      for _, entry in ipairs(decoded) do
        local index = nil
        if type(entry) == "table" then
          index = tonumber(entry.index or entry["arrangement-id"] or entry.id)
        elseif type(entry) == "number" then
          index = entry
        end
        if index and index > 0 and index == math.floor(index) and not seen[index] then
          seen[index] = true
          table.insert(ids, index)
        end
      end
      if #ids == 0 then
        return nil
      end
      table.sort(ids)
      local parts = {}
      for _, id in ipairs(ids) do
        table.insert(parts, tostring(id))
      end
      return table.concat(parts, ",")
    end

    if yabai_available() and YABAI_BIN then
      local list = parse_space_indexes(
        string.format("%q -m query --spaces 2>/dev/null", YABAI_BIN)
      )
      if list then
        return list
      end
    end

    local list = parse_space_indexes(
      string.format("%q --query spaces 2>/dev/null", SKETCHYBAR_BIN)
    )
    if list then
      return list
    end

    -- SketchyBar treats associated_space=all as a no-op once ignore_association
    -- is off; fall back to a generous explicit range so display-scoped widgets
    -- still appear on every space of their target monitor.
    return "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16"
  end

  local function get_associated_displays()
    local function parse_display_query(cmd, key)
      local handle = io.popen(cmd)
      if not handle then
        return nil
      end
      local output = handle:read("*a") or ""
      handle:close()
      return normalize_display_ids(output, key)
    end

    local list = parse_display_query(
      string.format("%q --query displays 2>/dev/null", SKETCHYBAR_BIN),
      "arrangement-id"
    )
    if list then
      return list
    end

    if yabai_available() and YABAI_BIN then
      list = parse_display_query(
        string.format("%q -m query --displays 2>/dev/null", YABAI_BIN),
        "index"
      )
      if list then
        return list
      end
    end

    return "active"
  end

  local function refresh_spaces()
    local cmd = string.format("%sCONFIG_DIR=%q %q", runtime_prefix, CONFIG_DIR, PLUGIN_DIR .. "/refresh_spaces.sh")
    shell_exec(cmd)
  end

  local function build_refresh_action(reason)
    local refresh_script = PLUGIN_DIR .. "/refresh_spaces.sh"
    return string.format(
      "%sBARISTA_REASON=%q CONFIG_DIR=%q %q",
      runtime_prefix,
      reason or "topology_refresh",
      CONFIG_DIR,
      refresh_script
    )
  end

  local function refresh_spaces_if_needed()
    local current_state = get_display_state()
    if current_state and current_state ~= last_display_state then
      last_display_state = current_state
      refresh_spaces()
      display_refresh_pending = false
    else
      display_refresh_pending = false
    end
  end

  local function build_mission_control_action(phase)
    return string.format(
      "%sCONFIG_DIR=%q %q %s",
      runtime_prefix,
      CONFIG_DIR,
      PLUGIN_DIR .. "/mission_control_guard.sh",
      phase
    )
  end

  -- Yabai forgets every signal when it restarts, and the bar registers them
  -- only when it loads. The yabairc replays this file after a restart.
  local function save_signal_replay(signal_cmds)
    if not signal_replay_path then
      return
    end
    local tmp = signal_replay_path .. ".tmp"
    local file = io.open(tmp, "w")
    if not file then
      os.execute(string.format("mkdir -p %q", signal_replay_path:match("^(.*)/[^/]+$") or "."))
      file = io.open(tmp, "w")
      if not file then
        return
      end
    end
    file:write("#!/bin/sh\n# Generated by modules/spaces.lua watch_spaces().\n", table.concat(signal_cmds, "\n"), "\n")
    file:close()
    if not os.rename(tmp, signal_replay_path) then
      os.remove(tmp)
    end
  end

  local function watch_spaces()
    local active_refresh_action = build_refresh_action("space_changed")
    local yabai_cmd = string.format("%q -m signal", YABAI_BIN or "yabai")

    local signal_cmds = {
      string.format("%s --remove sketchybar_space_change >/dev/null 2>&1 || true", yabai_cmd),
      string.format("%s --remove sketchybar_space_created >/dev/null 2>&1 || true", yabai_cmd),
      string.format("%s --remove sketchybar_space_destroyed >/dev/null 2>&1 || true", yabai_cmd),
      string.format("%s --remove sketchybar_display_changed >/dev/null 2>&1 || true", yabai_cmd),
      string.format("%s --remove sketchybar_display_added >/dev/null 2>&1 || true", yabai_cmd),
      string.format("%s --remove sketchybar_display_removed >/dev/null 2>&1 || true", yabai_cmd),
      string.format("%s --remove sketchybar_mission_control_enter >/dev/null 2>&1 || true", yabai_cmd),
      string.format("%s --remove sketchybar_mission_control_exit >/dev/null 2>&1 || true", yabai_cmd),
      string.format("%s --add event=space_changed label=sketchybar_space_change action=%q", yabai_cmd, active_refresh_action),
      string.format("%s --add event=space_created label=sketchybar_space_created action=%q", yabai_cmd, build_refresh_action("space_created")),
      string.format("%s --add event=space_destroyed label=sketchybar_space_destroyed action=%q", yabai_cmd, build_refresh_action("space_destroyed")),
      string.format("%s --add event=display_changed label=sketchybar_display_changed action=%q", yabai_cmd, build_refresh_action("display_changed")),
      string.format("%s --add event=display_added label=sketchybar_display_added action=%q", yabai_cmd, build_refresh_action("display_added")),
      string.format("%s --add event=display_removed label=sketchybar_display_removed action=%q", yabai_cmd, build_refresh_action("display_removed")),
      string.format("%s --add event=mission_control_enter label=sketchybar_mission_control_enter action=%q", yabai_cmd, build_mission_control_action("enter")),
      string.format("%s --add event=mission_control_exit label=sketchybar_mission_control_exit action=%q", yabai_cmd, build_mission_control_action("exit")),
    }
    shell_exec(table.concat(signal_cmds, "; "))
    save_signal_replay(signal_cmds)
    last_display_state = get_display_state()
  end

  return {
    get_associated_displays = get_associated_displays,
    get_associated_spaces = get_associated_spaces,
    get_display_state = get_display_state,
    refresh_spaces = refresh_spaces,
    refresh_spaces_if_needed = refresh_spaces_if_needed,
    watch_spaces = watch_spaces,
  }
end

return {
  create = create,
  normalize_display_ids = normalize_display_ids,
}
