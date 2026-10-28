local display_profile = require("display_profile")

run_test("display_profile.parse_resolution: parses spaced resolution", function()
  local width, height = display_profile.parse_resolution("3600 x 2338")
  assert_equal(width, 3600, "width")
  assert_equal(height, 2338, "height")
end)

run_test("display_profile.parse_resolution: parses spdisplays native resolution", function()
  local width, height = display_profile.parse_resolution("spdisplays_3024x1964Retina")
  assert_equal(width, 3024, "width")
  assert_equal(height, 1964, "height")
end)

run_test("display_profile.analyze: detects built-in more-space mode", function()
  local result = display_profile.analyze({
    SPDisplaysDataType = {
      {
        spdisplays_ndrvs = {
          {
            spdisplays_connection_type = "spdisplays_internal",
            _spdisplays_pixels = "3600 x 2338",
            spdisplays_pixelresolution = "spdisplays_3024x1964Retina",
          },
        },
      },
    },
  })

  assert_true(result.built_in_present, "built-in detected")
  assert_true(result.more_space_active, "more-space detected")
  assert_equal(result.render_width, 3600, "render width")
  assert_equal(result.native_width, 3024, "native width")
end)

run_test("display_profile.analyze: native mode stays neutral", function()
  local result = display_profile.analyze({
    SPDisplaysDataType = {
      {
        spdisplays_ndrvs = {
          {
            spdisplays_display_type = "spdisplays_built-in-liquid-retina-xdr",
            _spdisplays_pixels = "3024 x 1964",
            spdisplays_pixelresolution = "spdisplays_3024x1964Retina",
          },
        },
      },
    },
  })

  assert_true(result.built_in_present, "built-in detected")
  assert_true(not result.more_space_active, "native mode should not boost")
  assert_equal(result.render_scale, 1.0, "native scale")
end)

run_test("display_profile.detect: merges screen inset metrics", function()
  local result = display_profile.detect(function(cmd)
    if cmd:find("system_profiler", 1, true) then
      return [[{"SPDisplaysDataType":[{"spdisplays_ndrvs":[{"spdisplays_connection_type":"spdisplays_internal","_spdisplays_pixels":"3600 x 2338","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"}]}]}]]
    end
    if cmd:find("osascript", 1, true) then
      return [[{"screen":0,"topInset":38,"bottomInset":0,"frameWidth":1800,"frameHeight":1169}]]
    end
    if cmd:find("--query displays", 1, true) then
      return [=[[{"arrangement-id":1,"frame":{"w":1800,"h":1169}}]]=]
    end
    return ""
  end)

  assert_true(result.more_space_active, "more-space detected")
  assert_equal(result.top_inset, 38, "top inset")
  assert_nil(result.bottom_inset, "zero bottom inset omitted")
  assert_equal(result.density, "comfortable", "single wide display stays comfortable")
  assert_equal(result.min_width, 1800, "min width from frames")
  assert_equal(result.wide_displays, "1", "SketchyBar display number")
end)

run_test("display_profile.detect: inset fallback sets density but no display numbers", function()
  local result = display_profile.detect(function(cmd)
    if cmd:find("osascript", 1, true) then
      return [[{"screen":0,"topInset":38,"bottomInset":0,"frameWidth":900,"frameHeight":1600}]]
    end
    return ""
  end)

  assert_equal(result.density, "dense", "fallback frames still drive density")
  assert_equal(result.wide_displays, "", "NSScreen index is not a SketchyBar display")
  assert_equal(result.narrow_displays, "", "NSScreen index is not a SketchyBar display")
  assert_true(not result.split_layout, "no split without display numbers")
end)

run_test("display_profile.classify_displays: portrait external becomes dense", function()
  local layout = display_profile.classify_displays({
    { id = 1, width = 1800, height = 1169 },
    { id = 2, width = 800, height = 1280 },
  })

  assert_equal(layout.density, "dense", "800pt portrait is dense")
  assert_true(layout.has_portrait, "portrait flagged")
  assert_true(layout.split_layout, "mixed wide+narrow is a split layout")
  assert_true(not layout.all_narrow, "laptop keeps a wide desktop")
  assert_equal(layout.min_width, 800, "min width")
  assert_equal(layout.wide_displays, "1", "laptop stays wide")
  assert_equal(layout.narrow_displays, "2", "portrait is narrow")
  assert_true(layout.optional_wide_only, "optional widgets stay on wide displays")
  assert_true(layout.narrow_status_strip, "narrow monitors get compact status clones")
  assert_true(not layout.hide_anchor_labels, "wide desktop keeps full labels")
  assert_equal(layout.clock_style, "full", "wide desktop keeps full clock")
end)

run_test("display_profile.classify_displays: all-narrow densifies globally", function()
  local layout = display_profile.classify_displays({
    { id = 1, width = 800, height = 1280 },
  })

  assert_equal(layout.density, "dense", "single portrait is dense")
  assert_true(layout.all_narrow, "only narrow displays")
  assert_true(not layout.split_layout, "no wide peer")
  assert_true(layout.hide_anchor_labels, "homogeneous narrow hides labels")
  assert_equal(layout.clock_style, "time", "homogeneous narrow uses time clock")
  assert_true(not layout.optional_wide_only, "no wide target to park optionals on")
end)

run_test("display_profile.density_for_width: thresholds", function()
  assert_equal(display_profile.density_for_width(1800), "comfortable", "wide")
  assert_equal(display_profile.density_for_width(1200), "compact", "mid")
  assert_equal(display_profile.density_for_width(800), "dense", "narrow")
end)

run_test("display_profile.detect: multi-display portrait topology", function()
  local result = display_profile.detect(function(cmd)
    if cmd:find("system_profiler", 1, true) then
      return [[{"SPDisplaysDataType":[{"spdisplays_ndrvs":[{"spdisplays_connection_type":"spdisplays_internal","_spdisplays_pixels":"3024 x 1964","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"}]}]}]]
    end
    if cmd:find("osascript", 1, true) then
      return table.concat({
        [[{"screen":0,"topInset":38,"bottomInset":0,"frameWidth":1800,"frameHeight":1169}]],
        [[{"screen":1,"topInset":0,"bottomInset":0,"frameWidth":800,"frameHeight":1280}]],
      }, "\n")
    end
    if cmd:find("--query displays", 1, true) then
      return [=[[{"arrangement-id":1,"frame":{"w":1800,"h":1169}},{"arrangement-id":2,"frame":{"w":800,"h":1280}}]]=]
    end
    return ""
  end)

  assert_equal(result.density, "dense", "multi-display densifies to narrowest")
  assert_equal(result.wide_displays, "1", "wide list")
  assert_equal(result.narrow_displays, "2", "narrow list")
  assert_true(result.split_layout, "split layout")
  assert_true(result.optional_wide_only, "optional wide only")
  assert_true(result.narrow_status_strip, "narrow status strip")
  assert_true(not result.hide_anchor_labels, "wide desktop keeps labels")
  assert_equal(result.clock_style, "full", "wide desktop keeps full clock")
end)
