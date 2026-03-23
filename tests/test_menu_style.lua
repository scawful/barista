local menu_style = require("menu_style")

local ctx = {
  theme = {
    WHITE = 0xffffffff,
    bar = { bg = "0xC021162F" },
  },
  settings = {
    font = {
      text = "Source Code Pro",
      style_map = {
        Regular = "Regular",
        Semibold = "Semibold",
        Bold = "Bold",
      },
      sizes = {
        small = 13,
      },
    },
  },
  appearance = {
    popup_padding = 8,
    popup_item_height = 0,
    menu_font_size_offset = 1,
    popup_item_corner_radius = 4,
    submenu_hover_color = "0x80cba6f7",
    submenu_idle_color = "0x00000000",
  },
  widget_height = 36,
}

run_test("menu_style.compute: menu rows stay decoupled from tall widget height", function()
  local style = menu_style.compute(ctx)
  assert_equal(style.item_height, 24, "menu rows should stay compact")
  assert_equal(style.header_height, 26, "header rows slightly taller")
end)

run_test("menu_style.compute: explicit menu sizing overrides defaults", function()
  local style = menu_style.compute({
    theme = ctx.theme,
    settings = ctx.settings,
    appearance = {
      menu_padding = 10,
      menu_item_height = 28,
      menu_header_height = 30,
      menu_item_corner_radius = 8,
      submenu_hover_corner_radius = 9,
      submenu_hover_padding_left = 6,
      submenu_hover_padding_right = 7,
    },
  })

  assert_equal(style.item_height, 28, "explicit menu height")
  assert_equal(style.header_height, 30, "explicit header height")
  assert_equal(style.item_corner_radius, 8, "explicit corner radius")
  assert_equal(style.submenu_hover_env.SUBMENU_HOVER_CORNER_RADIUS, "9", "submenu hover radius")
  assert_equal(style.submenu_hover_env.SUBMENU_HOVER_PADDING_LEFT, "6", "submenu hover padding left")
  assert_equal(style.submenu_hover_env.SUBMENU_HOVER_PADDING_RIGHT, "7", "submenu hover padding right")
end)
