local apple_menu = require("apple_menu_enhanced")

run_test("apple_menu_enhanced: apple menu stays click-only", function()
  local added = {}
  local subscribed = {}

  local meta = apple_menu.setup({
    sbar = {
      add = function(kind, name, props)
        table.insert(added, { kind = kind, name = name, props = props })
      end,
    },
    theme = {
      WHITE = "0xffffffff",
      DARK_WHITE = "0xffcccccc",
      BG_SEC_COLR = "0xff111111",
      bar = { bg = "0xff000000" },
    },
    widget_height = 22,
    associated_displays = "all",
    popup_anchor_script = "/tmp/popup_anchor",
    popup_toggle_action = function()
      return "toggle:apple_menu"
    end,
    subscribe_popup_autoclose = function(name)
      table.insert(subscribed, name)
    end,
    call_script = function(path, ...)
      local parts = { path }
      for _, arg in ipairs({ ... }) do
        table.insert(parts, tostring(arg))
      end
      return table.concat(parts, " ")
    end,
    apple_menu_prepared = {
      config_dir = "/tmp/config",
      style = {
        popup_border_width = 2,
        popup_corner_radius = 4,
        popup_border_color = "0xffffffff",
        popup_bg_color = "0xff111111",
        popup_padding = 8,
      },
      font_small = "Inter:Regular:12.0",
      font_bold = "Inter:Bold:12.0",
      popup_item_height = 20,
      popup_header_height = 22,
      popup_item_corner_radius = 4,
      popup_padding = {
        icon_left = 4,
        icon_right = 6,
        label_left = 6,
        label_right = 6,
      },
      hover_script_cmd = nil,
      rendered = {},
      sections = {},
    },
    icon_for = function(_, fallback)
      return fallback or ""
    end,
  })

  local apple_menu_item = nil
  for _, entry in ipairs(added) do
    if entry.name == "apple_menu" then
      apple_menu_item = entry
      break
    end
  end

  assert_true(apple_menu_item ~= nil, "apple_menu should be added")
  assert_equal(apple_menu_item.props.click_script, "toggle:apple_menu", "apple_menu should still toggle on click")
  assert_equal(apple_menu_item.props.script, "/tmp/popup_anchor", "apple_menu should use the popup anchor without hover-open env")
  assert_true(not apple_menu_item.props.script:find("POPUP_OPEN_ON_ENTER", 1, true), "apple_menu script should not enable hover-open")
  assert_equal(subscribed[1], "apple_menu", "apple_menu should still subscribe to popup autoclose")
  assert_type(meta, "table", "setup should return metadata")
end)
