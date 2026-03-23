local bar_config = require("bar_config")

local theme = {
  WHITE = 0xffffffff,
  bar = { bg = "0xC021162F" },
}

local state_module = {}

function state_module.get_appearance(state, key, default)
  local appearance = state.appearance or {}
  local value = appearance[key]
  if value == nil then
    return default
  end
  return value
end

run_test("bar_config.compute: more-space boost increases effective widget scale", function()
  local result = bar_config.compute(
    { appearance = { bar_height = 28, widget_scale = 1.0 } },
    theme,
    state_module,
    "all",
    { more_space_active = true, top_inset = 38 }
  )

  assert_equal(result.widget_scale_base, 1.0, "base scale")
  assert_equal(result.more_space_widget_scale_boost, 0.08, "auto boost")
  assert_equal(result.widget_scale, 1.08, "effective scale")
  assert_equal(result.configured_bar_height, 28, "configured baseline")
  assert_equal(result.bar_height, 38, "effective bar height matches inset")
end)

run_test("bar_config.compute: auto more-space scaling can be disabled", function()
  local result = bar_config.compute(
    { appearance = { bar_height = 28, widget_scale = 1.0, auto_more_space_scaling = false } },
    theme,
    state_module,
    "all",
    { more_space_active = true }
  )

  assert_equal(result.more_space_widget_scale_boost, 0, "boost disabled")
  assert_equal(result.widget_scale, 1.0, "effective scale unchanged")
end)
