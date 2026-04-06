-- Detect built-in display scaling so appearance can respond to macOS "More Space".

local json = require("json")

local display_profile = {}
local CACHE_TTL_SECONDS = tonumber(os.getenv("BARISTA_DISPLAY_PROFILE_CACHE_TTL") or "10") or 10

local function cache_path()
  local home = os.getenv("HOME")
  local config_dir = os.getenv("BARISTA_CONFIG_DIR") or (home .. "/.config/sketchybar")
  return config_dir .. "/cache/display_profile.json"
end

local function load_cached_result()
  if CACHE_TTL_SECONDS <= 0 then
    return nil
  end

  local handle = io.open(cache_path(), "r")
  if not handle then
    return nil
  end

  local raw = handle:read("*a")
  handle:close()
  if type(raw) ~= "string" or raw == "" then
    return nil
  end

  local ok, decoded = pcall(json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  local timestamp = tonumber(decoded.timestamp)
  local result = decoded.result
  if not timestamp or type(result) ~= "table" then
    return nil
  end

  if (os.time() - timestamp) > CACHE_TTL_SECONDS then
    return nil
  end

  return result
end

local function write_cached_result(result)
  if CACHE_TTL_SECONDS <= 0 or type(result) ~= "table" then
    return
  end

  local path = cache_path()
  local dir = path:match("^(.*)/[^/]+$")
  if dir and dir ~= "" then
    os.execute(string.format("mkdir -p %q", dir))
  end

  local ok, encoded = pcall(json.encode, {
    timestamp = os.time(),
    result = result,
  })
  if not ok or type(encoded) ~= "string" then
    return
  end

  local handle = io.open(path, "w")
  if not handle then
    return
  end

  handle:write(encoded)
  handle:close()
end

local function parse_resolution(value)
  if type(value) ~= "string" then return nil, nil end

  local width, height = value:match("(%d+)%s*x%s*(%d+)")
  if width and height then
    return tonumber(width), tonumber(height)
  end

  width, height = value:match("spdisplays_(%d+)x(%d+)")
  if width and height then
    return tonumber(width), tonumber(height)
  end

  width, height = value:match("(%d+)x(%d+)")
  if width and height then
    return tonumber(width), tonumber(height)
  end

  return nil, nil
end

local function read_command_output(cmd)
  local handle = io.popen(cmd)
  if not handle then return nil end

  local output = handle:read("*a")
  handle:close()

  if type(output) ~= "string" or output == "" then
    return nil
  end

  return output
end

local function decode_json_line(line)
  if type(line) ~= "string" or line == "" then
    return nil
  end

  local ok, decoded = pcall(json.decode, line)
  if ok and type(decoded) == "table" then
    return decoded
  end

  return nil
end

local function is_built_in_display(display)
  if type(display) ~= "table" then return false end
  if display.spdisplays_connection_type == "spdisplays_internal" then return true end

  local display_type = tostring(display.spdisplays_display_type or ""):lower()
  return display_type:find("built%-in", 1, false) ~= nil
end

function display_profile.parse_resolution(value)
  return parse_resolution(value)
end

function display_profile.load_snapshot(reader)
  local read_output = reader or read_command_output
  local raw = read_output("system_profiler SPDisplaysDataType -json 2>/dev/null")
  if type(raw) ~= "string" or raw == "" then
    return nil
  end

  local ok, decoded = pcall(json.decode, raw)
  if ok and type(decoded) == "table" then
    return decoded
  end

  return nil
end

function display_profile.load_screen_insets(reader)
  local read_output = reader or read_command_output
  local raw = read_output([[osascript -l JavaScript <<'JXA'
ObjC.import('AppKit')
ObjC.import('Foundation')
var out = $.NSFileHandle.fileHandleWithStandardOutput
var screens = $.NSScreen.screens
for (var i = 0; i < screens.count; i++) {
  var s = screens.objectAtIndex(i)
  var f = s.frame
  var v = s.visibleFrame
  var top = (f.origin.y + f.size.height) - (v.origin.y + v.size.height)
  var bottom = v.origin.y - f.origin.y
  var line = JSON.stringify({screen:i, topInset:top, bottomInset:bottom, frameWidth:f.size.width, visibleWidth:v.size.width}) + "\n"
  out.writeData($(line).dataUsingEncoding($.NSUTF8StringEncoding))
}
JXA
]])
  if type(raw) ~= "string" or raw == "" then
    return {}
  end

  local results = {}
  for line in raw:gmatch("[^\r\n]+") do
    local decoded = decode_json_line(line)
    if decoded then
      table.insert(results, decoded)
    end
  end
  return results
end

function display_profile.analyze(snapshot)
  local result = {
    built_in_present = false,
    more_space_active = false,
    render_width = nil,
    render_height = nil,
    native_width = nil,
    native_height = nil,
    render_scale = 1.0,
    top_inset = nil,
    bottom_inset = nil,
  }

  local gpus = type(snapshot) == "table" and snapshot.SPDisplaysDataType or nil
  if type(gpus) ~= "table" then
    return result
  end

  for _, gpu in ipairs(gpus) do
    local displays = type(gpu) == "table" and gpu.spdisplays_ndrvs or nil
    if type(displays) == "table" then
      for _, display in ipairs(displays) do
        if is_built_in_display(display) then
          result.built_in_present = true

          local render_width, render_height = parse_resolution(display._spdisplays_pixels)
          local native_width, native_height = parse_resolution(display.spdisplays_pixelresolution)

          result.render_width = render_width
          result.render_height = render_height
          result.native_width = native_width
          result.native_height = native_height

          if render_width and native_width and native_width > 0 then
            result.render_scale = render_width / native_width
            result.more_space_active = render_width > native_width
          end

          return result
        end
      end
    end
  end

  return result
end

function display_profile.detect(reader)
  if reader == nil then
    local cached = load_cached_result()
    if cached then
      return cached
    end
  end

  local snapshot = display_profile.load_snapshot(reader)
  local result = display_profile.analyze(snapshot)
  local inset_rows = display_profile.load_screen_insets(reader)

  local max_top_inset = 0
  local max_bottom_inset = 0
  for _, row in ipairs(inset_rows) do
    local top_inset = tonumber(row.topInset) or 0
    local bottom_inset = tonumber(row.bottomInset) or 0
    if top_inset > max_top_inset then
      max_top_inset = top_inset
    end
    if bottom_inset > max_bottom_inset then
      max_bottom_inset = bottom_inset
    end
  end

  if max_top_inset > 0 then
    result.top_inset = max_top_inset
  end
  if max_bottom_inset > 0 then
    result.bottom_inset = max_bottom_inset
  end

  if reader == nil then
    write_cached_result(result)
  end

  return result
end

return display_profile
