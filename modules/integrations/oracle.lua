-- Oracle workflow integration for Barista.
-- The dedicated Triforce popup stays shallow and points deeper work at
-- Oracle Agent Manager plus a few high-signal session actions.

local oracle = {}

local locator = require("tool_locator")

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

local function close_after(command, popup_name)
  local popup = popup_name or "triforce"
  if not command or command == "" then
    return string.format("sketchybar -m --set %s popup.drawing=off", popup)
  end
  return string.format("%s; sketchybar -m --set %s popup.drawing=off", command, popup)
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

local function popup_item(name, props, parent_popup)
  local item = {
    name = name,
    position = "popup." .. (parent_popup or "triforce"),
    background = { drawing = false },
    ["icon.padding_left"] = 6,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 8,
    ["label.padding_right"] = 8,
  }
  for key, value in pairs(props or {}) do
    item[key] = value
  end
  return item
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
      "cd %s && ./scripts/oos-triforce.sh status-json --barista 2>/dev/null",
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
  elseif ctx and ctx.scripts and ctx.scripts.open_control_panel and ctx.call_script then
    panel_action = ctx.call_script(ctx.scripts.open_control_panel, "--oracle")
  end
  local continue_action = repo_action(focus.command or "./scripts/oos-session.sh maku --crystals 0")
  local patch_and_play_action = repo_action("./scripts/oos-triforce.sh patch-and-play")
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
  if state.panel_action ~= "" then
    table.insert(play_entries, make_entry("panel", "Open Oracle Hub", "󰒋", state.panel_action))
  end
  add_section(sections, "play", play_entries)

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

local function append_popup_entries(items, ctx, parent_popup, name_prefix, section)
  local title_font = popup_font(ctx, "Bold", ctx and ctx.settings and ctx.settings.font and ctx.settings.font.sizes and ctx.settings.font.sizes.small or 11)
  local row_font = popup_font(ctx, "Semibold", ctx and ctx.settings and ctx.settings.font and ctx.settings.font.sizes and ctx.settings.font.sizes.small or 11)

  for _, entry in ipairs(section.entries or {}) do
    local base_name = name_prefix .. "." .. entry.id
    if entry.type == "header" then
      table.insert(items, popup_item(base_name, {
        icon = { string = "", drawing = false },
        label = entry.label,
        ["label.font"] = title_font,
        ["label.color"] = section.color,
      }, parent_popup))
    elseif entry.type == "separator" then
      table.insert(items, popup_item(base_name, {
        icon = { string = "", drawing = false },
        label = "───────────────",
        ["label.font"] = row_font,
        ["label.color"] = theme_color(ctx, "SUBTEXT1", "WHITE"),
      }, parent_popup))
    else
      local background = { drawing = false }
      if entry.prominent then
        background = {
          drawing = true,
          color = "0x20343a58",
          corner_radius = 6,
        }
      end
      table.insert(items, popup_item(base_name, {
        icon = { string = entry.icon, color = entry.icon_color or section.color },
        label = truncate_label(entry.label, 40),
        ["label.font"] = row_font,
        click_script = close_after(entry.action, "triforce"),
        background = background,
        hover = true,
      }, parent_popup))
    end
  end
end

local function popup_items_from_model(model, ctx)
  local items = {}
  local title_font = popup_font(ctx, "Bold", ctx and ctx.settings and ctx.settings.font and ctx.settings.font.sizes and ctx.settings.font.sizes.small or 11)
  local accent = finishline_color(model.state.alerts_level)

  table.insert(items, popup_item("oracle.triforce.header", {
    icon = { string = model.state.widget_icon, color = accent },
    label = model.title or "Oracle Workflow",
    ["label.font"] = title_font,
    ["label.color"] = theme_color(ctx, "WHITE"),
  }, "triforce"))

  table.insert(items, popup_item("oracle.triforce.rom", {
    icon = { string = "󰍛", color = theme_color(ctx, "BLUE") },
    label = "ROM: " .. tostring(model.state.rom_label or "patched ROM"),
    ["label.font"] = title_font,
    ["label.color"] = theme_color(ctx, "SUBTEXT1", "WHITE"),
    background = { drawing = false },
  }, "triforce"))

  local direct_seen = false
  for _, section in ipairs(model.sections or {}) do
    if section.presentation == "direct" then
      if not direct_seen and #model.sections > 1 then
        table.insert(items, popup_item("oracle.triforce.direct.header", {
          icon = { string = "", drawing = false },
          label = section.label,
          ["label.font"] = title_font,
          ["label.color"] = section.color,
        }, "triforce"))
        direct_seen = true
      end
      append_popup_entries(items, ctx, "triforce", "oracle.triforce." .. section.id, section)
    end
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
    item.click_script = string.format("BARISTA_TRIFORCE_ACTION=click %s", item.script)
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
