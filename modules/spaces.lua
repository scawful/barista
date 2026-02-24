-- Space management: display list, refresh, and yabai signal wiring.

local function create(CONFIG_DIR, PLUGIN_DIR, SKETCHYBAR_BIN, YABAI_BIN, shell_exec, yabai_available)
  local last_display_state = nil
  local display_refresh_pending = false

  local function get_display_state()
    if not yabai_available() then
      return nil
    end
    local cmd = (YABAI_BIN or "yabai") .. " -m query --displays 2>/dev/null | jq -r '[.[] | .index] | sort | join(\",\")'"
    local handle = io.popen(cmd)
    if not handle then return nil end
    local result = handle:read("*a")
    handle:close()
    return result and result:gsub("%s+", "") or nil
  end

  local function get_associated_displays()
    local function read_display_list(cmd)
      local handle = io.popen(cmd)
      if not handle then
        return nil
      end
      local output = handle:read("*a") or ""
      handle:close()
      local targets = {}
      for line in output:gmatch("[^\r\n]+") do
        local num = tonumber(line)
        if num then
          table.insert(targets, tostring(num))
        end
      end
      if #targets == 0 then
        return nil
      end
      return table.concat(targets, ",")
    end

    local list = read_display_list(string.format([[ %s --query displays 2>/dev/null | jq -r '.[]."arrangement-id"' ]], SKETCHYBAR_BIN))
    if list then
      return list
    end

    if yabai_available() and YABAI_BIN then
      list = read_display_list(string.format([[ %s -m query --displays 2>/dev/null | jq -r '.[].index' ]], YABAI_BIN))
      if list then
        return list
      end
    end

    return "active"
  end

  local function refresh_spaces()
    local cmd = string.format("CONFIG_DIR=%s %s/refresh_spaces.sh", CONFIG_DIR, PLUGIN_DIR)
    shell_exec(cmd)
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

  local function watch_spaces()
    local refresh_action = string.format("CONFIG_DIR=%s %s/refresh_spaces.sh", CONFIG_DIR, PLUGIN_DIR)
    local change_action = string.format("%s --trigger space_change; %s --trigger space_mode_refresh", SKETCHYBAR_BIN, SKETCHYBAR_BIN)

    local signal_cmds = {
      "yabai -m signal --remove sketchybar_space_change >/dev/null 2>&1 || true",
      "yabai -m signal --remove sketchybar_space_created >/dev/null 2>&1 || true",
      "yabai -m signal --remove sketchybar_space_destroyed >/dev/null 2>&1 || true",
      "yabai -m signal --remove sketchybar_display_changed >/dev/null 2>&1 || true",
      "yabai -m signal --remove sketchybar_display_added >/dev/null 2>&1 || true",
      "yabai -m signal --remove sketchybar_display_removed >/dev/null 2>&1 || true",
      string.format("yabai -m signal --add event=space_changed label=sketchybar_space_change action=%q", change_action),
      string.format("yabai -m signal --add event=space_created label=sketchybar_space_created action=%q", refresh_action),
      string.format("yabai -m signal --add event=space_destroyed label=sketchybar_space_destroyed action=%q", refresh_action),
      string.format("yabai -m signal --add event=display_changed label=sketchybar_display_changed action=%q", change_action),
      string.format("yabai -m signal --add event=display_added label=sketchybar_display_added action=%q", refresh_action),
      string.format("yabai -m signal --add event=display_removed label=sketchybar_display_removed action=%q", refresh_action),
    }
    shell_exec(table.concat(signal_cmds, "; "))
    last_display_state = get_display_state()
  end

  return {
    get_associated_displays = get_associated_displays,
    get_display_state = get_display_state,
    refresh_spaces = refresh_spaces,
    refresh_spaces_if_needed = refresh_spaces_if_needed,
    watch_spaces = watch_spaces,
  }
end

return { create = create }
