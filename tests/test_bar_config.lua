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

run_test("bar_config.compute: SF family names resolve to installed system fonts", function()
  local result = bar_config.compute(
    { appearance = { font_numbers = "SF Mono", font_popup = "SF Pro", font_text = "Source Code Pro" } },
    theme, state_module, "all", {}
  )
  assert_equal(result.settings.font.numbers, ".SF NS Mono", "SF Mono alias")
  assert_equal(result.settings.font.popup, "System Font", "SF Pro alias")
  assert_equal(result.settings.font.text, "Source Code Pro", "non-SF family untouched")
  assert_equal(result.defaults["popup.blur_radius"], 20, "popup blur default")
  assert_equal(result.defaults["popup.background.shadow.drawing"], true, "popup shadow default")
end)

run_test("bar_config.style_popup_row: popup text rows get popup font and icon column", function()
  local result = bar_config.compute({}, theme, state_module, "all", {})
  local style = result.style_popup_row

  local row = style({
    position = "popup.clock",
    icon = "\239\129\179",
    ["label.font"] = "Source Code Pro:Semibold:13.0",
  })
  assert_equal(row["label.font"], "System Font:Semibold:13.0", "text font swapped")
  assert_equal(row["icon.width"], 26, "fixed icon column")
  assert_equal(row["icon.align"], "center", "icon centered in column")

  local numbers = style({
    position = "popup.clock",
    icon = { string = "\239\129\179", drawing = false },
    label = { font = { family = ".SF NS Mono", style = "Regular", size = 13 } },
  })
  assert_equal(numbers.label.font.family, ".SF NS Mono", "numbers font kept")
  assert_equal(numbers["icon.width"], nil, "hidden icon gets no column")

  local both = style({
    position = "popup.control_center",
    ["label.font"] = "Source Code Pro:Bold:13.0",
    label = { string = "Tile", font = "Source Code Pro:Semibold:13.0" },
  })
  assert_equal(both["label.font"], "System Font:Bold:13.0", "flat font swapped")
  assert_equal(both.label.font, "System Font:Semibold:13.0", "nested font swapped")

  local wide_icon = style({ position = "popup.x", icon = "⌘K", ["label.font"] = "Hack:Bold:12.0" })
  assert_equal(wide_icon["icon.width"], nil, "multi-glyph icon keeps natural width")
  assert_equal(wide_icon["label.font"], "Hack:Bold:12.0", "other families untouched")

  local bar_item = style({ position = "right", icon = "\239\129\179", ["label.font"] = "Source Code Pro:Bold:14.0" })
  assert_equal(bar_item["label.font"], "Source Code Pro:Bold:14.0", "bar items untouched")
  assert_equal(bar_item["icon.width"], nil, "bar items get no icon column")
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

run_test("bar_config.compute: dense portrait topology shrinks and scopes widgets", function()
  local result = bar_config.compute(
    { appearance = { bar_height = 28, widget_scale = 1.0, bar_padding_left = 14, bar_padding_right = 14 } },
    theme,
    state_module,
    "1",
    {
      density = "dense",
      hide_anchor_labels = true,
      optional_wide_only = false,
      narrow_status_strip = false,
      split_layout = false,
      all_narrow = true,
      clock_style = "time",
      wide_displays = "",
      narrow_displays = "1",
      fingerprint = "dense|min=800|wide=|narrow=1|split=0",
      min_width = 800,
    }
  )

  assert_equal(result.display_density, "dense", "density")
  assert_equal(result.clock_style, "time", "clock style")
  assert_true(result.hide_anchor_labels, "hide labels")
  assert_equal(result.bar.padding_left, 6, "bar padding compacted")
  assert_true(result.widget_scale < 1.0, "widget scale reduced")
end)

run_test("bar_config.compute: split layout keeps wide desktop full", function()
  local result = bar_config.compute(
    { appearance = { bar_height = 28, widget_scale = 1.0, bar_padding_left = 14, bar_padding_right = 14 } },
    theme,
    state_module,
    "1,2",
    {
      density = "dense",
      hide_anchor_labels = false,
      optional_wide_only = true,
      narrow_status_strip = true,
      split_layout = true,
      clock_style = "full",
      wide_displays = "1",
      narrow_displays = "2",
      fingerprint = "dense|min=800|wide=1|narrow=2|split=1",
      min_width = 800,
    }
  )

  assert_equal(result.display_density, "dense", "density reports narrowest")
  assert_true(result.split_layout, "split layout")
  assert_true(result.optional_wide_only, "optionals stay wide")
  assert_true(result.narrow_status_strip, "narrow status strip")
  assert_equal(result.clock_style, "full", "wide clock stays full")
  assert_true(not result.hide_anchor_labels, "wide labels stay")
  assert_equal(result.bar.padding_left, 14, "wide padding preserved")
  assert_equal(result.widget_scale, 1.0, "wide scale preserved")
end)

run_test("bar_config.compute: auto display density can be disabled", function()
  local result = bar_config.compute(
    { appearance = { auto_display_density = false, widget_scale = 1.0 } },
    theme,
    state_module,
    "all",
    {
      density = "dense",
      hide_anchor_labels = true,
      optional_wide_only = true,
      clock_style = "time",
    }
  )

  assert_equal(result.display_density, "comfortable", "density ignored when disabled")
  assert_equal(result.clock_style, "full", "clock stays full")
  assert_true(not result.hide_anchor_labels, "labels remain")
  assert_equal(result.widget_scale, 1.0, "scale unchanged")
end)
