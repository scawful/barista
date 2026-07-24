local apple_menu = {}
local apple_menu_model = require("apple_menu_model")
local binary_resolver = require("binary_resolver")
local menu_style = require("menu_style")
local locator = require("tool_locator")
local interface_extensions = require("interface_extensions")
local project_shortcuts_module = require("project_shortcuts")
local ui = require("ui_builder")
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

local function resolve_afs_studio_launcher(ctx)
  return locator.resolve_afs_studio_launcher(ctx)
end

local function resolve_afs_apps_launcher(ctx)
  return locator.resolve_afs_apps_launcher(ctx)
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

local function resolve_sys_manual_binary(ctx)
  return locator.resolve_sys_manual_binary(ctx)
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

local function wrap_action(menu_action, popup_name, entry_name, action)
  if not action or action == "" then
    return ""
  end
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

local function build_prepared(ctx)
  local theme = ctx.theme
  local settings = ctx.settings
  local config_dir = resolve_config_dir(ctx)
  local state = type(ctx.state) == "table" and ctx.state or load_state(config_dir)
  local menu_config = read_menu_config(config_dir, state)
  local style = menu_style.compute(ctx)
  local menu_action = resolve_menu_action(ctx, config_dir)
  local font_small = style.font_small
  local font_bold = style.font_header
  local popup_item_height = style.item_height
  local popup_header_height = style.header_height
  local popup_item_corner_radius = style.item_corner_radius
  local popup_padding = style.padding or {}

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
  local apple_extensions = interface_extensions.for_surface(config_dir, code_dir, state, "apple_menu")
  local show_missing = os.getenv("BARISTA_SHOW_MISSING_TOOLS") == "1"
  if type(menu_config.show_missing) == "boolean" then
    show_missing = menu_config.show_missing
  end

  local afs_root = select(1, resolve_afs_root(ctx))
  local studio_root = select(1, resolve_afs_studio_root(ctx, afs_root))
  local afs_apps_launcher, afs_apps_launcher_ok = resolve_afs_apps_launcher(ctx)
  local afs_studio_launcher, afs_studio_launcher_ok = resolve_afs_studio_launcher(ctx)
  local afs_studio_bin, afs_studio_bin_ok = locator.resolve_afs_studio_binary(studio_root)
  local afs_browser_app, afs_browser_ok = resolve_afs_browser_app(ctx)
  local ghostty_app, ghostty_ok = locator.resolve_ghostty_app(ctx)
  local lm_studio_app, lm_studio_ok = locator.resolve_lm_studio_app(ctx)
  local chatgpt_app, chatgpt_ok = locator.resolve_chatgpt_app(ctx)
  local claude_app, claude_ok = locator.resolve_claude_app(ctx)
  local cursor_app, cursor_ok = locator.resolve_cursor_app(ctx)
  local cortex_launcher, cortex_ok = locator.resolve_cortex_launcher(ctx)
  local stemforge_app, stemforge_ok = resolve_stemforge_app(ctx)
  local stem_sampler_app, stem_sampler_ok = resolve_stem_sampler_app(ctx)
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
  local function tc(k, d) return theme[k] or theme[d or "WHITE"] or theme.WHITE end
  local sketchybar_bin = binary_resolver.resolve_sketchybar_bin()
  local reload_action = ctx.call_script and ctx.call_script(config_dir .. "/plugins/reload_sketchybar.sh")
  if not reload_action or reload_action == "" then
    reload_action = string.format("%q --reload", sketchybar_bin)
  end
  local afs_action = ""
  local afs_available = false
  if afs_browser_app and afs_browser_ok then
    afs_action = string.format("open %s", shell_quote(afs_browser_app))
    afs_available = true
  elseif afs_apps_launcher and afs_apps_launcher_ok then
    afs_action = string.format("%s launch afs_studio", shell_quote(afs_apps_launcher))
    afs_available = true
  elseif afs_studio_launcher and afs_studio_launcher_ok then
    afs_action = shell_quote(afs_studio_launcher)
    afs_available = true
  elseif afs_studio_bin and afs_studio_bin_ok then
    if afs_studio_bin:match("%.app/?$") then
      afs_action = string.format("open %s", shell_quote(afs_studio_bin))
    else
      afs_action = shell_quote(afs_studio_bin)
    end
    afs_available = true
  end
  local ghostty_action = ""
  if ghostty_app and ghostty_ok then
    ghostty_action = string.format("open -na %s", shell_quote(ghostty_app))
  end
  local lm_studio_action = ""
  if lm_studio_app and lm_studio_ok then
    lm_studio_action = string.format("open %s", shell_quote(lm_studio_app))
  end
  local chatgpt_action = ""
  if chatgpt_app and chatgpt_ok then
    chatgpt_action = string.format("open %s", shell_quote(chatgpt_app))
  end
  local claude_action = ""
  if claude_app and claude_ok then
    claude_action = string.format("open %s", shell_quote(claude_app))
  end
  local cursor_action = ""
  if cursor_app and cursor_ok then
    cursor_action = string.format("open %s", shell_quote(cursor_app))
  end
  local cortex_action = ""
  if cortex_launcher and cortex_ok then
    cortex_action = shell_quote(cortex_launcher)
  end
  local labeler_bin, labeler_bin_ok = locator.resolve_afs_labeler_binary(studio_root, ctx)
  local labeler_csv = os.getenv("AFS_LABELER_CSV")
  local labeler_cmd
  local labeler_action
  if labeler_bin_ok and labeler_bin then
    if labeler_bin:match("%.app/?$") then
      labeler_action = string.format("open %s", shell_quote(labeler_bin))
    else
      labeler_cmd = shell_quote(labeler_bin)
      if labeler_csv and labeler_csv ~= "" then
        labeler_cmd = labeler_cmd .. " --csv " .. shell_quote(labeler_csv)
      end
      labeler_action = labeler_cmd
    end
  end
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
      action = afs_action,
      shortcut_action = "launch_afs_browser",
      available = afs_available,
      default_enabled = true,
    },
    {
      id = "cortex",
      label = "Cortex",
      icon = "󰘦",
      icon_color = tc("MAUVE", "LAVENDER"),
      section = "apps",
      action = cortex_action,
      available = cortex_ok,
      default_enabled = true,
    },
    {
      id = "lm_studio",
      label = "LM Studio",
      icon = "󰭻",
      icon_color = tc("GREEN"),
      section = "apps",
      action = lm_studio_action,
      available = lm_studio_ok,
      default_enabled = true,
    },
    {
      id = "ghostty",
      label = "Ghostty",
      icon = "",
      icon_color = tc("SKY"),
      section = "apps",
      action = ghostty_action,
      available = ghostty_ok,
      default_enabled = true,
    },
    {
      id = "chatgpt",
      label = "ChatGPT",
      icon = "󰚩",
      icon_color = tc("GREEN"),
      section = "apps",
      action = chatgpt_action,
      available = chatgpt_ok,
      default_enabled = true,
    },
    {
      id = "claude",
      label = "Claude",
      icon = "󰭹",
      icon_color = tc("PEACH"),
      section = "apps",
      action = claude_action,
      available = claude_ok,
      default_enabled = true,
    },
    {
      id = "cursor",
      label = "Cursor",
      icon = "󰨞",
      icon_color = tc("TEAL"),
      section = "apps",
      action = cursor_action,
      available = cursor_ok,
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
      default_enabled = false,
    },
    {
      id = "afs_labeler",
      label = "AFS Labeler",
      icon = "󰓹",
      icon_color = tc("TEAL"),
      section = "apps",
      action = labeler_action or "",
      shortcut_action = "launch_afs_labeler",
      available = labeler_bin_ok and labeler_action ~= nil,
      blocked = false,
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
      label = "Barista",
      icon = "󰒓",
      icon_color = tc("SKY"),
      section = "controls",
      action = ctx.call_script(config_dir .. "/bin/open_control_panel.sh", "--tab", "home"),
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
      action = reload_action,
      shortcut_action = "reload_sketchybar",
      available = true,
      default_enabled = true,
    },
  }

  local sections = {
    apps = { id = "apps", label = "Apps", icon = "󰀻", color = tc("MAUVE", "LAVENDER"), order = 0 },
    oracle = { id = "oracle", label = "Oracle", icon = "󰯙", color = tc("GREEN"), order = 1 },
    controls = { id = "controls", label = "Controls", icon = "󰒓", color = tc("SKY"), order = 2 },
    work = { id = "work", label = "Web Apps", icon = "󰖟", color = tc("BLUE"), order = 3 },
    support = { id = "support", label = "Support", icon = "󰘥", color = tc("LAVENDER"), order = 4 },
    afs = { id = "afs", label = "AFS Tools", icon = "󰈙", color = tc("SAPPHIRE"), order = 5 },
    audio = { id = "audio", label = "Audio", icon = "󰎈", color = tc("PEACH"), order = 6 },
    extensions = { id = "extensions", label = "Extensions", icon = "󰐕", color = tc("TEAL"), order = 7 },
    custom = { id = "custom", label = "Custom", icon = "󰘥", color = tc("LAVENDER"), order = 8 },
  }

  local menu_model = apple_menu_model.build({
    base_items = base_items,
    sections = sections,
    menu_config = menu_config,
    project_shortcuts = project_shortcuts,
    interface_extensions = { enabled = true, items = apple_extensions },
    show_missing = show_missing,
    theme = theme,
  })
  return {
    config_dir = config_dir,
    style = style,
    font_small = font_small,
    font_bold = font_bold,
    popup_item_height = popup_item_height,
    popup_header_height = popup_header_height,
    popup_item_corner_radius = popup_item_corner_radius,
    popup_padding = popup_padding,
    hover_script_cmd = hover_script_cmd,
    menu_action = menu_action,
    rendered = menu_model.rendered,
    sections = menu_model.sections,
  }
end

function apple_menu.prepare(ctx)
  return build_prepared(ctx)
end

function apple_menu.setup(ctx)
  local sbar = ctx.sbar
  local theme = ctx.theme
  local widget_height = ctx.widget_height
  local associated_displays = ctx.associated_displays or "all"
  local prepared = ctx.apple_menu_prepared or build_prepared(ctx)
  local config_dir = prepared.config_dir
  local style = prepared.style
  local font_small = prepared.font_small
  local font_bold = prepared.font_bold
  local popup_item_height = prepared.popup_item_height
  local popup_header_height = prepared.popup_header_height
  local popup_item_corner_radius = prepared.popup_item_corner_radius
  local popup_padding = prepared.popup_padding
  local hover_script_cmd = prepared.hover_script_cmd
  local menu_action = prepared.menu_action
  local rendered = prepared.rendered
  local sections = prepared.sections

  local function popup_toggle(item_name, opts)
    if type(ctx.popup_toggle_action) == "function" then
      return ctx.popup_toggle_action(item_name, opts)
    end
    if item_name and item_name ~= "" then
      return string.format("sketchybar -m --set %s popup.drawing=toggle", item_name)
    end
    return "sketchybar -m --set $NAME popup.drawing=toggle"
  end
  local apple_menu_script = ui.anchor_script(ctx.popup_anchor_script, ctx, {
    height = widget_height,
    padding_left = 4,
    padding_right = 4,
  })
  local apple_menu_background = ui.anchor_chip_style(ctx, {
    height = widget_height,
    padding_left = 4,
    padding_right = 4,
  })

  sbar.add("item", "apple_menu", {
    position = "left",
    icon = ctx.icon_for and ctx.icon_for("apple", "") or "",
    label = { drawing = false },
    associated_display = associated_displays,
    associated_space = "all",
    background = apple_menu_background,
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
    script = apple_menu_script,
  })

  local subscribe_popup = ctx.subscribe_popup_autoclose or ctx.subscribe_mouse_exit
  if subscribe_popup then
    subscribe_popup("apple_menu")
  end

  local item_height = popup_item_height
  local popup_parents = { apple_menu = true }
  local submenu_parents = {}
  local submenu_ancestors = {}

  local function remember_popup(name)
    if type(name) == "string" and name ~= "" then
      popup_parents[name] = true
    end
  end

  local function remember_submenu(name, containing_popup)
    if type(name) ~= "string" or name == "" then
      return
    end
    submenu_parents[name] = true
    if not submenu_parents[containing_popup] then
      return
    end

    local ancestors = submenu_ancestors[name] or {}
    local seen = {}
    for _, ancestor in ipairs(ancestors) do
      seen[ancestor] = true
    end
    local function add_ancestor(ancestor)
      if type(ancestor) == "string" and ancestor ~= "" and ancestor ~= name
          and not seen[ancestor] then
        seen[ancestor] = true
        table.insert(ancestors, ancestor)
      end
    end

    add_ancestor(containing_popup)
    for _, ancestor in ipairs(submenu_ancestors[containing_popup] or {}) do
      add_ancestor(ancestor)
    end
    table.sort(ancestors)
    submenu_ancestors[name] = ancestors
  end

  local function list_popup_parents()
    local items = {}
    for name in pairs(popup_parents) do
      table.insert(items, name)
    end
    table.sort(items)
    return items
  end

  local function list_submenu_parents()
    local items = {}
    for name in pairs(submenu_parents) do
      table.insert(items, name)
    end
    table.sort(items)
    return items
  end

  local function popup_key(name)
    return tostring(name or "apple_menu"):gsub("[^%w]+", "_")
  end

  local function popup_background()
    return {
      border_width = style.popup_border_width,
      corner_radius = style.popup_corner_radius,
      border_color = style.popup_border_color,
      color = style.popup_bg_color,
      padding_left = style.popup_padding,
      padding_right = style.popup_padding,
    }
  end

  local function add_separator(popup_name, index)
    sbar.add("item", string.format("menu.tools.sep.%s.%d", popup_key(popup_name), index), {
      position = "popup." .. popup_name,
      icon = { drawing = false },
      label = { string = "───────────────", font = font_small, color = theme.DARK_WHITE },
      ["label.padding_left"] = popup_padding.label_left or 6,
      ["label.padding_right"] = popup_padding.label_right or 6,
      background = { drawing = false },
    })
  end

  local function add_header(popup_name, meta, index)
    local label = meta.label or ""
    sbar.add("item", string.format("menu.tools.header.%s.%s.%d", popup_key(popup_name), meta.id or "section", index), {
      position = "popup." .. popup_name,
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

  local render_popup_items

  local function add_item(popup_name, entry, parent_popup)
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
    if entry.missing and (not action or action == "") then
      local launcher = config_dir .. "/bin/open_control_panel.sh"
      local fallback = ctx.call_script and ctx.call_script(launcher, "--panel") or ""
      action = fallback
    elseif entry.blocked and (not action or action == "") then
      local launcher = config_dir .. "/bin/open_control_panel.sh"
      local fallback = ctx.call_script and ctx.call_script(launcher, "--panel") or ""
      action = fallback
    end
    local click_script = wrap_action(menu_action, parent_popup or popup_name, entry.name, action)
    local popup_config = nil
    local hover_enabled = entry.hover == true
      or (entry.hover ~= false and (
        (entry.action and entry.action ~= "")
        or entry.missing == true
        or entry.blocked == true
        or (entry.submenu and entry.items and #entry.items > 0)
      ))
    if entry.submenu and entry.items and #entry.items > 0 then
      remember_submenu(entry.name, popup_name)
      click_script = popup_toggle(entry.name, { direct = true, origin = "submenu" })
      label = string.format("%s  %s", label, entry.arrow_icon or "󰅂")
      popup_config = {
        align = "right",
        background = popup_background(),
      }
    end
    local item_config = {
      position = "popup." .. popup_name,
      icon = { string = entry.icon or "", color = icon_color },
      label = { string = label, font = font_small, color = label_color },
      click_script = click_script,
      ["icon.padding_left"] = popup_padding.icon_left or 4,
      ["icon.padding_right"] = popup_padding.icon_right or 6,
      ["label.padding_left"] = popup_padding.label_left or 6,
      ["label.padding_right"] = popup_padding.label_right or 6,
      background = {
        drawing = false,
        corner_radius = popup_item_corner_radius,
        height = item_height,
      },
    }
    if hover_enabled and hover_script_cmd then
      item_config.script = hover_script_cmd
    end
    if popup_config then
      item_config.popup = popup_config
    end
    sbar.add("item", entry.name, item_config)
    if hover_enabled and ctx.attach_hover then
      ctx.attach_hover(entry.name)
    end
    if popup_config then
      render_popup_items(entry.name, entry.items, entry.name)
    end
  end

  render_popup_items = function(popup_name, entries, parent_popup)
    local section_index = 1
    for _, entry in ipairs(entries or {}) do
      if entry.type == "header" then
        add_header(popup_name, entry, section_index)
        section_index = section_index + 1
      elseif entry.type == "separator" then
        add_separator(popup_name, section_index)
        section_index = section_index + 1
      else
        add_item(popup_name, entry, parent_popup)
      end
    end
  end

  local current_section = nil
  local section_index = 1
  for _, entry in ipairs(rendered) do
    if entry.section ~= current_section then
      if current_section ~= nil then
        add_separator("apple_menu", section_index)
        section_index = section_index + 1
      end
      add_header("apple_menu", sections[entry.section] or { id = entry.section, label = entry.section }, section_index)
      section_index = section_index + 1
      current_section = entry.section
    end
    add_item("apple_menu", entry)
  end

  return {
    popup_parents = list_popup_parents(),
    submenu_parents = list_submenu_parents(),
    submenu_ancestors = submenu_ancestors,
  }
end

return apple_menu
