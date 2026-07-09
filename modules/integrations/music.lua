-- Music/studio launcher integration for Barista.
-- Adds a shallow "studio" popup next to the Triforce menu for the apps and
-- folders that are useful while making songs.

local music = {}

local locator = require("tool_locator")
local ui = require("ui_builder")

local HOME = os.getenv("HOME") or ""
local DEFAULT_ITEM_NAME = "music_studio"
local MUSIC_ROOT = HOME .. "/Music"
local STUDIO_ROOT = MUSIC_ROOT .. "/Studio"

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

local function shell_quote(value)
  return string.format("%q", tostring(value or ""))
end

local function bash_literal(value)
  return "'" .. tostring(value or ""):gsub("'", "'\"'\"'") .. "'"
end

local function path_exists(path, want_dir)
  return locator.path_exists(path, want_dir)
end

local function open_path_action(path)
  if type(path) ~= "string" or path == "" then
    return ""
  end
  return "open " .. shell_quote(path)
end

local function terminal_action(command, ctx)
  if type(command) ~= "string" or command == "" then
    return ""
  end

  local function debounced_command(key, raw_command)
    local raw_key = tostring(key or "music"):gsub("[^%w]+", "_")
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
    return debounced_command(
      "music_terminal",
      string.format("open -na %s --args -e /bin/zsh -lc %s", shell_quote(ghostty_app), shell_quote(command))
    )
  end

  return string.format("osascript -e 'tell application \"Terminal\" to do script %q'", command)
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

local function ui_config(ctx)
  local menus = ctx and ctx.state and ctx.state.menus or {}
  local menu = type(menus.music) == "table" and menus.music or {}
  return {
    raw = menu,
    item_name = type(menu.item_name) == "string" and menu.item_name ~= "" and menu.item_name or DEFAULT_ITEM_NAME,
    title = type(menu.title) == "string" and menu.title ~= "" and menu.title or "Music Studio",
    label = type(menu.label) == "string" and menu.label or "",
    icon = type(menu.icon) == "string" and menu.icon ~= "" and menu.icon or "",
    show_label = normalize_bool(menu.show_label) == true,
    update_freq = normalize_number(menu.update_freq) or 300,
    app_paths = type(menu.app_paths) == "table" and menu.app_paths or {},
    items = type(menu.items) == "table" and menu.items or {},
  }
end

local function app_path_override(ctx, ui, id)
  if type(ui.app_paths[id]) == "string" and ui.app_paths[id] ~= "" then
    return ui.app_paths[id]
  end
  if ctx and type(ctx.paths) == "table" then
    local key = id .. "_app"
    if type(ctx.paths[key]) == "string" and ctx.paths[key] ~= "" then
      return ctx.paths[key]
    end
  end
  return nil
end

local function resolve_app(ctx, ui, spec)
  local candidates = {}
  table.insert(candidates, app_path_override(ctx, ui, spec.id))
  for _, candidate in ipairs(spec.candidates or {}) do
    table.insert(candidates, candidate)
  end
  local path, ok = locator.resolve_path(candidates, true)
  if ok and path and path ~= "" then
    return path
  end
  return nil
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

local app_specs = {
  {
    id = "yams",
    label = "yams",
    icon = "󰆼",
    color_key = "MAUVE",
    candidates = {
      HOME .. "/Applications/yams.app",
      "/Applications/yams.app",
    },
  },
  {
    id = "logic_pro",
    label = "Logic Pro",
    icon = "󰎈",
    color_key = "PEACH",
    candidates = {
      "/Applications/Logic Pro.app",
      HOME .. "/Applications/Logic Pro.app",
      "/Applications/Logic Pro X.app",
      HOME .. "/Applications/Logic Pro X.app",
    },
  },
  {
    id = "roland_cloud_manager",
    label = "Roland Cloud Manager",
    icon = "󰀻",
    color_key = "SAPPHIRE",
    candidates = {
      "/Applications/Roland Cloud Manager.app",
      HOME .. "/Applications/Roland Cloud Manager.app",
    },
  },
  {
    id = "sp404_mkii",
    label = "SP-404MKII App",
    icon = "󰟴",
    color_key = "RED",
    candidates = {
      "/Applications/Roland/SP-404MKII.app",
      "/Applications/SP-404MKII.app",
      HOME .. "/Applications/SP-404MKII.app",
    },
  },
  {
    id = "ableton_live",
    label = "Ableton Live",
    icon = "󰓃",
    color_key = "GREEN",
    candidates = {
      "/Applications/Ableton Live 12 Lite.app",
      "/Applications/Ableton Live 12 Suite.app",
      "/Applications/Ableton Live 12 Standard.app",
      "/Applications/Ableton Live 11 Lite.app",
      HOME .. "/Applications/Ableton Live 12 Lite.app",
    },
  },
  {
    id = "garageband",
    label = "GarageBand",
    icon = "󰋋",
    color_key = "YELLOW",
    candidates = {
      "/Applications/GarageBand.app",
      HOME .. "/Applications/GarageBand.app",
    },
  },
  {
    id = "serato_dj_pro",
    label = "Serato DJ Pro",
    icon = "󰲸",
    color_key = "MAUVE",
    candidates = {
      "/Applications/Serato DJ Pro.app",
      HOME .. "/Applications/Serato DJ Pro.app",
    },
  },
  {
    id = "mpc_beats",
    label = "MPC Beats",
    icon = "󰑊",
    color_key = "TEAL",
    candidates = {
      "/Applications/MPC Beats.app",
      HOME .. "/Applications/MPC Beats.app",
    },
  },
  {
    id = "audio_midi_setup",
    label = "Audio MIDI Setup",
    icon = "󰋋",
    color_key = "SKY",
    candidates = {
      "/System/Applications/Utilities/Audio MIDI Setup.app",
      "/Applications/Utilities/Audio MIDI Setup.app",
    },
  },
}

local function custom_entries(ctx, ui)
  local entries = {}
  for _, item in ipairs(ui.items or {}) do
    if type(item) == "table" and normalize_bool(item.enabled) ~= false then
      local action = item.action
      if (not action or action == "") and type(item.path) == "string" and item.path ~= "" then
        local expanded = locator.expand_path(item.path) or item.path
        if path_exists(expanded, item.want_dir ~= false) then
          action = open_path_action(expanded)
        end
      end
      if action and action ~= "" then
        table.insert(entries, make_entry(
          item.id or item.label,
          item.label or item.id,
          item.icon or "󰐕",
          action,
          { icon_color = item.icon_color or theme_color(ctx, "TEAL") }
        ))
      end
    end
  end
  return entries
end

function music.build_menu_model(ctx)
  local ui = ui_config(ctx)
  local sections = {}
  local app_entries = {}

  for _, spec in ipairs(app_specs) do
    local path = resolve_app(ctx, ui, spec)
    if path then
      table.insert(app_entries, make_entry(spec.id, spec.label, spec.icon, open_path_action(path), {
        icon_color = theme_color(ctx, spec.color_key, "WHITE"),
      }))
    end
  end

  if #app_entries > 0 then
    table.insert(sections, {
      id = "apps",
      label = "Apps",
      color = theme_color(ctx, "SAPPHIRE", "WHITE"),
      entries = app_entries,
    })
  end

  local workflow_entries = {}
  local studio_cli = STUDIO_ROOT .. "/Tools/studio/bin/studio"
  if locator.path_is_executable(studio_cli) then
    table.insert(workflow_entries, make_entry(
      "studio_start",
      "Studio Start",
      "󰐊",
      terminal_action("cd ~/Music && Studio/Tools/studio/bin/studio start", ctx),
      { icon_color = theme_color(ctx, "GREEN"), prominent = true }
    ))
    table.insert(workflow_entries, make_entry(
      "studio_devices",
      "Plugged In",
      "󰒋",
      terminal_action("cd ~/Music && Studio/Tools/studio/bin/studio devices", ctx),
      { icon_color = theme_color(ctx, "SAPPHIRE") }
    ))
  end

  local songforge = STUDIO_ROOT .. "/Songs/songforge/bin/songforge"
  if locator.path_is_executable(songforge) then
    table.insert(workflow_entries, make_entry(
      "songforge_tui",
      "SongForge Board",
      "󰓎",
      terminal_action("cd ~/Music && Studio/Songs/songforge/bin/songforge tui", ctx),
      { icon_color = theme_color(ctx, "TEAL") }
    ))
  end

  local guides = HOME .. "/Documents/Music/Guides"
  if path_exists(guides, true) then
    table.insert(workflow_entries, make_entry(
      "music_guides",
      "PDF Guides",
      "󰈙",
      open_path_action(guides),
      { icon_color = theme_color(ctx, "YELLOW") }
    ))
  end

  local muzak = HOME .. "/Documents/Music/Projects/Muzak"
  if path_exists(muzak, true) then
    table.insert(workflow_entries, make_entry(
      "muzak_bounces",
      "Muzak Bounces",
      "󰝚",
      open_path_action(muzak),
      { icon_color = theme_color(ctx, "MAUVE", "LAVENDER") }
    ))
  end

  for _, entry in ipairs(custom_entries(ctx, ui)) do
    table.insert(workflow_entries, entry)
  end

  if #workflow_entries > 0 then
    table.insert(sections, {
      id = "workflow",
      label = "Workflow",
      color = theme_color(ctx, "GREEN", "WHITE"),
      entries = workflow_entries,
    })
  end

  local kit_entries = {}
  local kit_paths = {
    { id = "samples", label = "Samples", icon = "󰉋", path = MUSIC_ROOT .. "/Samples", color = "SAPPHIRE" },
    { id = "opxy_wavetables", label = "OP-XY Wavetables", icon = "󰝚", path = MUSIC_ROOT .. "/Samples/OP-XY/Wavetables Starter 01", color = "MAUVE" },
    { id = "sp404_wavetables", label = "SP-404 Wavetables", icon = "󰟴", path = MUSIC_ROOT .. "/Samples/SP-404/Wavetables Starter 01", color = "RED" },
    { id = "song_pdfs", label = "Song PDFs", icon = "󰈙", path = MUSIC_ROOT .. "/PDFs/Song PDFs", color = "YELLOW" },
  }
  for _, spec in ipairs(kit_paths) do
    if path_exists(spec.path, true) then
      table.insert(kit_entries, make_entry(spec.id, spec.label, spec.icon, open_path_action(spec.path), {
        icon_color = theme_color(ctx, spec.color, "WHITE"),
      }))
    end
  end
  if #kit_entries > 0 then
    table.insert(sections, {
      id = "kits",
      label = "Kits + Folders",
      color = theme_color(ctx, "MAUVE", "WHITE"),
      entries = kit_entries,
    })
  end

  return {
    title = ui.title,
    ui = ui,
    sections = sections,
  }
end

function music.get_item_name(ctx)
  return ui_config(ctx).item_name
end

function music.create_widget(opts)
  opts = opts or {}
  local ctx = opts.ctx or {}
  local model = opts.model or music.build_menu_model(ctx)
  local ui = model.ui or ui_config(ctx)
  local icon = ui.icon
  if icon == "" then
    icon = ctx and ctx.icon_for and ctx.icon_for("music", "󰝚") or "󰝚"
  end
  local accent = theme_color(ctx, "MAUVE", "WHITE")

  local item = {
    name = ui.item_name or DEFAULT_ITEM_NAME,
    position = opts.position or "left",
    icon = {
      string = icon,
      font = opts.icon_font or { family = "Symbols Nerd Font", size = 14 },
      color = accent,
      padding_left = 6,
      padding_right = 4,
    },
    label = {
      string = ui.show_label and truncate_label(ui.label ~= "" and ui.label or ui.title, 24) or "",
      drawing = ui.show_label == true,
      font = popup_font(ctx, "Bold", 11) or { style = "Bold", size = 11 },
      color = accent,
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
      background = opts.popup_background or {
        drawing = true,
        color = "0xf01e1e2e",
        corner_radius = 8,
        border_width = 2,
        border_color = "0xffcdd6f4",
        padding_left = 8,
        padding_right = 8,
      },
    },
    update_freq = false,
    updates = false,
  }

  if ctx.CONFIG_DIR then
    local controller_script = shell_quote(ctx.CONFIG_DIR .. "/plugins/music_studio.sh")
    item.script = controller_script
  end

  return item
end

function music.create_popup_items(ctx)
  local model = ctx and ctx.music_menu_model or nil
  if not model then
    model = music.build_menu_model(ctx)
  end

  local items = {}
  local style = popup_style(ctx)
  local title_font = style.font_header or popup_font(ctx, "Bold", ctx and ctx.settings and ctx.settings.font and ctx.settings.font.sizes and ctx.settings.font.sizes.small or 11)
  local row_font = style.font_small or popup_font(ctx, "Semibold", ctx and ctx.settings and ctx.settings.font and ctx.settings.font.sizes and ctx.settings.font.sizes.small or 11)
  local parent_popup = (model.ui and model.ui.item_name) or DEFAULT_ITEM_NAME

  ui.header(items, parent_popup, "music.studio.header", model.title or "Music Studio", {
    style = style,
    icon = { string = (model.ui and model.ui.icon ~= "" and model.ui.icon) or "󰝚", color = theme_color(ctx, "MAUVE", "WHITE") },
    font = title_font,
    color = theme_color(ctx, "WHITE"),
  })

  for section_index, section in ipairs(model.sections or {}) do
    if section_index > 1 then
      ui.separator(items, parent_popup, "music.studio.sep." .. section.id, {
        style = style,
        font = row_font,
      })
    end

    ui.header(items, parent_popup, "music.studio." .. section.id .. ".header", section.label, {
      style = style,
      font = title_font,
      color = section.color,
    })

    for _, entry in ipairs(section.entries or {}) do
      ui.row(items, parent_popup, "music.studio." .. section.id .. "." .. entry.id, {
        style = style,
        icon = { string = entry.icon, color = entry.icon_color or section.color },
        label = truncate_label(entry.label, 42),
        font = row_font,
        label_color = entry.label_color or style.label_color,
        action = entry.action,
        prominent = entry.prominent,
      })
    end
  end

  return items
end

return music
