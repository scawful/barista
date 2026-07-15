local ui = require("ui_builder")

run_test("ui_builder: popup toggles and async refresh scripts", function()
  assert_equal(
    ui.toggle("volume"),
    "sketchybar -m --set volume popup.drawing=toggle",
    "named toggle should be a direct SketchyBar popup toggle"
  )
  assert_equal(
    ui.toggle(),
    [[USER="${USER:-$(id -un)}" sketchybar -m --set "$NAME" popup.drawing=toggle]],
    "anonymous toggle should target $NAME directly"
  )
  assert_equal(
    ui.toggle_then_refresh_async("clock", "/tmp/calendar.sh"),
    "sketchybar -m --set clock popup.drawing=toggle; (/tmp/calendar.sh) >/dev/null 2>&1 &",
    "async refresh should run after the immediate toggle"
  )
end)

run_test("ui_builder: close-after actions", function()
  assert_equal(
    ui.close_after("triforce", "open /Applications/Yaze.app"),
    "open /Applications/Yaze.app; sketchybar -m --set triforce popup.drawing=off",
    "close_after should execute the action then close the parent popup"
  )
  assert_equal(
    ui.close_after("triforce", ""),
    "sketchybar -m --set triforce popup.drawing=off",
    "empty close_after should only close the parent popup"
  )
end)

run_test("ui_builder: anchor layout entries", function()
  local layout = {}
  ui.anchor(layout, {
    ctx = { POST_CONFIG_DELAY = 0.2, SKETCHYBAR_BIN = "sketchybar" },
    name = "front_app",
    props = { position = "left" },
    events = { "front_app_switched" },
    associated_display = "all",
    associated_space = "all",
  })

  assert_equal(layout[1].type, "item", "anchor should add the item first")
  assert_equal(layout[1].name, "front_app", "anchor item should keep the requested name")
  assert_equal(layout[2].action, "exec", "anchor should add event subscription")
  assert_true(layout[2].cmd:find("--subscribe front_app front_app_switched", 1, true) ~= nil, "anchor should subscribe requested events")
  assert_equal(layout[3].action, "subscribe_popup_autoclose", "anchor should register popup dismissal")
  assert_equal(layout[4].action, "attach_hover", "anchor should register hover feedback")
  assert_true(layout[5].cmd:find("--set front_app associated_display=all associated_space=all", 1, true) ~= nil, "anchor should apply association")
end)

run_test("ui_builder: anchor chip style and hover env", function()
  local ctx = {
    widget_height = 24,
    widget_corner_radius = 6,
    hover_border_color = "0x60111111",
    hover_border_width = 2,
    env_prefix = function(vars)
      return string.format(
        "IDLE=%s HOVER=%s BORDER=%s ",
        vars.BARISTA_ANCHOR_IDLE_BG,
        vars.BARISTA_ANCHOR_HOVER_BG,
        vars.BARISTA_ANCHOR_HOVER_BORDER_WIDTH
      )
    end,
  }
  local chip = ui.anchor_chip_style(ctx)
  assert_equal(chip.drawing, true, "anchor chip should draw by default")
  assert_equal(chip.color, "0x18313a46", "anchor chip should use shared idle color")
  assert_equal(chip.corner_radius, 10, "anchor chip should use pill radius")
  assert_equal(chip.height, 24, "anchor chip should use widget height")

  local env = ui.anchor_hover_env(ctx)
  assert_equal(env.BARISTA_ANCHOR_IDLE_DRAWING, "on", "hover env should preserve idle drawing")
  assert_equal(env.BARISTA_ANCHOR_HOVER_BORDER_WIDTH, "2", "hover env should pass border width")
  assert_equal(env.BARISTA_ANCHOR_HOVER_BORDER_COLOR, "0x60111111", "hover env should pass border color")
  assert_equal(ui.anchor_script("/tmp/plugin.sh", ctx), "IDLE=0x18313a46 HOVER=0x28505a6a BORDER=2 /tmp/plugin.sh", "anchor_script should prefix hover state env")
end)

local function test_ctx()
  return {
    appearance = { menu_item_height = 23 },
    settings = {
      font = {
        text = "Inter",
        style_map = { Regular = "Regular", Semibold = "Semibold", Bold = "Bold" },
        sizes = { small = 12 },
      },
    },
    theme = {
      WHITE = "0xffffffff",
      DARK_WHITE = "0xffbac2de",
      BG_SEC_COLR = "0xff1e1e2e",
      GREEN = "0xffa6e3a1",
      bar = { bg = "0xff11111b" },
    },
    font_string = function(family, style, size)
      return string.format("%s:%s:%s", family, style, tostring(size))
    end,
  }
end

run_test("ui_builder: popup headers rows separators and sections", function()
  local layout = {}
  local style = ui.popup_style(test_ctx())

  ui.header(layout, "triforce", "triforce.header", "Oracle", { style = style, color = "0xffa6e3a1" })
  ui.row(layout, "triforce", "triforce.continue", {
    style = style,
    icon = { string = "󰐃", color = "0xffa6e3a1" },
    label = "Continue",
    action = "continue.sh",
    prominent = true,
  })
  ui.separator(layout, "triforce", "triforce.sep", { style = style })

  assert_equal(layout[1].position, "popup.triforce", "header should attach to parent popup")
  assert_equal(layout[1].background.height, 25, "header should use menu_style header height")
  assert_equal(layout[2].background.height, 23, "row should use menu_style item height")
  assert_equal(layout[2].hover, true, "action rows should opt into hover treatment")
  assert_true(layout[2].click_script:find("continue%.sh", 1, false) ~= nil, "row should include action")
  assert_true(layout[2].click_script:find("popup.drawing=off", 1, true) ~= nil, "row action should close parent popup")
  assert_equal(layout[3].label, "───────────────", "separator should use the standard label")

  local section_layout = {}
  ui.section(section_layout, "triforce", "triforce.apps", {
    id = "apps",
    label = "Apps",
    color = "0xffa6e3a1",
    entries = {
      { id = "yaze", icon = "󰯙", label = "Yaze", action = "open yaze" },
    },
  }, { style = style })
  assert_equal(section_layout[1].name, "triforce.apps.header", "section should add a header")
  assert_equal(section_layout[2].name, "triforce.apps.yaze", "section should add row entries")
end)
