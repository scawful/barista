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

run_test("bar_config.compute: zero motion reaches normal and fast hover", function()
  local result = bar_config.compute(
    { appearance = { hover_animation_duration = 0, blur_radius = 0 } },
    theme, state_module, "1,2,3", {}
  )

  assert_equal(result.hover_animation_duration, 0, "normal hover is immediate")
  assert_equal(result.fast_hover_duration, 0, "fast hover stays immediate")
  assert_equal(result.bar.blur_radius, 0, "explicit no-blur setting is preserved")
  assert_equal(result.defaults.associated_display, "1,2,3", "all display associations are retained")
end)

run_test("bar_config.compute: hover durations are finite whole frames", function()
  for _, case in ipairs({
    { value = "6", expected = 6 },
    { value = 2.8, expected = 2 },
    { value = -1, expected = 0 },
    { value = "invalid", expected = 8 },
    { value = math.huge, expected = 8 },
    { value = 0 / 0, expected = 8 },
  }) do
    local result = bar_config.compute(
      { appearance = { hover_animation_duration = case.value } },
      theme, state_module, "all", {}
    )
    assert_equal(result.hover_animation_duration, case.expected, "normalized frame count")
    assert_equal(result.fast_hover_duration, math.min(case.expected, 3), "fast frame count")
  end
  local result = bar_config.compute({}, theme, state_module, "all", {})
  assert_equal(result.hover_animation_duration, 8, "fallback matches state defaults")
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
