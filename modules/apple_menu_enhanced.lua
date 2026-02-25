local apple_menu = {}
local shortcuts_ok, shortcuts = pcall(require, "shortcuts")
if not shortcuts_ok then
  shortcuts = nil
end

local function expand_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 2) == "~/" then
    return (os.getenv("HOME") or "") .. path:sub(2)
  end
  return path
end

local function path_exists(path, want_dir)
  if not path or path == "" then
    return false
  end
  local flag = want_dir and "-d" or "-e"
  local handle = io.popen(string.format("test %s %q && printf 1 || printf 0", flag, path))
  if not handle then
    return false
  end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1") ~= nil
end

local function path_is_executable(path)
  if not path or path == "" then
    return false
  end
  local handle = io.popen(string.format("test -x %q && printf 1 || printf 0", path))
  if not handle then
    return false
  end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1") ~= nil
end

local function shell_quote(value)
  return string.format("%q", tostring(value))
end

local function command_path(command)
  if not command or command == "" then
    return nil
  end
  local handle = io.popen(string.format("command -v %q 2>/dev/null", command))
  if not handle then
    return nil
  end
  local result = handle:read("*a") or ""
  handle:close()
  result = result:gsub("%s+$", "")
  if result == "" then
    return nil
  end
  return result
end

local function env_prefix(vars)
  local keys = {}
  for key, value in pairs(vars or {}) do
    if type(value) == "string" and value ~= "" then
      table.insert(keys, key)
    end
  end
  if #keys == 0 then
    return ""
  end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    table.insert(parts, string.format("%s=%q", key, vars[key]))
  end
  return "env " .. table.concat(parts, " ") .. " "
end

local function open_terminal(command)
  if not command or command == "" then
    return ""
  end
  return string.format("osascript -e 'tell application \"Terminal\" to do script %q'", command)
end

local function menu_label(label, shortcut)
  if shortcut and shortcut ~= "" then
    return string.format("%-16s %s", label, shortcut)
  end
  return label
end

local function font_string(ctx, family, style, size)
  if ctx.font_string then
    return ctx.font_string(family, style, size)
  end
  return string.format("%s:%s:%0.1f", family, style, size)
end

local function resolve_code_dir(ctx)
  local home = os.getenv("HOME") or ""
  local candidate = (ctx.paths and ctx.paths.code_dir)
    or os.getenv("BARISTA_CODE_DIR")
    or (home .. "/src")
  candidate = expand_path(candidate)
  local fallback = home .. "/src"
  if candidate and candidate:match("/Code/?$") and path_exists(fallback, true) then
    return fallback
  end
  if candidate and not path_exists(candidate, true) then
    if path_exists(fallback, true) then
      return fallback
    end
    return candidate
  end
  if candidate and not path_exists(candidate .. "/lab", true) and path_exists(fallback .. "/lab", true) then
    return fallback
  end
  return candidate
end

local function resolve_config_dir(ctx)
  local home = os.getenv("HOME") or ""
  return (ctx.paths and ctx.paths.config_dir)
    or ctx.config_dir
    or os.getenv("BARISTA_CONFIG_DIR")
    or (home .. "/.config/sketchybar")
end

local function load_state(config_dir)
  local ok, json = pcall(require, "json")
  if not ok then
    return nil
  end
  local file = io.open(config_dir .. "/state.json", "r")
  if not file then
    return nil
  end
  local contents = file:read("*a")
  file:close()
  local ok_decode, data = pcall(json.decode, contents)
  if not ok_decode or type(data) ~= "table" then
    return nil
  end
  return data
end

local function resolve_menu_data_path(config_dir, raw_path)
  if type(raw_path) ~= "string" or raw_path == "" then
    return nil
  end
  local expanded = expand_path(raw_path)
  if expanded and expanded:match("^/") then
    return expanded
  end
  return string.format("%s/%s", config_dir, raw_path)
end

local function load_json_array_file(path)
  if not path then
    return nil
  end
  local ok_json, json = pcall(require, "json")
  if not ok_json then
    return nil
  end
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local contents = file:read("*a")
  file:close()
  local ok_decode, data = pcall(json.decode, contents)
  if not ok_decode or type(data) ~= "table" then
    return nil
  end
  return data
end

local function read_menu_config(config_dir)
  local state = load_state(config_dir)
  local menu_state = state and state.menus and state.menus.apple or {}
  local work_state = state and state.menus and state.menus.work or {}
  local items = type(menu_state.items) == "table" and menu_state.items or {}
  local custom = type(menu_state.custom) == "table" and menu_state.custom or {}
  local hover = type(menu_state.hover) == "table" and menu_state.hover or {}
  local sections = type(menu_state.sections) == "table" and menu_state.sections or {}
  local work_google_apps = type(work_state.google_apps) == "table" and work_state.google_apps or {}
  local work_apps_file = work_state.apps_file or menu_state.work_apps_file
  local resolved_work_apps_file = resolve_menu_data_path(config_dir, work_apps_file)
  local file_work_apps = load_json_array_file(resolved_work_apps_file)
  if type(file_work_apps) == "table" and #file_work_apps > 0 then
    work_google_apps = file_work_apps
  end
  return {
    show_missing = menu_state.show_missing,
    terminal = menu_state.terminal,
    launch = menu_state.launch,
    items = items,
    custom = custom,
    hover = hover,
    sections = sections,
    work_apps_file = work_apps_file,
    workspace_domain = work_state.workspace_domain,
    work_google_apps = work_google_apps,
  }
end

local function resolve_path(ctx, candidates, want_dir)
  local fallback = nil
  local max_index = 0
  for index in pairs(candidates or {}) do
    if type(index) == "number" and index > max_index then
      max_index = index
    end
  end
  for i = 1, max_index do
    local candidate = candidates[i]
    if candidate and candidate ~= "" then
      candidate = expand_path(candidate)
      fallback = fallback or candidate
      if path_exists(candidate, want_dir) then
        return candidate, true
      end
    end
  end
  return fallback, false
end

local function resolve_executable_path(candidates)
  local fallback = nil
  local max_index = 0
  for index in pairs(candidates or {}) do
    if type(index) == "number" and index > max_index then
      max_index = index
    end
  end
  for i = 1, max_index do
    local candidate = candidates[i]
    if candidate and candidate ~= "" then
      candidate = expand_path(candidate)
      fallback = fallback or candidate
      if path_is_executable(candidate) then
        return candidate, true
      end
    end
  end
  return fallback, false
end

local function resolve_afs_root(ctx)
  local code_dir = resolve_code_dir(ctx)
  return resolve_path(ctx, {
    ctx.paths and ctx.paths.afs or nil,
    os.getenv("AFS_ROOT"),
    code_dir .. "/lab/afs",
    code_dir .. "/afs",
  }, true)
end

local function resolve_afs_studio_root(ctx, afs_root)
  local code_dir = resolve_code_dir(ctx)
  return resolve_path(ctx, {
    ctx.paths and ctx.paths.afs_studio or nil,
    os.getenv("AFS_STUDIO_ROOT"),
    afs_root and (afs_root .. "/apps/studio") or nil,
    code_dir .. "/lab/afs_suite",
    code_dir .. "/lab/afs/apps/studio",
    code_dir .. "/lab/afs_studio",
    code_dir .. "/afs/apps/studio",
    code_dir .. "/afs_studio",
  }, true)
end

local function resolve_afs_browser_app(ctx)
  local code_dir = resolve_code_dir(ctx)
  return resolve_path(ctx, {
    ctx.paths and ctx.paths.afs_browser_app or nil,
    os.getenv("AFS_BROWSER_APP"),
    code_dir .. "/lab/afs_suite/build_ai/apps/browser/afs-browser.app",
    code_dir .. "/lab/afs_suite/build/apps/browser/afs-browser.app",
    code_dir .. "/lab/afs_suite/build/apps/browser/Debug/afs-browser.app",
    code_dir .. "/lab/afs_suite/build/apps/browser/Release/afs-browser.app",
  }, true)
end

local function resolve_stemforge_app(ctx)
  local code_dir = resolve_code_dir(ctx)
  return resolve_path(ctx, {
    ctx.paths and ctx.paths.stemforge_app or nil,
    os.getenv("STEMFORGE_APP"),
    code_dir .. "/tools/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app",
    code_dir .. "/tools/stemforge/build_ai/StemForge_artefacts/Release/Standalone/StemForge.app",
    code_dir .. "/tools/stemforge/build/StemForge_artefacts/Debug/Standalone/StemForge.app",
    code_dir .. "/lab/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app",
    code_dir .. "/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app",
    os.getenv("HOME") .. "/Applications/StemForge.app",
    "/Applications/StemForge.app",
  }, true)
end

local function resolve_stem_sampler_app(ctx)
  local code_dir = resolve_code_dir(ctx)
  return resolve_path(ctx, {
    ctx.paths and ctx.paths.stem_sampler_app or nil,
    os.getenv("STEM_SAMPLER_APP"),
    code_dir .. "/tools/stem-sampler/StemSampler.app",
    code_dir .. "/tools/stemsampler/StemSampler.app",
    code_dir .. "/tools/stem_sampler/StemSampler.app",
    os.getenv("HOME") .. "/Applications/StemSampler.app",
    "/Applications/StemSampler.app",
  }, true)
end

local function resolve_yaze_app(ctx)
  local code_dir = resolve_code_dir(ctx)
  local yaze_dir = os.getenv("BARISTA_YAZE_DIR")
    or (ctx.paths and ctx.paths.yaze)
    or (code_dir .. "/yaze")
  local nightly_prefix = os.getenv("BARISTA_YAZE_NIGHTLY_PREFIX")
    or os.getenv("YAZE_NIGHTLY_PREFIX")
    or ((os.getenv("HOME") or "") .. "/.local/yaze/nightly")
  return resolve_path(ctx, {
    ctx.paths and ctx.paths.yaze_app or nil,
    os.getenv("BARISTA_YAZE_APP") or os.getenv("YAZE_APP"),
    nightly_prefix .. "/current/yaze.app",
    nightly_prefix .. "/yaze.app",
    (os.getenv("HOME") or "") .. "/Applications/Yaze Nightly.app",
    (os.getenv("HOME") or "") .. "/Applications/yaze nightly.app",
    (os.getenv("HOME") or "") .. "/applications/Yaze Nightly.app",
    (os.getenv("HOME") or "") .. "/applications/yaze nightly.app",
    "/Applications/Yaze Nightly.app",
    "/Applications/yaze nightly.app",
    -- AI builds (Stable/Preferred) - Debug/Release variants for Multi-Config
    yaze_dir and (yaze_dir .. "/build_ai/bin/Debug/yaze.app") or nil,
    yaze_dir and (yaze_dir .. "/build_ai/bin/Release/yaze.app") or nil,
    code_dir .. "/hobby/yaze/build_ai/bin/Debug/yaze.app",
    code_dir .. "/hobby/yaze/build_ai/bin/Release/yaze.app",
    code_dir .. "/yaze/build_ai/bin/Debug/yaze.app",
    code_dir .. "/yaze/build_ai/bin/Release/yaze.app",

    -- Fallbacks
    yaze_dir and (yaze_dir .. "/build_ai/bin/yaze.app") or nil,
    code_dir .. "/hobby/yaze/build_ai/bin/yaze.app",
    code_dir .. "/yaze/build_ai/bin/yaze.app",
    
    -- Legacy/Standard builds
    yaze_dir and (yaze_dir .. "/build/bin/Release/yaze.app") or nil,
    yaze_dir and (yaze_dir .. "/build/bin/yaze.app") or nil,
    code_dir .. "/hobby/yaze/build/bin/Release/yaze.app",
    code_dir .. "/hobby/yaze/build/bin/yaze.app",
    code_dir .. "/yaze/build/bin/yaze.app",
  }, true)
end

local function resolve_yaze_launcher()
  local override = os.getenv("BARISTA_YAZE_LAUNCHER") or os.getenv("YAZE_LAUNCHER")
  if override and override ~= "" then
    override = expand_path(override)
    if path_is_executable(override) then
      return override, true
    end
    local resolved = command_path(override)
    if resolved then
      return resolved, true
    end
  end

  local resolved = command_path("yaze-nightly")
  if resolved then
    return resolved, true
  end

  return nil, false
end
local function resolve_sys_manual_binary(ctx)
  local code_dir = resolve_code_dir(ctx)
  return resolve_executable_path({
    code_dir .. "/lab/sys_manual/build/sys_manual",
    code_dir .. "/sys_manual/build/sys_manual",
    "/Applications/sys_manual.app/Contents/MacOS/sys_manual",
  })
end

local function resolve_mesen_run(ctx)
  return resolve_executable_path({
    (os.getenv("HOME") or "") .. "/bin/mesen-run",
    (os.getenv("HOME") or "") .. "/.local/bin/mesen-run",
  })
end

local function resolve_oracle_agent_manager(ctx)
  local code_dir = resolve_code_dir(ctx)
  return resolve_executable_path({
    code_dir .. "/hobby/oracle-agent-manager/mesen2ctl",
    code_dir .. "/hobby/oracle-agent-manager/build/mesen2ctl",
  })
end

local function resolve_cortex_cli(ctx)
  local override = os.getenv("CORTEX_CLI") or os.getenv("CORTEX_CLI_PATH")
  if override and override ~= "" then
    override = expand_path(override)
    if path_is_executable(override) then
      return override, true
    end
  end

  local resolved = command_path("cortex-cli")
  if resolved then
    return resolved, true
  end

  local code_dir = resolve_code_dir(ctx)
  return resolve_executable_path({
    code_dir .. "/lab/cortex/bin/cortex-cli",
    code_dir .. "/cortex/bin/cortex-cli",
    (os.getenv("HOME") or "") .. "/.local/bin/cortex-cli",
  })
end

local function afs_cli(afs_root, args)
  local pythonpath = afs_root .. "/src"
  return string.format(
    "cd %s && AFS_ROOT=%s PYTHONPATH=%s python3 -m afs %s",
    shell_quote(afs_root),
    shell_quote(afs_root),
    shell_quote(pythonpath),
    args or ""
  )
end

local function resolve_menu_action(ctx, config_dir)
  local candidates = {
    ctx.menu_action,
    config_dir and (config_dir .. "/bin/menu_action") or nil,
    config_dir and (config_dir .. "/helpers/menu_action") or nil,
    config_dir and (config_dir .. "/plugins/menu_action.sh") or nil,
  }
  for _, candidate in ipairs(candidates) do
    if candidate and candidate ~= "" and path_is_executable(candidate) then
      return candidate
    end
  end
  for _, candidate in ipairs(candidates) do
    if candidate and candidate ~= "" and path_exists(candidate, false) then
      return string.format("bash %s", shell_quote(candidate))
    end
  end
  return nil
end

local function wrap_action(ctx, popup_name, entry_name, action)
  if not action or action == "" then
    return ""
  end
  local config_dir = resolve_config_dir(ctx)
  local menu_action = resolve_menu_action(ctx, config_dir)
  if menu_action and menu_action ~= "" then
    return string.format(
      "MENU_ACTION_CMD=%q %s %q %q",
      action,
      menu_action,
      entry_name or "",
      popup_name or ""
    )
  end
  return string.format("%s; sketchybar -m --set %s popup.drawing=off", action, popup_name or "")
end

function apple_menu.setup(ctx)
  local sbar = ctx.sbar
  local theme = ctx.theme
  local settings = ctx.settings
  local widget_height = ctx.widget_height
  local associated_displays = ctx.associated_displays or "all"
  local config_dir = resolve_config_dir(ctx)
  local menu_config = read_menu_config(config_dir)

  local function resolved_style(style_name, fallback)
    local raw = tostring(style_name or fallback or "Regular")
    local normalized = raw:sub(1, 1):upper() .. raw:sub(2):lower()
    if settings.font.style_map[normalized] then
      return settings.font.style_map[normalized]
    end
    if settings.font.style_map[fallback] then
      return settings.font.style_map[fallback]
    end
    return settings.font.style_map["Regular"] or "Regular"
  end

  local menu_font_size_offset = tonumber((ctx.appearance and ctx.appearance.menu_font_size_offset) or 1) or 1
  local menu_font_size = math.max((settings.font.sizes.small or 12) + menu_font_size_offset, 10)
  local menu_font_style = resolved_style((ctx.appearance and ctx.appearance.menu_font_style) or "Bold", "Semibold")
  local menu_header_style = resolved_style((ctx.appearance and ctx.appearance.menu_header_font_style) or "Bold", "Bold")
  local font_small = font_string(ctx, settings.font.text, menu_font_style, menu_font_size)
  local font_bold = font_string(ctx, settings.font.text, menu_header_style, menu_font_size)

  local popup_border_width = (ctx.appearance and ctx.appearance.popup_border_width) or 2
  local popup_corner_radius = (ctx.appearance and ctx.appearance.popup_corner_radius) or 8
  local popup_border_color = (ctx.appearance and ctx.appearance.popup_border_color) or theme.WHITE
  local popup_bg_color = (ctx.appearance and (ctx.appearance.menu_popup_bg_color or ctx.appearance.popup_bg_color)) or theme.BG_PRI_COLR or theme.bar.bg
  local popup_padding = (ctx.appearance and ctx.appearance.popup_padding) or 8
  local popup_item_height = tonumber((ctx.appearance and ctx.appearance.popup_item_height) or 0) or 0
  if popup_item_height <= 0 then
    popup_item_height = math.max(widget_height - 6, 20)
  end
  local popup_item_corner_radius = tonumber((ctx.appearance and ctx.appearance.popup_item_corner_radius) or 6) or 6
  local function popup_toggle(item_name)
    if type(ctx.popup_toggle_action) == "function" then
      return ctx.popup_toggle_action(item_name)
    end
    if item_name and item_name ~= "" then
      return string.format("sketchybar -m --set %s popup.drawing=toggle", item_name)
    end
    return "sketchybar -m --set $NAME popup.drawing=toggle"
  end

  sbar.add("item", "apple_menu", {
    position = "left",
    icon = ctx.icon_for and ctx.icon_for("apple", "") or "",
    label = { drawing = false },
    associated_display = associated_displays,
    associated_space = "all",
    background = {
      color = "0x00000000",
      corner_radius = 4,
      height = widget_height,
      padding_left = 4,
      padding_right = 4,
    },
    click_script = popup_toggle(),
    popup = {
      background = {
        border_width = popup_border_width,
        corner_radius = popup_corner_radius,
        border_color = popup_border_color,
        color = popup_bg_color,
        padding_left = popup_padding,
        padding_right = popup_padding,
      },
    },
  })

  local subscribe_popup = ctx.subscribe_popup_autoclose or ctx.subscribe_mouse_exit
  if subscribe_popup then
    subscribe_popup("apple_menu")
  end

  local item_height = popup_item_height

  local hover_script = ctx.HOVER_SCRIPT
  if not hover_script and config_dir then
    local compiled_hover = config_dir .. "/bin/popup_hover"
    if path_exists(compiled_hover, false) then
      hover_script = compiled_hover
    else
      hover_script = config_dir .. "/plugins/popup_hover.sh"
    end
  end
  local hover_env = {}
  local hover_color = (menu_config.hover and menu_config.hover.color)
    or (ctx.appearance and ctx.appearance.hover_bg)
    or "0x60cdd6f4"
  local hover_border_color = (menu_config.hover and menu_config.hover.border_color)
    or (ctx.appearance and ctx.appearance.hover_border_color)
  local hover_border_width = (menu_config.hover and menu_config.hover.border_width)
    or (ctx.appearance and ctx.appearance.hover_border_width)
  local hover_curve = (ctx.appearance and ctx.appearance.hover_animation_curve)
  local hover_duration = (ctx.appearance and ctx.appearance.hover_animation_duration)
  if hover_color then
    hover_env.POPUP_HOVER_COLOR = tostring(hover_color)
  end
  if hover_border_color then
    hover_env.POPUP_HOVER_BORDER_COLOR = tostring(hover_border_color)
  end
  if hover_border_width then
    hover_env.POPUP_HOVER_BORDER_WIDTH = tostring(hover_border_width)
  end
  if hover_curve then
    hover_env.POPUP_HOVER_ANIMATION_CURVE = tostring(hover_curve)
  end
  if hover_duration then
    hover_env.POPUP_HOVER_ANIMATION_DURATION = tostring(hover_duration)
  end
  local hover_script_cmd = hover_script
  if hover_script and next(hover_env) then
    hover_script_cmd = env_prefix(hover_env) .. hover_script
  end

  local code_dir = resolve_code_dir(ctx)
  local show_missing = os.getenv("BARISTA_SHOW_MISSING_TOOLS") == "1"
  if type(menu_config.show_missing) == "boolean" then
    show_missing = menu_config.show_missing
  end

  local function normalize_bool(value)
    if type(value) == "boolean" then
      return value
    end
    if type(value) == "number" then
      return value ~= 0
    end
    if type(value) == "string" then
      local lowered = value:lower()
      if lowered == "true" or lowered == "yes" or lowered == "1" then
        return true
      end
      if lowered == "false" or lowered == "no" or lowered == "0" then
        return false
      end
    end
    return nil
  end

  local function normalize_order(value)
    if type(value) == "number" then
      return value
    end
    if type(value) == "string" then
      return tonumber(value)
    end
    return nil
  end

  local terminal_defaults = {}

  local function terminal_allowed(item_id)
    local override = menu_config.items[item_id] or {}
    if type(override.launch) == "string" then
      return override.launch:lower() == "terminal"
    end
    local override_terminal = normalize_bool(override.terminal or override.open_terminal)
    if override_terminal ~= nil then
      return override_terminal
    end
    local enabled_override = normalize_bool(override.enabled)
    if enabled_override == true then
      return true
    end
    if type(menu_config.launch) == "string" then
      return menu_config.launch:lower() == "terminal"
    end
    local menu_terminal = normalize_bool(menu_config.terminal or menu_config.open_terminal)
    if menu_terminal ~= nil then
      return menu_terminal
    end
    local env = os.getenv("BARISTA_MENU_TERMINAL")
    if env and env ~= "" then
      env = env:lower()
      return env == "1" or env == "true" or env == "yes"
    end
    return terminal_defaults[item_id] == true
  end

  local function terminal_action(item_id, command)
    if not command or command == "" then
      return nil
    end
    if not terminal_allowed(item_id) then
      return nil
    end
    return open_terminal(command)
  end

  local function add_separator(index)
    sbar.add("item", string.format("menu.tools.sep.%d", index), {
      position = "popup.apple_menu",
      icon = { drawing = false },
      label = { string = "───────────────", font = font_small, color = theme.DARK_WHITE },
      ["label.padding_left"] = 8,
      ["label.padding_right"] = 8,
      background = { drawing = false },
    })
  end

  local function add_header(meta, index)
    local label = meta.label or ""
    sbar.add("item", string.format("menu.tools.header.%s.%d", meta.id or "section", index), {
      position = "popup.apple_menu",
      icon = { drawing = false },
      label = { string = label, font = font_bold, color = meta.color or theme.WHITE },
      ["label.padding_left"] = 10,
      ["label.padding_right"] = 10,
      background = {
        drawing = true,
        color = meta.bg_color or theme.BG_SEC_COLR or theme.bar.bg,
        corner_radius = popup_item_corner_radius,
        height = item_height,
      },
    })
  end

  local function add_item(entry)
    local muted = entry.missing or entry.blocked
    local shortcut = entry.shortcut
    if (not shortcut or shortcut == "") and entry.shortcut_action and shortcuts and shortcuts.get_symbol then
      shortcut = shortcuts.get_symbol(entry.shortcut_action)
    end
    local label = menu_label(entry.label, shortcut)
    local icon_color = entry.icon_color or (muted and theme.DARK_WHITE or theme.WHITE)
    local label_color = entry.label_color
      or (ctx.appearance and ctx.appearance.menu_label_color)
      or theme.WHITE
    local action = entry.action
    if entry.missing then
      local launcher = config_dir .. "/bin/open_control_panel.sh"
      local fallback = ctx.call_script and ctx.call_script(launcher, "--panel") or ""
      action = fallback
    elseif entry.blocked then
      local launcher = config_dir .. "/bin/open_control_panel.sh"
      local fallback = ctx.call_script and ctx.call_script(launcher, "--panel") or ""
      action = fallback
    end
    sbar.add("item", entry.name, {
      position = "popup.apple_menu",
      icon = { string = entry.icon or "", color = icon_color },
      label = { string = label, font = font_small, color = label_color },
      click_script = wrap_action(ctx, "apple_menu", entry.name, action),
      script = hover_script_cmd,
      ["icon.padding_left"] = 10,
      ["icon.padding_right"] = 6,
      ["label.padding_left"] = 4,
      ["label.padding_right"] = 8,
      background = {
        drawing = false,
        corner_radius = popup_item_corner_radius,
        height = item_height,
      },
    })
    if ctx.attach_hover then
      ctx.attach_hover(entry.name)
    end
  end

  local afs_root, afs_ok = resolve_afs_root(ctx)
  local studio_root, studio_ok = resolve_afs_studio_root(ctx, afs_root)
  local afs_browser_app, afs_browser_ok = resolve_afs_browser_app(ctx)
  local stemforge_app, stemforge_ok = resolve_stemforge_app(ctx)
  local stem_sampler_app, stem_sampler_ok = resolve_stem_sampler_app(ctx)
  local yaze_app, yaze_ok = resolve_yaze_app(ctx)
  local yaze_launcher, yaze_launcher_ok = resolve_yaze_launcher()
  local yaze_available = yaze_ok or yaze_launcher_ok
  local yaze_enabled = (ctx.integrations and ctx.integrations.yaze ~= nil)
  if ctx.integration_flags and ctx.integration_flags.yaze == false then
    yaze_enabled = false
  end
  local cortex_cli, cortex_cli_ok = resolve_cortex_cli(ctx)
  local help_center_bin, help_center_ok = resolve_executable_path({
    ctx.helpers and ctx.helpers.help_center or nil,
    config_dir .. "/gui/bin/help_center",
    config_dir .. "/build/bin/help_center",
  })
  local help_center_doc, help_center_doc_ok = resolve_path(ctx, {
    config_dir .. "/docs/features/ICONS_AND_SHORTCUTS.md",
    config_dir .. "/docs/guides/QUICK_START.md",
  }, false)
  local help_center_action = ""
  local help_center_available = false
  local code_dir = resolve_code_dir(ctx)
  local env_prefix = string.format(
    "BARISTA_CONFIG_DIR=%s BARISTA_CODE_DIR=%s",
    shell_quote(config_dir),
    shell_quote(code_dir)
  )
  if help_center_ok and help_center_bin then
    help_center_action = string.format("%s %s", env_prefix, shell_quote(help_center_bin))
    help_center_available = true
  elseif help_center_doc then
    help_center_action = string.format("open %s", shell_quote(help_center_doc))
    help_center_available = help_center_doc_ok
  end

  local icon_browser_bin, icon_browser_ok = resolve_executable_path({
    config_dir .. "/gui/bin/icon_browser",
    config_dir .. "/build/bin/icon_browser",
  })
  local icon_browser_doc, icon_browser_doc_ok = resolve_path(ctx, {
    config_dir .. "/docs/features/ICON_REFERENCE.md",
  }, false)
  local icon_browser_action = ""
  local icon_browser_available = false
  if icon_browser_ok and icon_browser_bin then
    icon_browser_action = string.format("%s %s", env_prefix, shell_quote(icon_browser_bin))
    icon_browser_available = true
  elseif icon_browser_doc then
    icon_browser_action = string.format("open %s", shell_quote(icon_browser_doc))
    icon_browser_available = icon_browser_doc_ok
  end

  local keyboard_overlay_bin, keyboard_overlay_ok = resolve_executable_path({
    config_dir .. "/scripts/open_keyboard_overlay.sh",
  })
  local keyboard_overlay_action = ""
  local keyboard_overlay_available = false
  if keyboard_overlay_ok and keyboard_overlay_bin then
    keyboard_overlay_action = shell_quote(keyboard_overlay_bin)
    keyboard_overlay_available = true
  end

  local sys_manual_bin, sys_manual_ok = resolve_sys_manual_binary(ctx)
  local sys_manual_action = ""
  local sys_manual_available = false
  if sys_manual_ok and sys_manual_bin then
    sys_manual_action = shell_quote(sys_manual_bin)
    sys_manual_available = true
  end

  local mesen_run_bin, mesen_run_ok = resolve_mesen_run(ctx)
  local mesen_run_action = ""
  if mesen_run_ok and mesen_run_bin then
    mesen_run_action = shell_quote(mesen_run_bin)
  end

  local oam_bin, oam_ok = resolve_oracle_agent_manager(ctx)
  local oam_action = ""
  if oam_ok and oam_bin then
    oam_action = terminal_action("oracle.agent_manager", shell_quote(oam_bin))
  end

  local afs_action = afs_browser_app and string.format("open %s", shell_quote(afs_browser_app)) or ""
  local studio_bin, studio_bin_ok = resolve_path(ctx, {
    studio_root and (studio_root .. "/build_ai/apps/studio/afs-studio.app") or nil,
    studio_root and (studio_root .. "/build_ai/apps/studio/afs-studio") or nil,
    studio_root and (studio_root .. "/build/apps/studio/afs-studio.app") or nil,
    studio_root and (studio_root .. "/build/apps/studio/afs-studio") or nil,
  }, false)
  local studio_action
  local studio_cmd
  if studio_bin_ok and studio_bin then
    if studio_bin:match("%.app/?$") then
      studio_action = string.format("open %s", shell_quote(studio_bin))
    else
      studio_action = shell_quote(studio_bin)
    end
  else
    if afs_root then
      studio_cmd = afs_cli(afs_root, "studio run --build")
    elseif studio_root then
      studio_cmd = string.format(
        "cd %s && cmake --build build_ai --target afs-studio && ./build_ai/apps/studio/afs-studio",
        shell_quote(studio_root)
      )
    end
    studio_action = terminal_action("afs_studio", studio_cmd)
  end
  local studio_available = studio_ok and (studio_bin_ok or studio_cmd ~= nil)
  local studio_blocked = studio_ok and studio_cmd ~= nil and studio_action == nil

  local labeler_bin, labeler_bin_ok = resolve_path(ctx, {
    studio_root and (studio_root .. "/build_ai/apps/studio/afs-labeler.app") or nil,
    studio_root and (studio_root .. "/build_ai/apps/studio/afs-labeler") or nil,
    studio_root and (studio_root .. "/build/apps/studio/afs-labeler.app") or nil,
    studio_root and (studio_root .. "/build/apps/studio/afs-labeler") or nil,
  }, false)
  local labeler_csv = os.getenv("AFS_LABELER_CSV")
  local labeler_cmd
  local labeler_action
  if labeler_bin_ok and labeler_bin then
    labeler_cmd = shell_quote(labeler_bin)
    if labeler_csv and labeler_csv ~= "" then
      labeler_cmd = labeler_cmd .. " --csv " .. shell_quote(labeler_csv)
    end
    labeler_action = labeler_cmd
  elseif studio_root then
    labeler_cmd = string.format("cd %s && cmake --build build_ai --target afs-labeler && ./build_ai/apps/studio/afs-labeler", shell_quote(studio_root))
    if labeler_csv and labeler_csv ~= "" then
      labeler_cmd = labeler_cmd .. " --csv " .. shell_quote(labeler_csv)
    end
    labeler_action = terminal_action("afs_labeler", labeler_cmd)
  end

  local cortex_toggle = cortex_cli_ok and (shell_quote(cortex_cli) .. " toggle") or ""
  local cortex_hub = cortex_cli_ok and (shell_quote(cortex_cli) .. " hub") or ""
  local function tc(k, d) return theme[k] or theme[d or "WHITE"] or theme.WHITE end

  local base_items = {
    {
      id = "afs_browser",
      label = "AFS Browser",
      icon = "󰈙",
      icon_color = tc("SAPPHIRE"),
      section = "core",
      action = afs_action or "",
      shortcut_action = "launch_afs_browser",
      available = afs_browser_ok,
      default_enabled = true,
    },
    {
      id = "afs_studio",
      label = "AFS Studio",
      icon = "󰆍",
      icon_color = tc("LAVENDER"),
      section = "afs",
      action = studio_action or "",
      shortcut_action = "launch_afs_studio",
      available = studio_available,
      blocked = studio_blocked,
      default_enabled = false,
    },
    {
      id = "afs_labeler",
      label = "AFS Labeler",
      icon = "󰓹",
      icon_color = tc("TEAL"),
      section = "afs",
      action = labeler_action or "",
      shortcut_action = "launch_afs_labeler",
      available = studio_ok and labeler_cmd ~= nil,
      blocked = studio_ok and labeler_cmd ~= nil and labeler_action == nil,
      default_enabled = false,
    },
    {
      id = "stemforge",
      label = "StemForge",
      icon = "󰎈",
      icon_color = tc("PINK"),
      section = "audio",
      action = stemforge_app and string.format("open %s", shell_quote(stemforge_app)) or "",
      shortcut_action = "launch_stemforge",
      available = stemforge_ok,
      default_enabled = false,
    },
    {
      id = "stem_sampler",
      label = "StemSampler",
      icon = "󰎈",
      icon_color = tc("PEACH"),
      section = "audio",
      action = stem_sampler_app and string.format("open %s", shell_quote(stem_sampler_app)) or "",
      shortcut_action = "launch_stem_sampler",
      available = stem_sampler_ok,
      default_enabled = false,
    },
    {
      id = "yaze",
      label = "Yaze",
      icon = "󰯙",
      icon_color = tc("YELLOW"),
      section = "core",
      action = yaze_launcher_ok and shell_quote(yaze_launcher) or (yaze_app and string.format("open %s", shell_quote(yaze_app)) or ""),
      -- Default to enabled if we found it
      available = yaze_available,
      default_enabled = true,
      submenu = yaze_enabled and {
        {
          name = "yaze.repo",
          label = "Open Repo",
          icon = "󰋜",
          action = ctx.open_path(yaze_dir),
        },
        {
          name = "yaze.docs",
          label = "Workflow Docs",
          icon = "󰊕",
          action = ctx.open_path(ctx.paths and ctx.paths.rom_doc or (code_dir .. "/docs/workflow/rom-hacking.org")),
        }
      } or nil
    },
    {
      id = "mesen_oos",
      label = "Mesen2 OoS",
      icon = "󰁆",
      icon_color = tc("RED"),
      section = "core",
      action = mesen_run_action,
      available = mesen_run_ok,
      default_enabled = true,
    },
    {
      id = "oracle_agent_manager",
      label = "Agent Manager",
      icon = "󰒋",
      icon_color = tc("MAGENTA", "MAUVE"),
      section = "core",
      action = oam_action,
      available = oam_ok,
      default_enabled = true,
    },
    {
      id = "cortex_toggle",
      label = "Cortex Dashboard",
      icon = "󰕮",
      icon_color = tc("MAUVE", "LAVENDER"),
      section = "controls",
      action = cortex_toggle,
      shortcut_action = "toggle_cortex",
      available = cortex_cli_ok,
      default_enabled = true,
    },
    {
      id = "cortex_hub",
      label = "Cortex Hub",
      icon = "󰣖",
      icon_color = tc("SKY"),
      section = "controls",
      action = cortex_hub,
      available = cortex_cli_ok,
      default_enabled = false,
    },
    {
      id = "help_center",
      label = "Help Center",
      icon = "󰘥",
      icon_color = tc("BLUE"),
      section = "support",
      action = help_center_action,
      shortcut_action = "open_help_center",
      available = help_center_available,
      default_enabled = true,
    },
    {
      id = "sys_manual",
      label = "Sys Manual",
      icon = "󰋜",
      icon_color = tc("BLUE"),
      section = "support",
      action = sys_manual_action,
      shortcut_action = "open_sys_manual",
      available = sys_manual_available,
      default_enabled = false,
    },
    {
      id = "icon_browser",
      label = "Icon Browser",
      icon = "󰈙",
      icon_color = tc("SKY"),
      section = "support",
      action = icon_browser_action,
      shortcut_action = "open_icon_browser",
      available = icon_browser_available,
      default_enabled = false,
    },
    {
      id = "keyboard_overlay",
      label = "Keyboard Overlay",
      icon = "󰌌",
      icon_color = tc("SKY"),
      section = "support",
      action = keyboard_overlay_action,
      shortcut_action = "toggle_keyboard_overlay",
      available = keyboard_overlay_available,
      default_enabled = false,
    },
    {
      id = "barista_config",
      label = "Barista Config",
      icon = "󰒓",
      icon_color = tc("SKY"),
      section = "controls",
      action = ctx.call_script(config_dir .. "/bin/open_control_panel.sh", "--panel"),
      shortcut_action = "open_control_panel",
      available = true,
      default_enabled = true,
    },
    {
      id = "reload_bar",
      label = "Reload SketchyBar",
      icon = "󰑐",
      icon_color = tc("YELLOW"),
      section = "controls",
      action = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload",
      shortcut_action = "reload_sketchybar",
      available = true,
      default_enabled = true,
    },
  }

  local sections = {
    core = { id = "core", label = "Core Tools", icon = "󰯙", color = tc("GREEN"), order = 1 },
    controls = { id = "controls", label = "Controls", icon = "󰒓", color = tc("SKY"), order = 2 },
    work = { id = "work", label = "Work Apps", icon = "󰖟", color = tc("BLUE"), order = 3 },
    support = { id = "support", label = "Support", icon = "󰘥", color = tc("LAVENDER"), order = 4 },
    afs = { id = "afs", label = "AFS Tools", icon = "󰈙", color = tc("SAPPHIRE"), order = 5 },
    audio = { id = "audio", label = "Audio", icon = "󰎈", color = tc("PEACH"), order = 6 },
    custom = { id = "custom", label = "Custom", icon = "󰘥", color = tc("LAVENDER"), order = 7 },
  }

  for section_id, override in pairs(menu_config.sections or {}) do
    if type(override) == "table" then
      local section = sections[section_id] or { id = section_id, label = section_id, order = 99 }
      if override.label and override.label ~= "" then
        section.label = override.label
      end
      if override.icon and override.icon ~= "" then
        section.icon = override.icon
      end
      if override.color and override.color ~= "" then
        section.color = override.color
      end
      local order = normalize_order(override.order)
      if order ~= nil then
        section.order = order
      end
      sections[section_id] = section
    end
  end

  local rendered = {}
  for index, item in ipairs(base_items) do
    local override = menu_config.items[item.id] or {}
    local enabled_override = normalize_bool(override.enabled)
    local should_show = false
    local missing = false

    if enabled_override == false then
      should_show = false
    elseif item.blocked then
      should_show = true
    elseif enabled_override == true then
      should_show = true
      missing = not item.available
    else
      if item.default_enabled == false then
        should_show = false
      elseif item.available then
        should_show = true
      elseif show_missing then
        should_show = true
        missing = true
      end
    end

    if should_show then
      local order = normalize_order(override.order) or item.order or (1000 + index)
      table.insert(rendered, {
        id = item.id,
        name = "menu.tools." .. item.id,
        label = override.label or item.label,
        icon = override.icon or item.icon,
        icon_color = override.icon_color or override.color or item.icon_color,
        label_color = override.label_color or item.label_color,
        action = item.action,
        shortcut = override.shortcut or item.shortcut,
        shortcut_action = override.shortcut_action or item.shortcut_action,
        missing = missing,
        order = order,
        default_index = index,
        section = override.section or item.section or "controls",
      })
    end
  end

  for index, custom in ipairs(menu_config.custom or {}) do
    if type(custom) == "table" then
      local enabled_override = normalize_bool(custom.enabled)
      if enabled_override ~= false then
        local label = custom.label or custom.title or ("Custom " .. index)
        local action = custom.command or custom.action or ""
        if label ~= "" and action ~= "" then
          table.insert(rendered, {
            id = "custom_" .. index,
            name = "menu.tools.custom." .. index,
            label = label,
            icon = custom.icon or "",
            icon_color = custom.icon_color or custom.color,
            label_color = custom.label_color,
            action = action,
            shortcut = custom.shortcut,
            missing = false,
            order = normalize_order(custom.order) or (2000 + index),
            default_index = 1000 + index,
            section = custom.section or "custom",
          })
        end
      end
    end
  end

  for index, app in ipairs(menu_config.work_google_apps or {}) do
    if type(app) == "table" then
      local enabled = normalize_bool(app.enabled)
      if enabled ~= false then
        local label = app.label or app.title or app.name or ("Work App " .. index)
        local action = app.command or app.action or ""
        local url = app.url
        if (not action or action == "") and type(url) == "string" and url ~= "" then
          action = string.format("open %s", shell_quote(url))
        end
        if label ~= "" and action ~= "" then
          table.insert(rendered, {
            id = app.id or ("work_google_" .. index),
            name = "menu.tools.work." .. index,
            label = label,
            icon = app.icon or "󰊯",
            icon_color = app.icon_color or app.color or theme.BLUE,
            label_color = app.label_color,
            action = action,
            shortcut = app.shortcut,
            missing = false,
            order = normalize_order(app.order) or (1500 + index),
            default_index = 1200 + index,
            section = app.section or "work",
          })
        end
      end
    end
  end

  table.sort(rendered, function(a, b)
    local section_a = sections[a.section] and sections[a.section].order or 99
    local section_b = sections[b.section] and sections[b.section].order or 99
    if section_a ~= section_b then
      return section_a < section_b
    end
    if a.order == b.order then
      return a.default_index < b.default_index
    end
    return a.order < b.order
  end)

  local current_section = nil
  local section_index = 1
  for _, entry in ipairs(rendered) do
    if entry.section ~= current_section then
      if current_section ~= nil then
        add_separator(section_index)
        section_index = section_index + 1
      end
      add_header(sections[entry.section] or { id = entry.section, label = entry.section }, section_index)
      section_index = section_index + 1
      current_section = entry.section
    end
    add_item(entry)
  end
end

return apple_menu
