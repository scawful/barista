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
      return [[{"screen":0,"topInset":38,"bottomInset":0}]]
    end
    return ""
  end)

  assert_true(result.more_space_active, "more-space detected")
  assert_equal(result.top_inset, 38, "top inset")
  assert_nil(result.bottom_inset, "zero bottom inset omitted")
end)
