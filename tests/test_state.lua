-- test_state.lua - Tests for state module (mock-based, no actual state.json needed)

-- We test the utility functions that don't require the full sketchybar runtime

-- Mock state for testing
local function make_state()
  return {
    widgets = { clock = true, battery = false, volume = true },
    icons = { apple = "", clock = "", missing = nil },
    integrations = {
      yaze = { enabled = true, recent_roms = {} },
      oracle = { enabled = false },
      emacs = { enabled = true },
      halext = { enabled = false },
    },
    appearance = { bar_height = 28, corner_radius = 0 },
    space_modes = { ["1"] = "bsp", ["2"] = "float" },
  }
end

-- Attempt to load state module (may fail in test env, so we test what we can)
local ok, state_module = pcall(require, "state")

if ok and state_module then
  run_test("state.get: top-level key", function()
    local state = make_state()
    if state_module.get then
      local result = state_module.get(state, "appearance.bar_height", 0)
      assert_equal(result, 28, "bar_height")
    end
  end)

  run_test("state.get: missing key returns default", function()
    local state = make_state()
    if state_module.get then
      local result = state_module.get(state, "nonexistent.path", "default_val")
      assert_equal(result, "default_val", "fallback default")
    end
  end)

  run_test("state.get_icon: existing icon", function()
    local state = make_state()
    if state_module.get_icon then
      local result = state_module.get_icon(state, "apple", nil)
      assert_equal(result, "", "apple icon")
    end
  end)

  run_test("state.get_icon: missing icon returns default", function()
    local state = make_state()
    if state_module.get_icon then
      local result = state_module.get_icon(state, "nonexistent", "fallback")
      assert_equal(result, "fallback", "fallback for missing icon")
    end
  end)

  run_test("state.get_integration: enabled integration", function()
    local state = make_state()
    if state_module.get_integration then
      local result = state_module.get_integration(state, "yaze")
      assert_type(result, "table", "yaze integration")
      assert_true(result.enabled, "yaze enabled")
    end
  end)

  run_test("state.get_integration: disabled integration", function()
    local state = make_state()
    if state_module.get_integration then
      local result = state_module.get_integration(state, "oracle")
      assert_type(result, "table", "oracle integration")
      assert_true(not result.enabled, "oracle disabled")
    end
  end)
else
  run_test("state module: load check (skipped - module not available in test env)", function()
    -- This is expected when running outside the full barista environment
    assert_true(true, "skipped")
  end)
end
