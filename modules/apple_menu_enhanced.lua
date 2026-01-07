local apple_menu = {}

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

local function shell_quote(value)
  return string.format("%q", tostring(value))
end

local function open_terminal(command)
  if not command or command == "" then
    return ""
  end
  return string.format("osascript -e 'tell application \"Terminal\" to do script %q'", command)
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

local function resolve_path(ctx, candidates, want_dir)
  local fallback = nil
  for _, candidate in ipairs(candidates or {}) do
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
    code_dir .. "/lab/afs/apps/studio",
    code_dir .. "/lab/afs_studio",
    code_dir .. "/afs/apps/studio",
    code_dir .. "/afs_studio",
  }, true)
end

local function resolve_stemforge_app(ctx)
  local code_dir = resolve_code_dir(ctx)
  return resolve_path(ctx, {
    ctx.paths and ctx.paths.stemforge_app or nil,
    os.getenv("STEMFORGE_APP"),
    code_dir .. "/tools/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app",
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
    code_dir .. "/tools/stemsampler/StemSampler.app",
    code_dir .. "/tools/stem_sampler/StemSampler.app",
    os.getenv("HOME") .. "/Applications/StemSampler.app",
    "/Applications/StemSampler.app",
  }, true)
end

local function resolve_yaze_app(ctx)
  local code_dir = resolve_code_dir(ctx)
  return resolve_path(ctx, {
    ctx.paths and ctx.paths.yaze and (ctx.paths.yaze .. "/build/bin/yaze.app") or nil,
    code_dir .. "/hobby/yaze/build/bin/yaze.app",
    code_dir .. "/yaze/build/bin/yaze.app",
  }, true)
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

local function wrap_action(ctx, popup_name, entry_name, action)
  if not action or action == "" then
    return ""
  end
  local menu_action = ctx.menu_action or (ctx.config_dir and (ctx.config_dir .. "/helpers/menu_action")) or ""
  if menu_action ~= "" then
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
  local font_small = font_string(ctx, settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)
  local font_bold = font_string(ctx, settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small)

  local popup_border_width = (ctx.appearance and ctx.appearance.popup_border_width) or 2
  local popup_corner_radius = (ctx.appearance and ctx.appearance.popup_corner_radius) or 8
  local popup_border_color = (ctx.appearance and ctx.appearance.popup_border_color) or theme.WHITE
  local popup_bg_color = (ctx.appearance and ctx.appearance.popup_bg_color) or theme.BG_PRI_COLR or theme.bar.bg

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
    click_script = "sketchybar -m --set $NAME popup.drawing=toggle",
    popup = {
      background = {
        border_width = popup_border_width,
        corner_radius = popup_corner_radius,
        border_color = popup_border_color,
        color = popup_bg_color,
        padding_left = 8,
        padding_right = 8,
      },
    },
  })

  local subscribe_popup = ctx.subscribe_popup_autoclose or ctx.subscribe_mouse_exit
  if subscribe_popup then
    subscribe_popup("apple_menu")
  end

  local item_height = math.max(widget_height - 6, 20)

  local function add_header(name, icon, label, color)
    sbar.add("item", name, {
      position = "popup.apple_menu",
      icon = { string = icon or "", color = color or theme.WHITE, drawing = icon and icon ~= "" },
      label = { string = label or "", font = font_bold, color = theme.WHITE },
      ["icon.padding_left"] = 8,
      ["icon.padding_right"] = 6,
      ["label.padding_left"] = 4,
      ["label.padding_right"] = 8,
      ["label.padding_top"] = 2,
      background = { drawing = false },
    })
  end

  local function add_separator(name)
    sbar.add("item", name, {
      position = "popup.apple_menu",
      icon = { drawing = false },
      label = { string = "───────────────", font = font_small, color = "0x40cdd6f4" },
      ["label.padding_left"] = 8,
      background = { drawing = false },
    })
  end

  local hover_script = ctx.HOVER_SCRIPT
  if not hover_script and ctx.config_dir then
    local compiled_hover = ctx.config_dir .. "/bin/popup_hover"
    if path_exists(compiled_hover, false) then
      hover_script = compiled_hover
    else
      hover_script = ctx.config_dir .. "/plugins/popup_hover.sh"
    end
  end

  local code_dir = resolve_code_dir(ctx)
  local has_lab = code_dir and path_exists(code_dir .. "/lab", true)
  local show_missing = os.getenv("BARISTA_SHOW_MISSING_TOOLS") == "1" or has_lab

  local function add_item(entry)
    local enabled = entry.enabled ~= false
    local label = entry.label
    local icon_color = enabled and (entry.icon_color or theme.WHITE) or theme.DARK_WHITE
    local label_color = enabled and (entry.label_color or theme.WHITE) or theme.DARK_WHITE
    local action = entry.action
    if not enabled and not show_missing then
      return
    end
    if not enabled then
      local launcher = (ctx.config_dir or "") .. "/bin/open_control_panel.sh"
      local fallback = ctx.call_script and ctx.call_script(launcher, "--panel") or ""
      action = fallback
      label = label .. " (missing)"
    end
    sbar.add("item", entry.name, {
      position = "popup.apple_menu",
      icon = { string = entry.icon or "", color = icon_color },
      label = { string = label, font = font_small, color = label_color },
      click_script = wrap_action(ctx, "apple_menu", entry.name, action),
      script = hover_script,
      ["icon.padding_left"] = 10,
      ["icon.padding_right"] = 6,
      ["label.padding_left"] = 4,
      ["label.padding_right"] = 8,
      background = {
        drawing = false,
        corner_radius = 6,
        height = item_height,
      },
    })
    if ctx.attach_hover then
      ctx.attach_hover(entry.name)
    end
  end

  add_header("menu.tools.header", "󰕮", "Creative Tools", theme.LAVENDER)

  local afs_root, afs_ok = resolve_afs_root(ctx)
  local studio_root, studio_ok = resolve_afs_studio_root(ctx, afs_root)
  local stemforge_app, stemforge_ok = resolve_stemforge_app(ctx)
  local stem_sampler_app, stem_sampler_ok = resolve_stem_sampler_app(ctx)
  local yaze_app, yaze_ok = resolve_yaze_app(ctx)

  if not afs_root and code_dir then
    afs_root = code_dir .. "/lab/afs"
  end
  if not studio_root and code_dir then
    studio_root = code_dir .. "/lab/afs/apps/studio"
  end

  if afs_root or show_missing then
    local afs_tui = string.format("cd %s && python3 -m tui.app", shell_quote(afs_root or ""))
    add_item({
      name = "menu.tools.afs.browser",
      icon = "󰈙",
      label = "AFS Browser",
      icon_color = theme.SAPPHIRE,
      action = open_terminal(afs_tui),
      enabled = afs_ok or has_lab,
    })
  end

  if studio_root or show_missing then
    local studio_bin, studio_bin_ok = resolve_path(ctx, {
      studio_root and (studio_root .. "/build/afs_studio") or nil,
      studio_root and (studio_root .. "/build/bin/afs_studio") or nil,
    }, false)
    local studio_action
    if studio_bin_ok and studio_bin then
      studio_action = open_terminal(shell_quote(studio_bin))
    elseif afs_root then
      studio_action = open_terminal(afs_cli(afs_root, "studio run --build"))
    elseif studio_root then
      studio_action = open_terminal(string.format(
        "cd %s && cmake --build build --target afs_studio && ./build/afs_studio",
        shell_quote(studio_root)
      ))
    end
    add_item({
      name = "menu.tools.afs.studio",
      icon = "󰆍",
      label = "AFS Studio",
      icon_color = theme.LAVENDER,
      action = studio_action,
      enabled = studio_ok or has_lab,
    })

    local labeler_bin, labeler_bin_ok = resolve_path(ctx, {
      studio_root and (studio_root .. "/build/afs_labeler") or nil,
      studio_root and (studio_root .. "/build/bin/afs_labeler") or nil,
    }, false)
    local labeler_csv = os.getenv("AFS_LABELER_CSV")
    local labeler_cmd
    if labeler_bin_ok and labeler_bin then
      labeler_cmd = shell_quote(labeler_bin)
      if labeler_csv and labeler_csv ~= "" then
        labeler_cmd = labeler_cmd .. " --csv " .. shell_quote(labeler_csv)
      end
    elseif studio_root then
      labeler_cmd = string.format("cd %s && cmake --build build --target afs_labeler && ./build/afs_labeler", shell_quote(studio_root))
      if labeler_csv and labeler_csv ~= "" then
        labeler_cmd = labeler_cmd .. " --csv " .. shell_quote(labeler_csv)
      end
    end
    add_item({
      name = "menu.tools.afs.labeler",
      icon = "󰓹",
      label = "AFS Labeler",
      icon_color = theme.TEAL,
      action = open_terminal(labeler_cmd),
      enabled = (studio_ok and (labeler_bin_ok or (labeler_cmd and labeler_cmd ~= ""))) or has_lab,
    })
  end

  if stemforge_app or show_missing then
    add_item({
      name = "menu.tools.stemforge",
      icon = "󰎈",
      label = "StemForge",
      icon_color = theme.PINK,
      action = string.format("open %s", shell_quote(stemforge_app or "")),
      enabled = stemforge_ok or has_lab,
    })
  end

  if stem_sampler_app or show_missing then
    add_item({
      name = "menu.tools.stem_sampler",
      icon = "󰎈",
      label = "StemSampler",
      icon_color = theme.PEACH,
      action = string.format("open %s", shell_quote(stem_sampler_app or "")),
      enabled = stem_sampler_ok or has_lab,
    })
  end

  if yaze_app or show_missing then
    add_item({
      name = "menu.tools.yaze",
      icon = "󰯙",
      label = "Yaze",
      icon_color = theme.GREEN,
      action = string.format("open %s", shell_quote(yaze_app or "")),
      enabled = yaze_ok or has_lab,
    })
  end

  add_separator("menu.tools.sep1")
  add_header("menu.tools.barista.header", "󰒓", "Barista", theme.SKY)

  add_item({
    name = "menu.tools.barista.config",
    icon = "󰒓",
    label = "Barista Config",
    icon_color = theme.SKY,
    action = ctx.call_script((ctx.config_dir or "") .. "/bin/open_control_panel.sh", "--panel"),
    enabled = true,
  })

  add_item({
    name = "menu.tools.barista.reload",
    icon = "󰑐",
    label = "Reload SketchyBar",
    icon_color = theme.YELLOW,
    action = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload",
    enabled = true,
  })
end

return apple_menu
