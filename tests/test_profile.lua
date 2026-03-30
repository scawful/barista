-- test_profile.lua - Tests for modules/profile.lua

local profile = require("profile")

run_test("get_selected_profile: nil state returns minimal", function()
  local result = profile.get_selected_profile(nil)
  assert_equal(result, "minimal", "default profile")
end)

run_test("get_selected_profile: empty state returns minimal", function()
  local result = profile.get_selected_profile({})
  assert_equal(result, "minimal", "empty state default")
end)

run_test("get_selected_profile: state.profile overrides", function()
  local result = profile.get_selected_profile({ profile = "custom" })
  assert_equal(result, "custom", "state override")
end)

run_test("get_selected_profile: BARISTA_PROFILE env overrides default", function()
  local result = profile.get_selected_profile({}, {
    env = {
      BARISTA_PROFILE = "personal",
    }
  })
  assert_equal(result, "personal", "BARISTA_PROFILE env override")
end)

run_test("get_selected_profile: SKETCHYBAR_PROFILE env fallback still works", function()
  local result = profile.get_selected_profile({}, {
    env = {
      SKETCHYBAR_PROFILE = "work",
    }
  })
  assert_equal(result, "work", "SKETCHYBAR_PROFILE env fallback")
end)

run_test("get_selected_profile: local config profile used when state/env unset", function()
  local result = profile.get_selected_profile({}, {
    config = {
      profile = "personal",
    }
  })
  assert_equal(result, "personal", "config profile override")
end)

run_test("get_selected_profile: state still beats env and local config", function()
  local result = profile.get_selected_profile({ profile = "girlfriend" }, {
    env = {
      BARISTA_PROFILE = "work",
    },
    config = {
      profile = "personal",
    }
  })
  assert_equal(result, "girlfriend", "state should win")
end)

run_test("merge_config: nil profile returns base", function()
  local base = { widgets = { clock = true } }
  local result = profile.merge_config(base, nil)
  assert_equal(result.widgets.clock, true, "base preserved")
end)

run_test("merge_config: appearance merge (only nil keys)", function()
  local base = { appearance = { bar_height = 28 } }
  local prof = { appearance = { bar_height = 32, corner_radius = 5 } }
  local result = profile.merge_config(base, prof)
  -- bar_height already set in base, should NOT be overwritten
  assert_equal(result.appearance.bar_height, 28, "existing preserved")
  -- corner_radius was nil, should be set
  assert_equal(result.appearance.corner_radius, 5, "new key set")
end)

run_test("merge_config: widgets merge (only nil keys)", function()
  local base = { widgets = { clock = true } }
  local prof = { widgets = { clock = false, battery = true } }
  local result = profile.merge_config(base, prof)
  assert_equal(result.widgets.clock, true, "existing preserved")
  assert_equal(result.widgets.battery, true, "new widget set")
end)

run_test("merge_config: modes merge (auto overridden)", function()
  local base = { modes = { window_manager = "auto" } }
  local prof = { modes = { window_manager = "disabled" } }
  local result = profile.merge_config(base, prof)
  assert_equal(result.modes.window_manager, "disabled", "auto overridden")
end)

run_test("merge_config: modes merge (explicit not overridden)", function()
  local base = { modes = { window_manager = "required" } }
  local prof = { modes = { window_manager = "disabled" } }
  local result = profile.merge_config(base, prof)
  -- "required" is not nil and not "auto", should be preserved
  assert_equal(result.modes.window_manager, "required", "explicit preserved")
end)

run_test("get_integration_flags: nil profile", function()
  local result = profile.get_integration_flags(nil)
  assert_type(result, "table", "returns table")
end)

run_test("get_integration_flags: empty profile", function()
  local result = profile.get_integration_flags({})
  assert_type(result, "table", "returns table")
end)

run_test("get_integration_flags: returns integrations", function()
  local result = profile.get_integration_flags({ integrations = { yaze = true } })
  assert_equal(result.yaze, true, "yaze flag")
end)

run_test("get_menu_sections: nil profile", function()
  local result = profile.get_menu_sections(nil)
  assert_type(result, "table", "returns table")
  assert_equal(#result, 0, "empty")
end)

run_test("get_menu_sections: sorted by order", function()
  local p = { menu_sections = {
    { name = "B", order = 2 },
    { name = "A", order = 1 },
    { name = "C", order = 3 },
  }}
  local result = profile.get_menu_sections(p)
  assert_equal(result[1].name, "A", "sorted first")
  assert_equal(result[2].name, "B", "sorted second")
  assert_equal(result[3].name, "C", "sorted third")
end)

run_test("get_paths: nil profile", function()
  local result = profile.get_paths(nil)
  assert_type(result, "table", "returns table")
end)

run_test("get_paths: returns paths table", function()
  local result = profile.get_paths({ paths = { custom = "/foo" } })
  assert_equal(result.custom, "/foo", "custom path")
end)
