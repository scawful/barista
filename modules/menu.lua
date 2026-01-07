local menu = {}
local json = require("json")
local menu_renderer = require("menu_renderer")

local unpack = table.unpack or _G.unpack

local function load_menu_section(ctx, name)
  if not ctx.paths or not ctx.paths.menu_data then return nil end
  local path = string.format("%s/%s.json", ctx.paths.menu_data, name)
  local file = io.open(path, "r")
  if not file then return nil end
  local contents = file:read("*a")
  file:close()
  local ok, data = pcall(json.decode, contents)
  return ok and type(data) == "table" and data or nil
end

local function apply_menu_template(value, ctx)
  if type(value) ~= "string" then
    return value
  end
  local config_dir = (ctx.paths and ctx.paths.config_dir) or (os.getenv("BARISTA_CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar"))
  local code_dir = (ctx.paths and ctx.paths.code_dir) or (os.getenv("BARISTA_CODE_DIR") or (os.getenv("HOME") .. "/src"))
  local expanded = value:gsub("%%CONFIG%%", config_dir)
  expanded = expanded:gsub("%%CODE%%", code_dir)
  return expanded
end

local function path_exists(path, want_dir)
  if not path or path == "" then
    return false
  end
  local flag = want_dir and "-d" or "-e"
  local ok = os.execute(string.format("test %s %q", flag, path))
  return ok == true or ok == 0
end

local function open_terminal(command)
  if not command or command == "" then
    return ""
  end
  return string.format("osascript -e 'tell application \"Terminal\" to do script %q'", command)
end

local function shell_quote(value)
  return string.format("%q", tostring(value))
end

local function resolve_code_dir(ctx)
  return (ctx.paths and ctx.paths.code_dir) or (os.getenv("BARISTA_CODE_DIR") or (os.getenv("HOME") .. "/src"))
end

local function resolve_path(ctx, candidates, want_dir)
  local fallback = nil
  for _, candidate in ipairs(candidates or {}) do
    if candidate and candidate ~= "" then
      fallback = fallback or candidate
      if path_exists(candidate, want_dir) then
        return candidate
      end
    end
  end
  return fallback
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
    code_dir .. "/tools/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app",
    code_dir .. "/tools/stemforge/build/StemForge_artefacts/Debug/Standalone/StemForge.app",
    code_dir .. "/lab/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app",
    code_dir .. "/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app",
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

local function append_items(target, items)
  for _, item in ipairs(items or {}) do
    table.insert(target, item)
  end
end

local function menu_entry_from_data(ctx, entry, prefix)
  if type(entry) ~= "table" then
    return nil
  end
  local id = entry.id or entry.name or entry.label or entry.title or "item"
  local name = string.format("%s.%s", prefix, tostring(id):gsub("%s+", "_"))
  local label = entry.label or entry.title or tostring(id)
  local icon = entry.icon or ""
  local action = nil

  if entry.action == "help_center" then
    action = ctx.open_path(ctx.helpers.help_center)
  elseif entry.path_key and ctx.paths and ctx.paths[entry.path_key] then
    action = ctx.open_path(ctx.paths[entry.path_key])
  elseif entry.command then
    action = apply_menu_template(entry.command, ctx)
  end

  if not action or action == "" then
    return nil
  end

  return { type = "item", name = name, icon = icon, label = label, action = action }
end

local function focus_emacs_action(ctx)
  local check_cmd = "pgrep -x Emacs > /dev/null"
  local emacs_running = os.execute(check_cmd) == 0
  if emacs_running then
    return ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs")
  else
    return "osascript -e 'display notification \"Emacs is not running\" with title \"Focus Emacs\"'"
  end
end

-- ... [Keep existing helper functions: rom_hacking_items, emacs_items, oracle_items, halext_items, help_items] ...
-- I will inline them for brevity in this write, but in a real scenario I'd keep them.
-- Since I'm overwriting the file, I must include them.

local function rom_hacking_items(ctx)
  if ctx.integration_flags and ctx.integration_flags.yaze == false then
    return {{ type = "item", name = "menu.rom.customize", icon = "󰈙", label = "Customize Workflow", action = ctx.open_path(ctx.paths.whichkey_plan) }}
  end
  if ctx.integrations and ctx.integrations.yaze then
    return ctx.integrations.yaze.create_menu_items(ctx)
  end
  local yaze_repo = ctx.paths.yaze
  if not path_exists(yaze_repo, true) then
    return {{ type = "item", name = "menu.rom.missing", icon = "⚠️", label = "Yaze Repo Missing", action = ctx.open_path(ctx.paths.whichkey_plan) }}
  end
  local yaze_binary = string.format("open -a %q", yaze_repo .. "/build/bin/yaze.app/Contents/MacOS/yaze")
  return {
    { type = "item", name = "menu.rom.launch", icon = "󰯙", label = "Launch Yaze", action = yaze_binary },
    { type = "item", name = "menu.rom.repo", icon = "󰋜", label = "Open Yaze Repo", action = ctx.open_path(yaze_repo) },
    { type = "item", name = "menu.rom.doc", icon = "󰊕", label = "ROM Workflow Doc", action = ctx.open_path(ctx.paths.rom_doc) },
    { type = "item", name = "menu.rom.focus_emacs", icon = "󰘔", label = "Focus Emacs Space", action = focus_emacs_action(ctx) },
  }
end

local function emacs_items(ctx)
  if ctx.integration_flags and ctx.integration_flags.emacs == false then
    return {{ type = "item", name = "menu.emacs.customize", icon = "󰈙", label = "Bring your own workflow", action = ctx.open_path(ctx.paths.whichkey_plan) }}
  end
  if ctx.integrations and ctx.integrations.emacs then return ctx.integrations.emacs.create_menu_items(ctx) end
  local code_dir = (ctx.paths and ctx.paths.code_dir) or (os.getenv("BARISTA_CODE_DIR") or (os.getenv("HOME") .. "/src"))
  return {
    { type = "item", name = "menu.emacs.launch", icon = "", label = "Launch Emacs", action = "open -a Emacs" },
    { type = "item", name = "menu.emacs.tasks", icon = "󰩹", label = "Tasks.org", action = ctx.open_path(code_dir .. "/docs/workflow/tasks.org") },
    { type = "item", name = "menu.emacs.focus", icon = "󰘔", label = "Focus Emacs Space", action = focus_emacs_action(ctx) },
  }
end

local function oracle_items(ctx)
  if ctx.integrations and ctx.integrations.oracle then return ctx.integrations.oracle.create_menu_items(ctx) end
  return {{ type = "item", name = "menu.oracle.missing", icon = "⚠️", label = "Integration Disabled" }}
end

local function halext_items(ctx)
  if ctx.integration_flags and ctx.integration_flags.halext == false then
    return {{ type = "item", name = "menu.halext.configure", icon = "", label = "Configure halext-org", action = ctx.call_script(ctx.scripts.halext_menu, "configure") }}
  end
  if ctx.integrations and ctx.integrations.halext then return ctx.integrations.halext.create_menu_items(ctx) end
  local halext_script = ctx.scripts.halext_menu or ""
  return {
    { type = "header", name = "menu.halext.header", label = "halext-org" },
    { type = "item", name = "menu.halext.tasks", icon = "", label = "View Tasks", action = ctx.call_script(halext_script, "open_tasks") },
    { type = "item", name = "menu.halext.suggestions", icon = "󰚩", label = "LLM Suggestions", action = ctx.call_script(halext_script, "open_suggestions") },
  }
end

local function help_items(ctx)
  local custom = load_menu_section(ctx, "menu_help")
  if custom then
    local items = {}
    for _, entry in ipairs(custom) do
      local item = menu_entry_from_data(ctx, entry, "menu.help")
      if item then
        table.insert(items, item)
      end
    end
    if #items > 0 then
      return items
    end
  end

  return {
    { type = "item", name = "menu.help.center", icon = "󰘥", label = "Open Help Center", action = ctx.open_path(ctx.helpers.help_center) },
    { type = "item", name = "menu.help.handoff", icon = "󰣖", label = "Open HANDOFF Notes", action = ctx.open_path(ctx.paths.handoff) },
  }
end

-- === MAIN RENDER FUNCTION === --

function menu.render_all_menus(ctx)
  local appearance = ctx.appearance or {}
  local popup_border_width = appearance.popup_border_width or 2
  local popup_corner_radius = appearance.popup_corner_radius or 4
  local popup_border_color = appearance.popup_border_color or ctx.theme.WHITE
  local popup_bg_color = appearance.popup_bg_color or ctx.theme.bar.bg

  -- Use enhanced apple menu if available
  local ok, apple_menu_enhanced = pcall(require, "apple_menu_enhanced")
  if ok then
    -- Enhanced apple menu handles its own rendering
    local HOME = os.getenv("HOME")
    local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
    local scripts_dir = (ctx.scripts and ctx.scripts.yabai_control and ctx.scripts.yabai_control:match("^(.+)/[^/]+$")) or (CONFIG_DIR .. "/scripts")

    apple_menu_enhanced.setup({
      sbar = ctx.sbar,
      theme = ctx.theme,
      settings = ctx.settings,
      appearance = ctx.appearance,
      widget_height = ctx.widget_height,
      font_string = ctx.font_string,
      attach_hover = ctx.attach_hover,
      subscribe_mouse_exit = ctx.subscribe_popup_autoclose,
      icon_for = ctx.icon_for,
      call_script = ctx.call_script,
      paths = ctx.paths,
      helpers = ctx.helpers,
      menu_action = ctx.scripts and ctx.scripts.menu_action or nil,
      scripts_dir = scripts_dir,
      config_dir = CONFIG_DIR,
      associated_displays = ctx.associated_displays,
      yabai_control_script = ctx.scripts.yabai_control,
    })
    return
  end

  -- Fallback to standard menu rendering
  local renderer = menu_renderer.create(ctx)
  local render_menu_items = renderer.render
  local sbar = ctx.sbar
  local theme = ctx.theme
  local widget_height = ctx.widget_height
  local associated_displays = ctx.associated_displays or "all"
  
  -- 1. System Menu (Apple Icon)
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
        padding_right = 4
    },
    click_script = "sketchybar -m --set $NAME popup.drawing=toggle",
    popup = {
      background = {
        border_width = popup_border_width,
        corner_radius = popup_corner_radius,
        border_color = popup_border_color,
        color = popup_bg_color,
      }
    }
  })
  ctx.subscribe_popup_autoclose("apple_menu")
  
  local apple_menu_items = {}

  local afs_root = resolve_afs_root(ctx)
  local studio_root = resolve_afs_studio_root(ctx, afs_root)
  local stemforge_app = resolve_stemforge_app(ctx)
  local stem_sampler_app = resolve_stem_sampler_app(ctx)
  local yaze_app = resolve_yaze_app(ctx)

  if afs_root then
    local afs_tui = string.format("cd %s && python3 -m tui.app", shell_quote(afs_root))
    table.insert(apple_menu_items, {
      type = "item",
      name = "menu.tools.afs.browser",
      icon = "󰈙",
      label = "AFS Browser",
      action = open_terminal(afs_tui),
    })
  end

  if studio_root then
    local studio_bin = resolve_path(ctx, {
      studio_root .. "/build/afs_studio",
      studio_root .. "/build/bin/afs_studio",
    }, false)
    local studio_action
    if studio_bin and studio_bin ~= "" then
      studio_action = open_terminal(shell_quote(studio_bin))
    elseif afs_root then
      studio_action = open_terminal(afs_cli(afs_root, "studio run --build"))
    else
      studio_action = open_terminal(string.format("cd %s && cmake --build build --target afs_studio && ./build/afs_studio", shell_quote(studio_root)))
    end
    table.insert(apple_menu_items, {
      type = "item",
      name = "menu.tools.afs.studio",
      icon = "󰆍",
      label = "AFS Studio",
      action = studio_action,
    })

    local labeler_bin = resolve_path(ctx, {
      studio_root .. "/build/afs_labeler",
      studio_root .. "/build/bin/afs_labeler",
    }, false)
    local labeler_csv = os.getenv("AFS_LABELER_CSV")
    local labeler_cmd
    if labeler_bin and labeler_bin ~= "" then
      labeler_cmd = shell_quote(labeler_bin)
      if labeler_csv and labeler_csv ~= "" then
        labeler_cmd = labeler_cmd .. " --csv " .. shell_quote(labeler_csv)
      end
    else
      labeler_cmd = string.format("cd %s && cmake --build build --target afs_labeler && ./build/afs_labeler", shell_quote(studio_root))
      if labeler_csv and labeler_csv ~= "" then
        labeler_cmd = labeler_cmd .. " --csv " .. shell_quote(labeler_csv)
      end
    end
    table.insert(apple_menu_items, {
      type = "item",
      name = "menu.tools.afs.labeler",
      icon = "󰓹",
      label = labeler_bin and "AFS Labeler" or "Build AFS Labeler",
      action = open_terminal(labeler_cmd),
    })
  end

  if stemforge_app then
    table.insert(apple_menu_items, {
      type = "item",
      name = "menu.tools.stemforge",
      icon = "󰎈",
      label = "StemForge",
      action = string.format("open %s", shell_quote(stemforge_app)),
    })
  end

  if stem_sampler_app then
    table.insert(apple_menu_items, {
      type = "item",
      name = "menu.tools.stem_sampler",
      icon = "󰎈",
      label = "StemSampler",
      action = string.format("open %s", shell_quote(stem_sampler_app)),
    })
  end

  if yaze_app then
    table.insert(apple_menu_items, {
      type = "item",
      name = "menu.tools.yaze",
      icon = "󰯙",
      label = "Yaze",
      action = string.format("open %s", shell_quote(yaze_app)),
    })
  end

  local help_center = ctx.helpers and ctx.helpers.help_center or nil
  if help_center and path_exists(help_center, false) then
    table.insert(apple_menu_items, {
      type = "item",
      name = "menu.tools.help_center",
      icon = "󰘥",
      label = "Help Center",
      action = help_center,
    })
  end

  local icon_browser = (ctx.paths and ctx.paths.config_dir) and (ctx.paths.config_dir .. "/gui/bin/icon_browser") or nil
  if icon_browser and path_exists(icon_browser, false) then
    table.insert(apple_menu_items, {
      type = "item",
      name = "menu.tools.icon_browser",
      icon = "󰈙",
      label = "Icon Browser",
      action = icon_browser,
    })
  end

  table.insert(apple_menu_items, {
    type = "item",
    name = "menu.tools.barista.config",
    icon = "󰒓",
    label = "Barista Config",
    action = ctx.call_script(ctx.paths.apple_launcher, "--panel"),
    shortcut = "⌘⌥P",
  })
  table.insert(apple_menu_items, {
    type = "item",
    name = "menu.tools.barista.reload",
    icon = "󰑐",
    label = "Reload SketchyBar",
    action = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload",
    shortcut = "⌘⌥R",
  })

  render_menu_items("apple_menu", apple_menu_items)
end

menu.rom_hacking_items = rom_hacking_items
menu.emacs_items = emacs_items
menu.oracle_items = oracle_items
menu.halext_items = halext_items
menu.help_items = help_items
menu.app_tool_items = function() return {} end
menu.dev_tool_items = function() return {} end
menu.launch_agent_items = function() return {} end
menu.debug_tool_items = function() return {} end

return menu
