local menu = require("menu")

run_test("menu: menus.apple.enabled=false skips the Apple chip", function()
  local previous = package.loaded.apple_menu_enhanced
  local setup_calls = 0
  package.loaded.apple_menu_enhanced = {
    setup = function()
      setup_calls = setup_calls + 1
      return { popup_parents = { "apple_menu" } }
    end,
  }
  local ok, metadata = pcall(menu.render_all_menus, {
    state = { menus = { apple = { enabled = false } } },
    theme = { WHITE = "0xffffffff", bar = { bg = "0xff000000" } },
    scripts = { yabai_control = "/tmp/scripts/yabai_control.sh" },
  })
  package.loaded.apple_menu_enhanced = previous
  assert_true(ok, metadata)
  assert_equal(setup_calls, 0, "disabled Apple menu should not render")
  assert_equal(#metadata.popup_parents, 0, "disabled Apple menu registers no popup parent")
end)

run_test("menu: enhanced Apple menu receives the resolved SketchyBar binary", function()
  local previous = package.loaded.apple_menu_enhanced
  local received = nil
  local metadata = nil

  package.loaded.apple_menu_enhanced = {
    setup = function(ctx)
      received = ctx
      return {
        popup_parents = { "apple_menu" },
        submenu_parents = { "menu.level1", "menu.level2" },
        submenu_ancestors = {
          ["menu.level2"] = { "menu.level1" },
        },
      }
    end,
  }

  local ok, err = pcall(function()
    metadata = menu.render_all_menus({
      theme = { WHITE = "0xffffffff", bar = { bg = "0xff000000" } },
      scripts = { yabai_control = "/tmp/scripts/yabai_control.sh" },
      SKETCHYBAR_BIN = "/opt/homebrew/bin/sketchybar",
      sketchybar_bin = "/opt/homebrew/bin/sketchybar",
    })
  end)

  package.loaded.apple_menu_enhanced = previous
  assert_true(ok, err)
  assert_true(received ~= nil, "enhanced Apple menu should be invoked")
  assert_equal(received.SKETCHYBAR_BIN, "/opt/homebrew/bin/sketchybar", "uppercase binary path should be forwarded")
  assert_equal(received.sketchybar_bin, "/opt/homebrew/bin/sketchybar", "lowercase binary path should be forwarded")
  assert_equal(
    table.concat(metadata.submenu_ancestors["menu.level2"] or {}, "|"),
    "menu.level1",
    "enhanced menu ancestor metadata should survive aggregation"
  )
end)
