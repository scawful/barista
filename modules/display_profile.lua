-- Detect built-in display scaling and multi-display bar density.
-- Density follows the narrowest logical display width so a portrait/rotated
-- external monitor does not let left and right items intersect.

local json = require("json")

local display_profile = {}
local CACHE_TTL_SECONDS = tonumber(os.getenv("BARISTA_DISPLAY_PROFILE_CACHE_TTL") or "10") or 10

-- Logical point widths: portrait externals often land near 800–1080.
local DENSE_MAX_WIDTH = tonumber(os.getenv("BARISTA_DENSE_MAX_WIDTH") or "1000") or 1000
local COMPACT_MAX_WIDTH = tonumber(os.getenv("BARISTA_COMPACT_MAX_WIDTH") or "1400") or 1400

local function cache_path()
  local home = os.getenv("HOME")
  local config_dir = os.getenv("BARISTA_CONFIG_DIR") or (home .. "/.config/sketchybar")
  return config_dir .. "/cache/display_profile.json"
end

-- system_profiler and the JXA inset probe cost hundreds of milliseconds, so a
-- cache whose display signature still matches stays valid past the TTL.
local function frames_signature(frames)
  local parts = {}
  for _, frame in ipairs(frames or {}) do
    if frame.width and frame.height then
      table.insert(parts, string.format("%s:%dx%d", tostring(frame.id), math.floor(frame.width), math.floor(frame.height)))
    end
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function load_cached_result(signature)
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

  if signature and signature ~= "" and decoded.signature == signature then
    return result
  end

  if (os.time() - timestamp) > CACHE_TTL_SECONDS then
    return nil
  end

  return result
end

local function write_cached_result(result, signature)
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
    signature = signature,
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

local function join_ids(ids)
  if type(ids) ~= "table" or #ids == 0 then
    return ""
  end
  local parts = {}
  for _, id in ipairs(ids) do
    table.insert(parts, tostring(id))
  end
  return table.concat(parts, ",")
end

function display_profile.parse_resolution(value)
  return parse_resolution(value)
end

function display_profile.density_for_width(width, opts)
  opts = opts or {}
  local dense_max = tonumber(opts.dense_max_width) or DENSE_MAX_WIDTH
  local compact_max = tonumber(opts.compact_max_width) or COMPACT_MAX_WIDTH
  local w = tonumber(width)
  if not w or w <= 0 then
    return "comfortable"
  end
  if w < dense_max then
    return "dense"
  end
  if w < compact_max then
    return "compact"
  end
  return "comfortable"
end

function display_profile.classify_displays(frames, opts)
  opts = opts or {}
  local dense_max = tonumber(opts.dense_max_width) or DENSE_MAX_WIDTH
  local screens = {}
  local wide_ids = {}
  local narrow_ids = {}
  local min_width = nil
  local max_width = nil
  local has_portrait = false

  for _, frame in ipairs(frames or {}) do
    if type(frame) == "table" then
      local width = tonumber(frame.width or frame.frameWidth or frame.visibleWidth)
      local height = tonumber(frame.height or frame.frameHeight or frame.visibleHeight)
      local id = tonumber(frame.id or frame["arrangement-id"] or frame.arrangement_id or frame.screen)
      if width and width > 0 then
        local portrait = false
        if height and height > 0 then
          portrait = height > width
        end
        if portrait then
          has_portrait = true
        end
        local entry = {
          id = id,
          width = width,
          height = height,
          portrait = portrait,
        }
        table.insert(screens, entry)
        if id then
          if width < dense_max or portrait then
            table.insert(narrow_ids, id)
          else
            table.insert(wide_ids, id)
          end
        end
        if min_width == nil or width < min_width then
          min_width = width
        end
        if max_width == nil or width > max_width then
          max_width = width
        end
      end
    end
  end

  -- split_layout: at least one wide and one narrow display.
  -- Wide desktops keep the full widget set; narrow/portrait ones get a compact strip.
  local split_layout = #wide_ids > 0 and #narrow_ids > 0
  local all_narrow = #wide_ids == 0 and #narrow_ids > 0

  local density = display_profile.density_for_width(min_width, opts)
  -- Homogeneous narrow setups still densify globally. Mixed setups never
  -- strip the wide desktop — only the narrow monitors adapt.
  local hide_anchor_labels = all_narrow and (density == "dense" or density == "compact")
  local clock_style = "full"
  if all_narrow and density == "dense" then
    clock_style = "time"
  elseif all_narrow and density == "compact" then
    clock_style = "compact"
  end

  local min_width_key = min_width and tostring(math.floor(min_width + 0.5)) or ""
  local fingerprint = string.format(
    "%s|min=%s|wide=%s|narrow=%s|split=%s",
    density,
    min_width_key,
    join_ids(wide_ids),
    join_ids(narrow_ids),
    split_layout and "1" or "0"
  )

  return {
    screens = screens,
    min_width = min_width,
    max_width = max_width,
    has_portrait = has_portrait,
    density = density,
    wide_displays = join_ids(wide_ids),
    narrow_displays = join_ids(narrow_ids),
    fingerprint = fingerprint,
    split_layout = split_layout,
    all_narrow = all_narrow,
    -- When split, heavy/optional widgets stay on wide desktops only.
    optional_wide_only = split_layout,
    -- Narrow monitors get compact clock/volume/battery clones.
    narrow_status_strip = split_layout,
    hide_anchor_labels = hide_anchor_labels,
    clock_style = clock_style,
  }
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

function display_profile.load_display_frames(reader)
  local read_output = reader or read_command_output
  local sketchybar_bin = os.getenv("BARISTA_SKETCHYBAR_BIN") or "sketchybar"
  local raw = read_output(string.format("%q --query displays 2>/dev/null", sketchybar_bin))
  if type(raw) ~= "string" or raw == "" then
    return {}
  end

  local ok, decoded = pcall(json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return {}
  end

  local frames = {}
  for _, entry in ipairs(decoded) do
    if type(entry) == "table" then
      local frame = entry.frame or {}
      table.insert(frames, {
        id = tonumber(entry["arrangement-id"] or entry.arrangement_id),
        width = tonumber(frame.w or frame.width),
        height = tonumber(frame.h or frame.height),
      })
    end
  end
  return frames
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
  var line = JSON.stringify({screen:i, topInset:top, bottomInset:bottom, frameWidth:f.size.width, frameHeight:f.size.height, visibleWidth:v.size.width, visibleHeight:v.size.height}) + "\n"
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
    density = "comfortable",
    min_width = nil,
    max_width = nil,
    has_portrait = false,
    wide_displays = "",
    narrow_displays = "",
    fingerprint = "comfortable|min=|wide=|narrow=|split=0",
    split_layout = false,
    all_narrow = false,
    optional_wide_only = false,
    narrow_status_strip = false,
    hide_anchor_labels = false,
    clock_style = "full",
    screens = {},
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

local function merge_layout(result, layout)
  if type(layout) ~= "table" then
    return result
  end
  result.screens = layout.screens or {}
  result.min_width = layout.min_width
  result.max_width = layout.max_width
  result.has_portrait = layout.has_portrait == true
  result.density = layout.density or "comfortable"
  result.wide_displays = layout.wide_displays or ""
  result.narrow_displays = layout.narrow_displays or ""
  result.fingerprint = layout.fingerprint or result.fingerprint
  result.split_layout = layout.split_layout == true
  result.all_narrow = layout.all_narrow == true
  result.optional_wide_only = layout.optional_wide_only == true
  result.narrow_status_strip = layout.narrow_status_strip == true
  result.hide_anchor_labels = layout.hide_anchor_labels == true
  result.clock_style = layout.clock_style or "full"
  return result
end

function display_profile.detect(reader)
  local frames = display_profile.load_display_frames(reader)
  local signature = frames_signature(frames)
  if reader == nil then
    local cached = load_cached_result(signature)
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

  if #frames == 0 then
    frames = {}
    -- row.screen is the 0-based NSScreen index, not SketchyBar's display
    -- number, so these frames drive density only and never a split layout.
    for _, row in ipairs(inset_rows) do
      table.insert(frames, {
        width = tonumber(row.frameWidth or row.visibleWidth),
        height = tonumber(row.frameHeight or row.visibleHeight),
      })
    end
  end

  merge_layout(result, display_profile.classify_displays(frames))

  if reader == nil then
    write_cached_result(result, signature)
  end

  return result
end

function display_profile.invalidate_cache()
  os.remove(cache_path())
end

return display_profile
