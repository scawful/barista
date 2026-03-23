local apple_menu = {}
local binary_resolver = require("binary_resolver")
local menu_style = require("menu_style")
local locator = require("tool_locator")
local project_shortcuts_module = require("project_shortcuts")
local shortcuts_ok, shortcuts = pcall(require, "shortcuts")
if not shortcuts_ok then
  shortcuts = nil
end

local function expand_path(path)
  return locator.expand_path(path)
end

local function path_exists(path, want_dir)
  return locator.path_exists(path, want_dir)
end

local function path_is_executable(path)
  return locator.path_is_executable(path)
end

local function shell_quote(value)
  return string.format("%q", tostring(value))
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
  return locator.resolve_code_dir(ctx)
end

local function resolve_config_dir(ctx)
  return locator.resolve_config_dir(ctx)
end

local function load_state(config_dir)
  return locator.load_state(config_dir)
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

local function read_menu_config(config_dir, state_override)
  local state = type(state_override) == "table" and state_override or load_state(config_dir)
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
  return locator.resolve_path(candidates, want_dir)
end

local function resolve_executable_path(candidates)
  return locator.resolve_executable_path(candidates)
end

local function resolve_afs_root(ctx)
  return locator.resolve_afs_root(ctx)
end

local function resolve_afs_studio_root(ctx, afs_root)
  return locator.resolve_afs_studio_root(ctx, afs_root)
end

local function resolve_afs_browser_app(ctx)
  return locator.resolve_afs_browser_app(ctx)
end

local function resolve_stemforge_app(ctx)
  return locator.resolve_stemforge_app(ctx)
end

local function resolve_stem_sampler_app(ctx)
  return locator.resolve_stem_sampler_app(ctx)
end

local function resolve_yaze_app(ctx)
  return locator.resolve_yaze_app(ctx)
end

local function resolve_yaze_launcher()
  return locator.resolve_yaze_launcher()
end
local function resolve_sys_manual_binary(ctx)
  return locator.resolve_sys_manual_binary(ctx)
end

local function resolve_mesen_run(ctx)
  return locator.resolve_mesen_run(ctx)
end

local function resolve_oracle_agent_manager(ctx)
  return locator.resolve_oracle_agent_manager(ctx)
end

local function resolve_cortex_cli(ctx)
  return locator.resolve_cortex_cli(ctx)
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
  local state = type(ctx.state) == "table" and ctx.state or load_state(config_dir)
  local menu_config = read_menu_config(config_dir, state)

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

  local style = menu_style.compute(ctx)
  local font_small = style.font_small
  local font_bold = style.font_header
  local popup_item_height = style.item_height
  local popup_header_height = style.header_height
  local popup_item_corner_radius = style.item_corner_radius
  local popup_padding = style.padding or {}
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
        border_width = style.popup_border_width,
        corner_radius = style.popup_corner_radius,
        border_color = style.popup_border_color,
        color = style.popup_bg_color,
        padding_left = style.popup_padding,
        padding_right = style.popup_padding,
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
  local project_shortcuts = project_shortcuts_module.load(config_dir, code_dir, state)
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

  local function normalize_section_id(value)
    local section_id = tostring(value or ""):lower()
    if section_id == "" or section_id == "projects" then
      return "apps"
    end
    return section_id
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
      ["label.padding_left"] = popup_padding.label_left or 6,
      ["label.padding_right"] = popup_padding.label_right or 6,
      background = { drawing = false },
    })
  end

  local function add_header(meta, index)
    local label = meta.label or ""
    sbar.add("item", string.format("menu.tools.header.%s.%d", meta.id or "section", index), {
      position = "popup.apple_menu",
      icon = { drawing = false },
      label = { string = label, font = font_bold, color = meta.color or theme.WHITE },
      ["label.padding_left"] = popup_padding.label_left or 6,
      ["label.padding_right"] = popup_padding.label_right or 6,
      background = {
        drawing = true,
        color = meta.bg_color or theme.BG_SEC_COLR or theme.bar.bg,
        corner_radius = popup_item_corner_radius,
        height = popup_header_height,
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
      ["icon.padding_left"] = popup_padding.icon_left or 4,
      ["icon.padding_right"] = popup_padding.icon_right or 6,
      ["label.padding_left"] = popup_padding.label_left or 6,
      ["label.padding_right"] = popup_padding.label_right or 6,
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
  local studio_launcher, studio_launcher_ok = locator.resolve_afs_studio_launcher(ctx)
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

  local yaze_dir = select(1, locator.resolve_yaze_dir(ctx)) or (code_dir .. "/yaze")
  local afs_action = afs_browser_app and string.format("open %s", shell_quote(afs_browser_app)) or ""
  local studio_bin, studio_bin_ok = locator.resolve_afs_studio_binary(studio_root)
  local studio_action
  local studio_cmd
  if studio_launcher_ok and studio_launcher then
    studio_action = shell_quote(studio_launcher)
  elseif studio_bin_ok and studio_bin then
    if studio_bin:match("%.app/?$") then
      studio_action = string.format("open %s", shell_quote(studio_bin))
    else
      studio_action = shell_quote(studio_bin)
    end
  else
    if afs_root then
      studio_cmd = afs_cli(afs_root, "studio run --build")
    elseif studio_root then
      local build_dir = locator.afs_build_dir(studio_root)
      if locator.afs_studio_layout(studio_root) == "suite" then
        studio_cmd = string.format(
          "cd %s && cmake --build %s --target afs-studio && ./%s/apps/studio/afs-studio",
          shell_quote(studio_root),
          build_dir,
          build_dir
        )
      else
        studio_cmd = string.format(
          "cd %s && cmake --build build --target afs_studio && ./build/afs_studio",
          shell_quote(studio_root)
        )
      end
    end
    studio_action = terminal_action("afs_studio", studio_cmd)
  end
  local studio_available = studio_ok and (studio_launcher_ok or studio_bin_ok or studio_cmd ~= nil)
  local studio_blocked = studio_ok and not studio_launcher_ok and studio_cmd ~= nil and studio_action == nil

  local labeler_bin, labeler_bin_ok = locator.resolve_afs_labeler_binary(studio_root)
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
    local build_dir = locator.afs_build_dir(studio_root)
    if locator.afs_studio_layout(studio_root) == "suite" then
      labeler_cmd = string.format(
        "cd %s && cmake --build %s --target afs-labeler && ./%s/apps/studio/afs-labeler",
        shell_quote(studio_root),
        build_dir,
        build_dir
      )
    else
      labeler_cmd = string.format(
        "cd %s && cmake --build build --target afs_labeler && ./build/afs_labeler",
        shell_quote(studio_root)
      )
    end
    if labeler_csv and labeler_csv ~= "" then
      labeler_cmd = labeler_cmd .. " --csv " .. shell_quote(labeler_csv)
    end
    labeler_action = terminal_action("afs_labeler", labeler_cmd)
  end

  local cortex_toggle = cortex_cli_ok and (shell_quote(cortex_cli) .. " toggle") or ""
  local cortex_hub = cortex_cli_ok and (shell_quote(cortex_cli) .. " hub") or ""
  local sketchybar_bin = binary_resolver.resolve_sketchybar_bin()
  local function tc(k, d) return theme[k] or theme[d or "WHITE"] or theme.WHITE end

  -- AFS context helpers
  local afs_context_root = os.getenv("AFS_CONTEXT_ROOT")
    or ((os.getenv("HOME") or "") .. "/.context")
  local afs_scratchpad_dir = afs_context_root .. "/scratchpad"
  local afs_context_available = path_exists(afs_context_root, true)
  local afs_scratchpad_action = afs_context_available
    and open_terminal(string.format("ls -la %s && echo '--- Scratchpad ---' && cat %s/*.md 2>/dev/null || echo 'Empty'",
        shell_quote(afs_scratchpad_dir), shell_quote(afs_scratchpad_dir)))
    or ""
  local afs_query_action = ""
  if afs_root then
    afs_query_action = open_terminal(afs_cli(afs_root, "context query --interactive"))
  end

  local base_items = {
    {
      id = "afs_browser",
      label = "AFS Browser",
      icon = "󰈙",
      icon_color = tc("SAPPHIRE"),
      section = "apps",
      action = afs_action or "",
      shortcut_action = "launch_afs_browser",
      available = afs_browser_ok,
      default_enabled = true,
    },
    {
      id = "afs_context",
      label = "AFS Context Query",
      icon = "󰊕",
      icon_color = tc("TEAL"),
      section = "afs",
      action = afs_query_action,
      available = afs_root ~= nil,
      default_enabled = false,
    },
    {
      id = "afs_scratchpad",
      label = "AFS Scratchpad",
      icon = "󰏫",
      icon_color = tc("PEACH"),
      section = "afs",
      action = afs_scratchpad_action,
      available = afs_context_available,
      default_enabled = afs_context_available,
    },
    {
      id = "afs_studio",
      label = "AFS Studio",
      icon = "󰆍",
      icon_color = tc("LAVENDER"),
      section = "apps",
      action = studio_action or "",
      shortcut_action = "launch_afs_studio",
      available = studio_available,
      blocked = studio_blocked,
      default_enabled = true,
    },
    {
      id = "afs_labeler",
      label = "AFS Labeler",
      icon = "󰓹",
      icon_color = tc("TEAL"),
      section = "apps",
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
      section = "apps",
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
      section = "apps",
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
      label = "Cortex",
      icon = "󰕮",
      icon_color = tc("MAUVE", "LAVENDER"),
      section = "apps",
      action = cortex_hub,
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
      action = string.format("%q --reload", sketchybar_bin),
      shortcut_action = "reload_sketchybar",
      available = true,
      default_enabled = true,
    },
  }

  local sections = {
    apps = { id = "apps", label = "Apps", icon = "󰀻", color = tc("MAUVE", "LAVENDER"), order = 0 },
    core = { id = "core", label = "Core Tools", icon = "󰯙", color = tc("GREEN"), order = 1 },
    controls = { id = "controls", label = "Controls", icon = "󰒓", color = tc("SKY"), order = 2 },
    work = { id = "work", label = "Web Apps", icon = "󰖟", color = tc("BLUE"), order = 3 },
    support = { id = "support", label = "Support", icon = "󰘥", color = tc("LAVENDER"), order = 4 },
    afs = { id = "afs", label = "AFS Tools", icon = "󰈙", color = tc("SAPPHIRE"), order = 5 },
    audio = { id = "audio", label = "Audio", icon = "󰎈", color = tc("PEACH"), order = 6 },
    custom = { id = "custom", label = "Custom", icon = "󰘥", color = tc("LAVENDER"), order = 7 },
  }

  for section_id, override in pairs(menu_config.sections or {}) do
    if type(override) == "table" then
      local normalized_section_id = normalize_section_id(section_id)
      local section = sections[normalized_section_id] or {
        id = normalized_section_id,
        label = normalized_section_id,
        order = 99,
      }
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
      sections[normalized_section_id] = section
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
        section = normalize_section_id(override.section or item.section or "controls"),
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
            section = normalize_section_id(custom.section or "custom"),
          })
        end
      end
    end
  end

  if project_shortcuts.enabled then
    for index, project in ipairs(project_shortcuts.items or {}) do
      if project.available or show_missing then
        table.insert(rendered, {
          id = project.id,
          name = "menu.tools.project." .. project.id,
          label = project.label,
          icon = project.icon,
          icon_color = project.icon_color,
          label_color = project.label_color,
          action = project.action,
          shortcut = project.shortcut,
          missing = not project.available,
          order = project.order or (1300 + index),
          default_index = 1100 + index,
          section = normalize_section_id(project.section or "apps"),
        })
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
            section = normalize_section_id(app.section or "work"),
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

  return {
    popup_parents = { "apple_menu" },
    submenu_parents = {},
  }
end

return apple_menu
