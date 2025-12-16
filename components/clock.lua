-- components/clock.lua

local M = {}

function M.setup(config)
  local sbar = config.sbar
  local theme = config.theme
  local settings = config.font
  local widget_factory = config.widget_factory
  local compiled_script = config.compiled_script
  local font_string = config.font_string
  local subscribe_popup_autoclose = config.subscribe_popup_autoclose
  local attach_hover = config.attach_hover
  local PLUGIN_DIR = config.paths.plugins

  widget_factory.create_clock({
    script = compiled_script("clock_widget", PLUGIN_DIR .. "/clock.sh"),
    update_freq = 1,
    click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
    popup = {
      align = "right",
      background = {
        border_width = 2,
        corner_radius = 6,
        border_color = theme.WHITE,
        color = theme.bar.bg,
        padding_left = 12,
        padding_right = 12,
        padding_top = 8,
        padding_bottom = 10
      }
    }
  })
  subscribe_popup_autoclose("clock")
  attach_hover("clock")

  -- Calendar popup items
  local calendar_items = {
    {
      name = "clock.calendar.header",
      icon = "",
      script = PLUGIN_DIR .. "/calendar.sh",
      update_freq = 1800,
      font_style = "Semibold",
      color = theme.LAVENDER,
      ["icon.font"] = font_string(config.font.icon, config.font.style_map["Bold"], config.font.sizes.small)
    },
    {
      name = "clock.calendar.weekdays",
      icon = "",
      font_style = "Bold",
      color = theme.DARK_WHITE
    },
  }

  for i = 1, 6 do
    table.insert(calendar_items, {
      name = string.format("clock.calendar.week%d", i),
      icon = "",
      font_style = "Regular",
      color = theme.WHITE
    })
  end

  table.insert(calendar_items, {
    name = "clock.calendar.summary",
    icon = "",
    font_style = "Semibold",
    color = theme.YELLOW
  })

  table.insert(calendar_items, {
    name = "clock.calendar.footer",
    icon = "",
    font_style = "Regular",
    color = theme.DARK_WHITE
  })

  for _, item in ipairs(calendar_items) do
    local is_header = item.name == "clock.calendar.header"
    local is_summary = item.name == "clock.calendar.summary"
    local is_footer = item.name == "clock.calendar.footer"

    local item_font = config.font.numbers
    if is_header or is_summary or is_footer then
      item_font = config.font.text
    end

    local opts = {
      position = "popup.clock",
      icon = item.icon or "",
      label = "",
      ["label.font"] = font_string(
        item_font,
        config.font.style_map[item.font_style or "Regular"] or config.font.style_map["Regular"],
        is_header and config.font.sizes.text or config.font.sizes.small
      ),
      ["label.color"] = item.color or theme.WHITE,
      ["icon.font"] = item["icon.font"] or font_string(config.font.icon, config.font.style_map["Bold"], config.font.sizes.small),
      ["icon.drawing"] = item.icon ~= "" and true or false,
      ["label.padding_left"] = 6,
      ["label.padding_right"] = 6,
      ["label.padding_top"] = (is_header or is_summary) and 4 or 1,
      ["label.padding_bottom"] = (is_footer or is_summary) and 4 or 1,
      background = { drawing = false },
    }
    if item.script then
      opts.script = item.script
    end
    if item.update_freq then
      opts.update_freq = item.update_freq
    end
    sbar.add("item", item.name, opts)
  end
end

return M
