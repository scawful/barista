-- Oracle workflow integration for Barista.
-- The dedicated Triforce popup stays shallow and points deeper work at
-- Oracle Agent Manager plus a few high-signal session actions.

local oracle = {}

local locator = require("tool_locator")
local ui = require("ui_builder")

local json_ok, json = pcall(require, "json")

local HOME = os.getenv("HOME")
local CODE_DIR = os.getenv("BARISTA_CODE_DIR") or (HOME .. "/src")
local DOTFILES_DIR = CODE_DIR .. "/config/dotfiles"
local ORACLE_DIR = CODE_DIR .. "/hobby/oracle-of-secrets"

oracle.config = {
  repo_path = ORACLE_DIR,
  z3dk_repo = CODE_DIR .. "/hobby/z3dk",
  workbench = DOTFILES_DIR .. "/bin/oos-workbench",
  legacy_workbench = DOTFILES_DIR .. "/bin/oos-cockpit",
  triforce_widget = DOTFILES_DIR .. "/bin/oos-triforce-widget",
  handoff = ORACLE_DIR .. "/.context/scratchpad/agent_handoff.md",
  tracker = ORACLE_DIR .. "/oracle.org",
  workflow_plan = ORACLE_DIR .. "/Docs/Planning/Plans/development_workflow_alignment_2026-03-28.md",
  runbook = ORACLE_DIR .. "/RUNBOOK.md",
}

local section_defaults = {
  play = { label = "Oracle Session", order = 10, color_key = "GREEN", enabled = true, limit = 5, icon = "󰐃", presentation = "direct" },
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

local function workbench_path()
  if path_is_executable(oracle.config.workbench) then
    return oracle.config.workbench
  end
  if path_is_executable(oracle.config.legacy_workbench) then
    return oracle.config.legacy_workbench
  end
  return nil
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

local function finishline_color(level)
  local colors = {
    ok = "0xffa6e3a1",
    warn = "0xfff9e2af",
    error = "0xfff38ba8",
  }
  return colors[level] or "0xff89b4fa"
end

local function read_status_snapshot(ctx)
  if ctx and type(ctx.oracle_status_snapshot) == "table" then
    return ctx.oracle_status_snapshot
  end
  if not json_ok then
    return nil
  end

  local bin = workbench_path()
  local command
  if bin then
    command = string.format("%s status-json --barista 2>/dev/null", shell_quote(bin))
  elseif path_exists(oracle.config.repo_path, true) then
    command = string.format(
      "cd %s && ./Scripts/Build/oos-triforce.sh status-json --barista 2>/dev/null",
      shell_quote(oracle.config.repo_path)
    )
  end

  if not command then
    return nil
  end

  local handle = io.popen(command)
  if not handle then
    return nil
  end
  local payload = handle:read("*a") or ""
  handle:close()
  if payload == "" then
    return nil
  end

  local ok, decoded = pcall(json.decode, payload)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
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
      update_freq = normalize_number(triforce.update_freq) or 45,
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
  local status = read_status_snapshot(ctx) or {}
  local finish_line = get_field(status, "finish_line") or {}
  local focus = get_field(finish_line, "focus") or {}
  local version = parse_version_from_command(get_field(status, "commands.verify"))
    or parse_version_from_command(get_field(status, "commands.quick"))
  local rom_label = version and string.format("oos%dx.sfc", version) or "patched ROM"
  local ui = ui_config(ctx)

  local panel_action = ""
  if ctx and ctx.scripts and ctx.scripts.open_oracle_agent_manager and ctx.call_script then
    panel_action = ctx.call_script(ctx.scripts.open_oracle_agent_manager)
  else
    local oam_bin, oam_ok = locator.resolve_oracle_agent_manager(ctx or {})
    if oam_ok and oam_bin then
      panel_action = binary_action(oam_bin)
    end
  end
  if panel_action == "" and ctx and ctx.scripts and ctx.scripts.open_control_panel and ctx.call_script then
    panel_action = ctx.call_script(ctx.scripts.open_control_panel, "--oracle")
  end

  local yaze_action = ""
  local yaze_enabled = not (ctx and ctx.integration_flags and ctx.integration_flags.yaze == false)
  if yaze_enabled then
    local yaze_app, yaze_ok = locator.resolve_yaze_app(ctx or {})
    local yaze_launcher, yaze_launcher_ok = locator.resolve_yaze_launcher()
    if yaze_ok and yaze_app then
      yaze_action = open_app_action(yaze_app)
    elseif yaze_launcher_ok and yaze_launcher then
      yaze_action = binary_action(yaze_launcher)
    end
  end

  local mesen_action = ""
  local mesen_run_bin, mesen_run_ok = locator.resolve_mesen_run(ctx or {})
  if mesen_run_ok and mesen_run_bin then
    mesen_action = binary_action(mesen_run_bin)
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
  local continue_action = repo_action(focus.command or "./Scripts/Build/oos-session.sh maku --crystals 0")
  local patch_and_play_action = repo_action("./Scripts/Build/oos-triforce.sh patch-and-play")
  local density = current_density(ctx and ctx.state or {})
  local widget_icon = ui.triforce.icon
  if widget_icon == "" then
    widget_icon = ctx and ctx.icon_for and ctx.icon_for("triforce", "󰯙") or "󰯙"
  end
  local menu_title = ui.triforce.title
  if menu_title == "" then
    menu_title = "Oracle Hub"
  end
  local widget_label = ui.triforce.label
  if widget_label == "" then
    widget_label = finish_line.status_line or focus.label or "Oracle"
  end

  return {
    repo_ok = repo_ok,
    ui = ui,
    panel_action = panel_action,
    yaze_action = yaze_action,
    mesen_action = mesen_action,
    z3ed_action = z3ed_action,
    continue_action = continue_action,
    patch_and_play_action = patch_and_play_action,
    menu_title = menu_title,
    rom_label = rom_label,
    show_label = ui.triforce.show_label,
    widget_label = widget_label,
    widget_icon = widget_icon,
    update_freq = math.max(5, ui.triforce.update_freq),
    alerts_level = finish_line.alerts_level or "warn",
    focus_label = focus.label or "",
    focus_title = focus.title or "",
    density = density,
    triforce_widget = oracle.config.triforce_widget,
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

function oracle.build_menu_model(ctx)
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

  local continue_label = "Continue Session"
  if state.focus_title ~= "" then
    continue_label = "Continue: " .. tostring(state.focus_title):gsub("^Play%s+", "")
  elseif state.focus_label ~= "" then
    continue_label = "Continue: " .. state.focus_label
  end
  local play_entries = {
    make_entry("continue", continue_label, "󰐃", state.continue_action, { prominent = true }),
    make_entry("patch_continue", "Patch + Launch", "󰑐", state.patch_and_play_action),
  }
  add_section(sections, "play", play_entries)

  local app_entries = {}
  if state.panel_action ~= "" then
    table.insert(app_entries, make_entry("oracle_hub", "Oracle Hub", "󰒋", state.panel_action, {
      icon_color = theme_color(ctx, "MAGENTA", "MAUVE"),
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

  ui.row(items, "triforce", "oracle.triforce.rom", {
    style = style,
    icon = { string = "󰍛", color = theme_color(ctx, "BLUE") },
    label = "ROM: " .. tostring(model.state.rom_label or "patched ROM"),
    font = style.font_small or title_font,
    label_color = theme_color(ctx, "SUBTEXT1", "WHITE"),
    hover = false,
  })

  local focus_label = model.state.focus_title ~= "" and model.state.focus_title
    or model.state.focus_label
    or ""
  if focus_label ~= "" then
    focus_label = tostring(focus_label):gsub("^Play%s+", "")
    ui.row(items, "triforce", "oracle.triforce.focus", {
      style = style,
      icon = { string = "󰐃", color = theme_color(ctx, "GREEN") },
      label = "Focus: " .. truncate_label(focus_label, 34),
      font = style.font_small or title_font,
      label_color = theme_color(ctx, "SUBTEXT1", "WHITE"),
      hover = false,
    })
  end

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
    update_freq = state.update_freq,
  }

  if ctx.CONFIG_DIR then
    local controller_script = shell_quote(ctx.CONFIG_DIR .. "/plugins/oracle_triforce.sh")
    if path_is_executable(state.triforce_widget) then
      item.script = string.format(
        "BARISTA_TRIFORCE_WIDGET_BIN=%s %s",
        shell_quote(state.triforce_widget),
        controller_script
      )
    else
      item.script = controller_script
    end
  elseif path_is_executable(state.triforce_widget) then
    item.script = state.triforce_widget
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
