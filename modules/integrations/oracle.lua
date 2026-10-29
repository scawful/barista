-- Oracle workflow integration for Barista.
-- The Triforce popup stays shallow: launch the stable ROM or the newest test
-- build, plus the editor and emulator apps.

local oracle = {}

local locator = require("tool_locator")
local ui = require("ui_builder")

local state = locator.load_state()
local state_paths = state and type(state.paths) == "table" and state.paths or {}
local CODE_DIR = locator.resolve_code_dir({ state = state })
local ORACLE_DIR = os.getenv("BARISTA_ORACLE_DIR")
  or state_paths.oracle
  or (CODE_DIR .. "/hobby/oracle-of-secrets")
local TRIFORCE_WIDGET = os.getenv("BARISTA_TRIFORCE_WIDGET")
  or state_paths.triforce_widget
  or locator.command_path("oos-triforce-widget")
  or ""

oracle.config = {
  repo_path = ORACLE_DIR,
  z3dk_repo = os.getenv("BARISTA_Z3DK_DIR") or state_paths.z3dk or (CODE_DIR .. "/hobby/z3dk"),
  triforce_widget = TRIFORCE_WIDGET,
  status_script = os.getenv("BARISTA_ORACLE_STATUS_SCRIPT")
    or state_paths.oracle_status_script
    or (ORACLE_DIR .. "/Scripts/Build/oos-triforce.sh"),
  ganondorf_launcher = os.getenv("BARISTA_GANONDORF_LAUNCHER")
    or state_paths.ganondorf_launcher
    or "",
  -- The working yaze project: Lyra Sea sidecar ($A0-$BF) + native maps.
  lyra_project = os.getenv("BARISTA_ORACLE_LYRA_PROJECT")
    or state_paths.oracle_lyra_project
    or ((os.getenv("HOME") or "") .. "/Zelda/Projects/Oracle-of-Secrets/Oracle-Working/Oracle-of-Secrets-Working.yaze"),
  project_launcher = os.getenv("BARISTA_ORACLE_PROJECT_LAUNCHER")
    or state_paths.oracle_project_launcher,
  handoff = ORACLE_DIR .. "/.context/scratchpad/agent_handoff.md",
  tracker = ORACLE_DIR .. "/oracle.org",
  workflow_plan = ORACLE_DIR .. "/Docs/Planning/Plans/development_workflow_alignment_2026-03-28.md",
  runbook = ORACLE_DIR .. "/RUNBOOK.md",
}

local section_defaults = {
  play = { label = "Play", order = 10, color_key = "GREEN", enabled = true, limit = 5, icon = "󰐃", presentation = "direct" },
  apps = { label = "Apps", order = 20, color_key = "LAVENDER", enabled = true, limit = 5, icon = "󰀻", presentation = "direct" },
}

local function normalize_bool(value)
  if type(value) == "boolean" then
    return value
  end
  if type(value) == "number" then
    return value ~= 0
  end
  if type(value) == "string" then
    local lowered = value:lower()
    if lowered == "1" or lowered == "true" or lowered == "yes" or lowered == "on" then
      return true
    end
    if lowered == "0" or lowered == "false" or lowered == "no" or lowered == "off" then
      return false
    end
  end
  return nil
end

local function normalize_number(value)
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" then
    return tonumber(value)
  end
  return nil
end

local function path_exists(path, want_dir)
  return locator.path_exists(path, want_dir)
end

local function path_is_executable(path)
  return locator.path_is_executable(path)
end

local function shell_quote(value)
  return string.format("%q", tostring(value or ""))
end

local function bash_literal(value)
  return "'" .. tostring(value or ""):gsub("'", "'\"'\"'") .. "'"
end

local function open_app_action(path)
  if type(path) ~= "string" or path == "" then
    return ""
  end
  return string.format("open %s", shell_quote(path))
end

local function terminal_action(command, ctx)
  local function debounced_command(key, raw_command)
    if not raw_command or raw_command == "" then
      return ""
    end
    local raw_key = tostring(key or "action"):gsub("[^%w]+", "_")
    local lock_dir = string.format("/tmp/barista_popup_%s.lock", raw_key)
    local wrapped = string.format(
      "lock_dir=%s; if ! mkdir \"$lock_dir\" 2>/dev/null; then exit 0; fi; trap 'rmdir \"$lock_dir\"' EXIT; %s; sleep 0.75",
      shell_quote(lock_dir),
      raw_command
    )
    return "bash -lc " .. bash_literal(wrapped)
  end

  local ghostty_app = select(1, locator.resolve_ghostty_app(ctx or {}))
  if ghostty_app and ghostty_app ~= "" then
    if command and command ~= "" then
      return debounced_command(
        "ghostty_terminal",
        string.format("open -na %s --args -e /bin/zsh -lc %s", shell_quote(ghostty_app), shell_quote(command))
      )
    end
    return debounced_command("ghostty_terminal", string.format("open -na %s", shell_quote(ghostty_app)))
  end
  if command and command ~= "" then
    return string.format("osascript -e 'tell application \"Terminal\" to do script %q'", command)
  end
  return "open -a Terminal"
end

local function binary_action(path)
  if type(path) ~= "string" or path == "" then
    return ""
  end
  return shell_quote(path)
end

local function truncate_label(value, max_len)
  value = tostring(value or "")
  if #value <= max_len then
    return value
  end
  return value:sub(1, math.max(0, max_len - 1)) .. "…"
end

local function sanitize_id(value, fallback)
  local raw = tostring(value or fallback or "item")
  raw = raw:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if raw == "" then
    return tostring(fallback or "item")
  end
  return raw
end

local function repo_action(command)
  if not command or command == "" then
    return ""
  end
  return string.format(
    "bash -lc %q",
    string.format("cd %s && %s", shell_quote(oracle.config.repo_path), command)
  )
end

local function theme_color(ctx, key, fallback)
  local theme = ctx and ctx.theme or {}
  return theme[key] or theme[fallback or "WHITE"] or "0xffcdd6f4"
end

local function popup_font(ctx, style, size)
  local settings = ctx and ctx.settings or nil
  if ctx and ctx.font_string and settings and settings.font and settings.font.style_map then
    return ctx.font_string(settings.font.text, settings.font.style_map[style], size)
  end
  return nil
end

local function popup_style(ctx)
  return ui.popup_style(ctx)
end

local function get_field(value, path)
  if type(path) == "string" then
    local parts = {}
    for part in path:gmatch("[^.]+") do
      table.insert(parts, part)
    end
    path = parts
  end
  for _, part in ipairs(path or {}) do
    if type(value) ~= "table" then
      return nil
    end
    value = value[part]
  end
  return value
end

local function parse_version_from_command(command)
  if type(command) ~= "string" then
    return nil
  end
  local version = command:match("oos%-verify%.sh%s+(%d+)")
    or command:match("oos%-quick%.sh%s+(%d+)")
  if version then
    return tonumber(version)
  end
  return nil
end

local function detect_rom_version(repo_path)
  local handle = io.popen(string.format("ls %s 2>/dev/null", shell_quote(repo_path .. "/Roms")))
  if not handle then
    return nil
  end
  local best
  for name in handle:lines() do
    local version = tonumber(name:match("^oos(%d+)x%.sfc$") or "")
    if version and (not best or version > best) then
      best = version
    end
  end
  handle:close()
  return best
end

-- Newest dev build, the same pick as `oos-triforce.sh launch test`: the
-- Roms/TestBuilds/<name>/ folder whose oos*x.sfc changed last. Agents put a
-- build there when the user should try it before it is staged for playtest.
local function detect_dev_build(repo_path)
  local handle = io.popen(string.format(
    "ls -t %s/Roms/TestBuilds/*/oos*x.sfc 2>/dev/null",
    shell_quote(repo_path)
  ))
  if not handle then
    return nil
  end
  local newest = handle:read("*l")
  handle:close()
  if not newest or newest == "" then
    return nil
  end
  return newest:match("/Roms/TestBuilds/([^/]+)/[^/]+$")
end

-- "kydreeok-pr209-2026-10-19" -> "Dev kydreeok-pr209" (the date is in the folder).
local function dev_build_label(name)
  if not name or name == "" then
    return "Dev build"
  end
  local short = name:gsub("%-%d%d%d%d%-%d%d%-%d%d$", "")
  return "Dev " .. short
end

local function finishline_color(level)
  local colors = {
    ok = "0xffa6e3a1",
    warn = "0xfff9e2af",
    error = "0xfff38ba8",
  }
  return colors[level] or "0xff89b4fa"
end

local function current_density(state)
  local appearance = state and state.appearance or {}
  local menu_item_height = normalize_number(appearance.menu_item_height) or 23
  if menu_item_height <= 21 then
    return "compact"
  end
  if menu_item_height >= 26 then
    return "comfortable"
  end
  return "default"
end

local function ui_config(ctx)
  local menus = ctx and ctx.state and ctx.state.menus or {}
  local oracle_menu = type(menus.oracle) == "table" and menus.oracle or {}
  local triforce = type(oracle_menu.triforce) == "table" and oracle_menu.triforce or {}
  local sections = type(oracle_menu.sections) == "table" and oracle_menu.sections or {}

  return {
    raw = oracle_menu,
    triforce = {
      label = type(triforce.label) == "string" and triforce.label or "",
      icon = type(triforce.icon) == "string" and triforce.icon or "",
      title = type(triforce.title) == "string" and triforce.title or "",
      show_label = normalize_bool(triforce.show_label) == true,
    },
    sections = sections,
  }
end

local function section_setting(ui, section_id)
  local sections = ui and ui.sections or {}
  local value = sections[section_id]
  if type(value) == "table" then
    return value
  end
  return {}
end

local function section_enabled(ui, section_id)
  local defaults = section_defaults[section_id] or {}
  local enabled = normalize_bool(section_setting(ui, section_id).enabled)
  if enabled == nil then
    return defaults.enabled ~= false
  end
  return enabled
end

local function section_label(ui, section_id)
  local defaults = section_defaults[section_id] or {}
  local label = section_setting(ui, section_id).label
  if type(label) == "string" and label ~= "" then
    return label
  end
  return defaults.label or section_id
end

local function section_order(ui, section_id)
  local defaults = section_defaults[section_id] or {}
  local order = normalize_number(section_setting(ui, section_id).order)
  return order or defaults.order or 100
end

local function section_limit(ui, section_id)
  local defaults = section_defaults[section_id] or {}
  local limit = normalize_number(section_setting(ui, section_id).limit)
  return limit or defaults.limit
end

local function build_state(ctx)
  local repo_ok = path_exists(oracle.config.repo_path, true)
  -- Live status belongs to the event/on-open controller. Keeping config-model
  -- construction in-process avoids blocking a reload on the Oracle Python/git
  -- snapshot; tests and callers may still inject one deterministic snapshot.
  local status = ctx and type(ctx.oracle_status_snapshot) == "table"
    and ctx.oracle_status_snapshot
    or {}
  local finish_line = get_field(status, "finish_line") or {}
  local focus = get_field(finish_line, "focus") or {}
  local version = parse_version_from_command(get_field(status, "commands.verify"))
    or parse_version_from_command(get_field(status, "commands.quick"))
    or (repo_ok and detect_rom_version(oracle.config.repo_path))
    or nil
  local rom_label = version and string.format("oos%dx.sfc", version) or nil
  local ui = ui_config(ctx)

  local yaze_action = ""
  local lyra_project_action = ""
  local lyra_project_label = "Edit Lyra Sea"
  local yaze_enabled = not (ctx and ctx.integration_flags and ctx.integration_flags.yaze == false)
  if yaze_enabled then
    local yaze_app, yaze_ok = locator.resolve_yaze_app(ctx or {})
    local yaze_launcher, yaze_launcher_ok = locator.resolve_yaze_launcher()
    if yaze_ok and yaze_app then
      yaze_action = open_app_action(yaze_app)
    elseif yaze_launcher_ok and yaze_launcher then
      yaze_action = binary_action(yaze_launcher)
    end
    -- Opens the working project on the first Lyra Sea map ($A0 = 160).
    local lyra_project = (ctx and type(ctx.paths) == "table" and ctx.paths.lyra_project)
      or oracle.config.lyra_project
    local project_launcher = oracle.config.project_launcher
    if ctx and type(ctx.paths) == "table" and ctx.paths.oracle_project_launcher ~= nil then
      project_launcher = ctx.paths.oracle_project_launcher
    end
    if project_launcher ~= nil and project_launcher ~= "" then
      lyra_project_label = "Edit Oracle Project"
      if type(project_launcher) == "string" and path_is_executable(project_launcher) then
        lyra_project_action = string.format(
          "(%s >/tmp/oos-open-oracle.log 2>&1 &)", bash_literal(project_launcher))
      end
    elseif yaze_ok and yaze_app and path_exists(lyra_project, false) then
      lyra_project_action = string.format(
        "open -n -a %s --args --rom_file=%s --editor=Overworld --map=160 --startup_welcome=hide --startup_dashboard=hide",
        shell_quote(yaze_app), shell_quote(lyra_project))
    end
  end

  -- The Dock app, the same bundle the play window and Dev builds open
  -- (Oracle Scripts/Mesen2/mesen2_launch_instance.sh default). mesen-run is
  -- the fallback; SketchyBar's PATH often lacks the dotfiles bin.
  local mesen_action = ""
  local mesen_app = (ctx and type(ctx.paths) == "table" and ctx.paths.mesen_app)
    or os.getenv("BARISTA_MESEN_APP")
    or state_paths.mesen_app
    or "/Applications/Mesen2 OOS.app"
  if path_exists(mesen_app, true) then
    mesen_action = open_app_action(mesen_app)
  else
    local mesen_run_bin, mesen_run_ok = locator.resolve_mesen_run(ctx or {})
    if mesen_run_ok and mesen_run_bin then
      mesen_action = binary_action(mesen_run_bin)
    end
  end

  local z3ed_action = ""
  local z3ed_launcher, z3ed_ok = locator.resolve_z3ed_launcher(ctx or {})
  if z3ed_ok and z3ed_launcher then
    local yaze_dir = select(1, locator.resolve_yaze_dir(ctx or {})) or (CODE_DIR .. "/hobby/yaze")
    local command = string.format(
      "cd %s && clear && printf 'z3ed\\n\\n' && %s --help; printf '\\n'; exec /bin/zsh -l",
      shell_quote(yaze_dir),
      shell_quote(z3ed_launcher)
    )
    z3ed_action = terminal_action(command, ctx)
  end
  -- Launches run in the background so the popup closes at once; each channel
  -- logs to /tmp/oos-launch-<channel>.log.
  local function launch_action(channel)
    return repo_action(string.format(
      "nohup ./Scripts/Build/oos-triforce.sh launch %s >/tmp/oos-launch-%s.log 2>&1 &",
      channel,
      channel
    ))
  end
  -- The user's Mesen play window (Oracle Scripts/Mesen2/oos_play.py, instance
  -- oos-rc-play): open it on the latest staged playtest build, or offer /
  -- load that build into the open window. Logs to /tmp/oos-play.log.
  local function play_window_action(flag)
    return repo_action(string.format(
      "nohup python3 ./Scripts/Mesen2/oos_play.py %s>/tmp/oos-play.log 2>&1 &",
      flag ~= "" and (flag .. " ") or ""
    ))
  end
  local ganondorf_action = ""
  local ganondorf_launcher = locator.expand_path(oracle.config.ganondorf_launcher)
  local launcher_executable = ganondorf_launcher and path_exists(ganondorf_launcher)
    and os.execute("test -x " .. bash_literal(ganondorf_launcher))
  if launcher_executable == true or launcher_executable == 0 then
    local controller = (ctx and ctx.CONFIG_DIR or locator.resolve_config_dir()) .. "/plugins/oracle_triforce.sh"
    ganondorf_action = "bash -lc " .. bash_literal(string.format(
      "nohup env BARISTA_GANONDORF_LAUNCHER=%s %s launch_ganondorf >/tmp/oos-launch-ganondorf.log 2>&1 &",
      bash_literal(ganondorf_launcher),
      bash_literal(controller)
    ))
  end
  local density = current_density(ctx and ctx.state or {})
  local widget_icon = ui.triforce.icon
  if widget_icon == "" then
    widget_icon = ctx and ctx.icon_for and ctx.icon_for("triforce", "󰯙") or "󰯙"
  end
  local menu_title = ui.triforce.title
  if menu_title == "" then
    menu_title = "Oracle of Secrets"
  end
  local widget_label = ui.triforce.label
  if widget_label == "" then
    widget_label = finish_line.status_line or focus.label or "Oracle"
  end

  return {
    repo_ok = repo_ok,
    ui = ui,
    yaze_action = yaze_action,
    lyra_project_action = lyra_project_action,
    lyra_project_label = lyra_project_label,
    mesen_action = mesen_action,
    z3ed_action = z3ed_action,
    play_window_action = play_window_action(""),
    play_now_action = play_window_action("--now"),
    launch_test_action = launch_action("test"),
    ganondorf_action = ganondorf_action,
    menu_title = menu_title,
    rom_label = rom_label,
    dev_label = dev_build_label(repo_ok and detect_dev_build(oracle.config.repo_path) or nil),
    show_label = ui.triforce.show_label,
    widget_label = widget_label,
    widget_label_override = ui.triforce.label,
    widget_icon = widget_icon,
    alerts_level = finish_line.alerts_level or "warn",
    density = density,
    triforce_widget = oracle.config.triforce_widget,
    status_script = oracle.config.status_script,
  }
end

local function make_entry(id, label, icon, action, opts)
  opts = opts or {}
  return {
    id = sanitize_id(id or label, label or "entry"),
    label = label or "Item",
    icon = icon or "",
    icon_color = opts.icon_color,
    label_color = opts.label_color,
    action = action or "",
    prominent = opts.prominent == true,
  }
end

local function take_entries(entries, limit)
  local result = {}
  local max_items = limit or #entries
  for index, entry in ipairs(entries or {}) do
    if index > max_items then
      break
    end
    table.insert(result, entry)
  end
  return result
end

-- opts.extension_items: interface extensions on the "triforce" surface; they
-- join the Apps section after the built-in rows.
function oracle.build_menu_model(ctx, opts)
  opts = opts or {}
  local state = build_state(ctx)
  local ui = state.ui

  local function add_section(model_sections, section_id, entries)
    if not section_enabled(ui, section_id) then
      return
    end
    entries = take_entries(entries or {}, section_limit(ui, section_id))
    if #entries == 0 then
      return
    end
    table.insert(model_sections, {
      id = section_id,
      label = section_label(ui, section_id),
      order = section_order(ui, section_id),
      color = theme_color(ctx, section_defaults[section_id].color_key, "WHITE"),
      icon = section_defaults[section_id].icon or "",
      presentation = section_defaults[section_id].presentation or "submenu",
      entries = entries,
    })
  end

  local sections = {}

  -- Play = the staged playtest build in the play window (shared save).
  -- Dev = the newest Roms/TestBuilds build in its own instance
  -- (oos-<user>-test), so it never touches the play save. The old "stable"
  -- row opened Roms/oos168x.sfc, which nothing rebuilds any more.
  local play_entries = {
    -- Icon + label filled by plugins/oracle_triforce.sh from
    -- `oos_play.py --status --json` (icon = window state, label = build).
    make_entry("play_status", "—", "󰍹", ""),
    make_entry("play_latest", "Play", "󰐊", state.play_window_action, { prominent = true }),
    make_entry("play_now", "Load now", "󰑐", state.play_now_action),
    -- Label refreshed by plugins/oracle_triforce.sh when the popup opens.
    make_entry("launch_test", state.dev_label, "󰙨", state.launch_test_action, { prominent = true }),
  }
  if state.ganondorf_action ~= "" then
    table.insert(play_entries, make_entry("launch_ganondorf", "Ganondorf test", "󰙨", state.ganondorf_action, { prominent = true }))
  end
  add_section(sections, "play", play_entries)

  local app_entries = {}
  if state.lyra_project_action ~= "" then
    table.insert(app_entries, make_entry("lyra_project", state.lyra_project_label, "󰯙", state.lyra_project_action, {
      icon_color = theme_color(ctx, "BLUE"),
      prominent = true,
    }))
  end
  if state.yaze_action ~= "" then
    table.insert(app_entries, make_entry("yaze", "Yaze", "󰯙", state.yaze_action, {
      icon_color = theme_color(ctx, "YELLOW"),
    }))
  end
  if state.z3ed_action ~= "" then
    table.insert(app_entries, make_entry("z3ed", "z3ed", "", state.z3ed_action, {
      icon_color = theme_color(ctx, "SKY"),
    }))
  end
  if state.mesen_action ~= "" then
    table.insert(app_entries, make_entry("mesen_oos", "Mesen2 OoS", "󰁆", state.mesen_action, {
      icon_color = theme_color(ctx, "RED"),
    }))
  end
  for _, item in ipairs(opts.extension_items or {}) do
    if item.available ~= false and (item.action or "") ~= "" then
      table.insert(app_entries, make_entry(item.id, item.label, item.icon, item.action, {
        icon_color = item.icon_color,
        label_color = item.label_color,
      }))
    end
  end
  add_section(sections, "apps", app_entries)

  table.sort(sections, function(a, b)
    if a.order == b.order then
      return a.id < b.id
    end
    return a.order < b.order
  end)

  return {
    title = state.menu_title,
    state = state,
    sections = sections,
  }
end

local function flatten_model(model, include_header)
  local items = {}

  if include_header then
    table.insert(items, {
      type = "header",
      name = "oracle.header",
      label = model.title or "Oracle",
    })
  end

  local first = true
  for _, section in ipairs(model.sections or {}) do
    if not first then
      table.insert(items, {
        type = "separator",
        name = "oracle.sep." .. section.id,
      })
    end
    first = false

    table.insert(items, {
      type = "header",
      name = "oracle." .. section.id .. ".header",
      label = section.label,
    })

    for _, entry in ipairs(section.entries or {}) do
      if entry.type == "header" then
        table.insert(items, {
          type = "header",
          name = "oracle." .. section.id .. "." .. entry.id,
          label = entry.label,
        })
      elseif entry.type == "separator" then
        table.insert(items, {
          type = "separator",
          name = "oracle." .. section.id .. "." .. entry.id,
        })
      else
        table.insert(items, {
          type = "item",
          name = "oracle." .. section.id .. "." .. entry.id,
          icon = entry.icon,
          icon_color = entry.icon_color,
          label_color = entry.label_color,
          label = entry.label,
          action = entry.action,
        })
      end
    end
  end

  return items
end

local function append_popup_entries(items, ctx, parent_popup, name_prefix, section, style)
  local title_font = style.font_header or popup_font(ctx, "Bold", ctx and ctx.settings and ctx.settings.font and ctx.settings.font.sizes and ctx.settings.font.sizes.small or 11)
  local row_font = style.font_small or popup_font(ctx, "Semibold", ctx and ctx.settings and ctx.settings.font and ctx.settings.font.sizes and ctx.settings.font.sizes.small or 11)

  for _, entry in ipairs(section.entries or {}) do
    local base_name = name_prefix .. "." .. entry.id
    if entry.type == "header" then
      ui.header(items, parent_popup, base_name, entry.label, {
        style = style,
        font = title_font,
        color = section.color,
      })
    elseif entry.type == "separator" then
      ui.separator(items, parent_popup, base_name, {
        style = style,
        font = row_font,
      })
    else
      ui.row(items, parent_popup, base_name, {
        style = style,
        icon = { string = entry.icon, color = entry.icon_color or section.color },
        label = truncate_label(entry.label, 40),
        font = row_font,
        label_color = entry.label_color or style.label_color,
        action = entry.action,
        prominent = entry.prominent,
      })
    end
  end
end

local function popup_items_from_model(model, ctx)
  local items = {}
  local style = popup_style(ctx)
  local title_font = style.font_header or popup_font(ctx, "Bold", ctx and ctx.settings and ctx.settings.font and ctx.settings.font.sizes and ctx.settings.font.sizes.small or 11)
  local accent = finishline_color(model.state.alerts_level)

  ui.header(items, "triforce", "oracle.triforce.header", model.title or "Oracle Workflow", {
    style = style,
    icon = { string = model.state.widget_icon, color = accent },
    font = title_font,
    color = theme_color(ctx, "WHITE"),
  })

  local visible_sections = {}
  for _, section in ipairs(model.sections or {}) do
    if section.presentation == "direct" then
      table.insert(visible_sections, section)
    end
  end

  if #visible_sections > 0 then
    ui.separator(items, "triforce", "oracle.triforce.meta.sep", {
      style = style,
      font = style.font_small,
    })
  end

  for index, section in ipairs(visible_sections) do
    if index > 1 then
      ui.separator(items, "triforce", "oracle.triforce.sep." .. section.id, {
        style = style,
        font = style.font_small,
      })
    end
    ui.header(items, "triforce", "oracle.triforce." .. section.id .. ".header", section.label, {
      style = style,
      font = title_font,
      color = section.color,
    })
    append_popup_entries(items, ctx, "triforce", "oracle.triforce." .. section.id, section, style)
  end

  return items
end

function oracle.create_triforce_widget(opts)
  opts = opts or {}
  local ctx = opts.ctx or {}
  local model = opts.model or oracle.build_menu_model(ctx)
  local state = model.state
  if not state.repo_ok then
    return nil
  end

  local color = finishline_color(state.alerts_level)
  local popup_background = opts.popup_background or {
    drawing = true,
    color = "0xf01e1e2e",
    corner_radius = 8,
    border_width = 2,
    border_color = "0xffcdd6f4",
    padding_left = 8,
    padding_right = 8,
  }
  popup_background.drawing = popup_background.drawing ~= false

  local item = {
    name = "triforce",
    position = opts.position or "left",
    icon = {
      string = state.widget_icon,
      font = opts.icon_font or { family = "Symbols Nerd Font", size = 14 },
      color = color,
      padding_left = 6,
      padding_right = 4,
    },
    label = {
      string = state.show_label and truncate_label(state.widget_label, 24) or "",
      drawing = state.show_label == true,
      font = popup_font(ctx, "Bold", 11) or { style = "Bold", size = 11 },
      color = color,
      padding_left = 2,
      padding_right = 6,
    },
    background = opts.background or {
      drawing = false,
      color = "0x00000000",
      corner_radius = 4,
      height = 22,
    },
    click_script = opts.popup_toggle_script or [[sketchybar -m --set $NAME popup.drawing=toggle]],
    popup = {
      align = "left",
      background = popup_background,
    },
  }

  if ctx.CONFIG_DIR then
    local controller_script = shell_quote(ctx.CONFIG_DIR .. "/plugins/oracle_triforce.sh")
    local controller_env = {}
    if path_is_executable(state.status_script) then
      table.insert(controller_env, "BARISTA_ORACLE_REPO_PATH=" .. shell_quote(oracle.config.repo_path))
      table.insert(controller_env, "BARISTA_ORACLE_STATUS_BIN=" .. shell_quote(state.status_script))
    end
    if path_is_executable(state.triforce_widget) then
      table.insert(controller_env, "BARISTA_TRIFORCE_WIDGET_BIN=" .. shell_quote(state.triforce_widget))
    end
    if state.widget_label_override ~= "" then
      table.insert(controller_env, "BARISTA_TRIFORCE_LABEL_OVERRIDE=" .. bash_literal(state.widget_label_override))
    end
    if ctx.SKETCHYBAR_BIN then
      table.insert(controller_env, "BARISTA_SKETCHYBAR_BIN=" .. shell_quote(ctx.SKETCHYBAR_BIN))
    end
    table.insert(controller_env, controller_script)
    item.script = table.concat(controller_env, " ")
  elseif path_is_executable(state.triforce_widget) then
    item.script = state.triforce_widget
  end

  if item.script and item.script ~= "" then
    local refresh_script = string.format(
      "SENDER=popup_refresh NAME=%s %s",
      shell_quote(item.name),
      item.script
    )
    local toggle_script = opts.popup_toggle_script
      or ui.toggle(item.name, {
        sketchybar_bin = ctx.SKETCHYBAR_BIN,
        popup_manager_script = ctx.popup_manager_script,
        popup_topology_token = ctx.popup_topology_token,
      })
    item.click_script = string.format(
      "%s; (%s) >/dev/null 2>&1 &",
      toggle_script,
      refresh_script
    )
  end

  return item
end

function oracle.create_triforce_popup_items(ctx)
  local model = ctx and ctx.oracle_menu_model or nil
  if not model then
    model = oracle.build_menu_model(ctx)
  end
  if not model.state.repo_ok then
    return {}
  end
  return popup_items_from_model(model, ctx)
end

function oracle.create_popup_items(ctx)
  return flatten_model(oracle.build_menu_model(ctx), true)
end

function oracle.create_menu_items(ctx)
  return flatten_model(oracle.build_menu_model(ctx), true)
end

function oracle.create_apple_menu_entry(ctx, opts)
  return nil
end

return oracle
