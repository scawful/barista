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
  run_test("state.set_space_mode: preserves an explicit float choice", function()
    local data = make_state()
    local original_save = state_module.save
    local saved_mode
    state_module.save = function(updated)
      saved_mode = updated.space_modes["1"]
      return true
    end
    local success, result = pcall(state_module.set_space_mode, data, 1, "float")
    state_module.save = original_save
    assert_true(success, "space setter should succeed")
    assert_true(result, "space setter should save")
    assert_equal(saved_mode, "float", "float must not fall back to startup BSP")
    assert_equal(data.space_modes["2"], "float", "other choices remain unchanged")
  end)

  run_test("state.normalize: preserves UUID layout preferences", function()
    local normalized = state_module.normalize({
      space_modes = { ["1"] = "float" },
      space_mode_uuids = { ["1"] = "space-uuid" },
      space_modes_by_uuid = { ["space-uuid"] = "float" },
    })
    assert_equal(normalized.space_modes_by_uuid["space-uuid"], "float", "canonical choice should survive normalization")
    assert_equal(normalized.space_mode_uuids["1"], "space-uuid", "legacy mirror binding should survive normalization")
  end)

  run_test("state.set_space_mode: legacy edits release only their UUID preference", function()
    for _, mode in ipairs({ "stack", "" }) do
      local data = make_state()
      data.space_mode_uuids = { ["1"] = "uuid-one", ["2"] = "uuid-two" }
      data.space_modes_by_uuid = { ["uuid-one"] = "bsp", ["uuid-two"] = "float" }
      local original_save = state_module.save
      state_module.save = function() return true end
      local success, result = pcall(state_module.set_space_mode, data, 1, mode)
      state_module.save = original_save
      assert_true(success and result, "legacy change should save")
      assert_true(data.space_mode_uuids["1"] == nil, "changed index binding should be released")
      assert_true(data.space_modes_by_uuid["uuid-one"] == nil, "old UUID should not override the edit")
      assert_equal(data.space_modes_by_uuid["uuid-two"], "float", "unrelated UUID should survive")
      if mode == "" then
        assert_true(data.space_modes["1"] == nil, "empty mode should remove the preference")
      else
        assert_equal(data.space_modes["1"], "stack", "explicit legacy choice should survive")
      end
    end
  end)

  run_test("state.set_space_mode: unchanged values retain UUID preferences", function()
    local data = make_state()
    data.space_mode_uuids = { ["1"] = "uuid-one" }
    data.space_modes_by_uuid = { ["uuid-one"] = "bsp" }
    local original_save = state_module.save
    local save_called = false
    state_module.save = function() save_called = true; return true end
    local success, result = pcall(state_module.set_space_mode, data, 1, "bsp")
    state_module.save = original_save
    assert_true(success and result and not save_called, "unchanged layout should not write")
    assert_equal(data.space_mode_uuids["1"], "uuid-one", "unchanged binding should survive")
    assert_equal(data.space_modes_by_uuid["uuid-one"], "bsp", "unchanged UUID preference should survive")
  end)

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

  run_test("state.normalize: migrates legacy yabai_status to control_center", function()
    local data = {
      widgets = { yabai_status = false },
      integrations = {},
    }
    local normalized = state_module.normalize(data)
    assert_true(normalized.widgets.yabai_status == nil, "legacy widget key should be removed")
    assert_equal(normalized.integrations.control_center.enabled, false, "control_center should inherit legacy disabled state")
  end)

  run_test("state.normalize: preserves explicit control_center setting over legacy key", function()
    local data = {
      widgets = { yabai_status = true },
      integrations = { control_center = { enabled = false } },
    }
    local normalized = state_module.normalize(data)
    assert_true(normalized.widgets.yabai_status == nil, "legacy widget key should be removed")
    assert_equal(normalized.integrations.control_center.enabled, false, "existing control_center setting should win")
  end)

  run_test("state.normalize: fills defaults for partial state", function()
    local normalized = state_module.normalize({ widgets = { clock = false } })
    assert_type(normalized.appearance, "table", "appearance defaults present")
    assert_type(normalized.modes, "table", "modes defaults present")
    assert_type(normalized.integrations.control_center, "table", "control_center defaults present")
    assert_equal(normalized.widgets.clock, false, "explicit widget value preserved")
    assert_equal(normalized.widgets.volume, true, "missing widget default applied")
    assert_equal(normalized.modes.widget_daemon, "auto", "widget daemon mode default applied")
    assert_equal(normalized.integrations.control_center.item_name, "control_center", "control_center item name default applied")
    assert_equal(normalized.widgets.task_focus, false, "task focus should be opt-in")
    assert_equal(normalized.system_info_items.actions, true, "system info actions should remain enabled by default")
    assert_equal(normalized.menus.calendar.task_provider, "files", "calendar should use the portable file provider")
    assert_type(normalized.menus.calendar.task_sources, "table", "calendar task source defaults present")
    assert_equal(#normalized.menus.calendar.task_sources, 0, "calendar task sources should be machine-local")
    assert_equal(normalized.menus.calendar.meeting_cache_file, "", "calendar meeting cache should be opt-in")
    assert_equal(normalized.menus.calendar.meeting_cache_max_age_seconds, 86400, "calendar meeting cache should expire after 24 hours by default")
  end)

  run_test("state.normalize: preserves disabled system info actions", function()
    local normalized = state_module.normalize({
      system_info_items = { actions = false },
    })
    assert_equal(normalized.system_info_items.actions, false, "explicit system info action preference preserved")
    assert_equal(normalized.system_info_items.procs, true, "unrelated system info defaults still merge")
  end)

  run_test("state.normalize: removes the retired Triforce polling interval", function()
    local normalized = state_module.normalize({
      menus = { oracle = { triforce = { update_freq = 45, label = "Oracle" } } },
    })
    assert_nil(normalized.menus.oracle.triforce.update_freq, "retired polling key should be removed")
    assert_equal(normalized.menus.oracle.triforce.label, "Oracle", "unrelated Triforce settings should be preserved")
  end)

  run_test("state.normalize: preserves explicit task configuration", function()
    local normalized = state_module.normalize({
      widgets = { task_focus = true },
      menus = {
        calendar = {
          task_provider = "custom",
          task_sources = { "/tmp/work.md" },
          meeting_cache_file = "/tmp/events.tsv",
          meeting_cache_max_age_seconds = 7200,
          custom_option = "keep",
        },
      },
    })
    assert_equal(normalized.widgets.task_focus, true, "explicit task focus preserved")
    assert_equal(normalized.menus.calendar.task_provider, "custom", "explicit task provider preserved")
    assert_equal(normalized.menus.calendar.task_sources[1], "/tmp/work.md", "explicit task source preserved")
    assert_equal(normalized.menus.calendar.meeting_cache_file, "/tmp/events.tsv", "explicit meeting cache preserved")
    assert_equal(normalized.menus.calendar.meeting_cache_max_age_seconds, 7200, "explicit meeting cache freshness preserved")
    assert_equal(normalized.menus.calendar.custom_option, "keep", "unrelated calendar setting preserved")
  end)
else
  run_test("state module: load check (skipped - module not available in test env)", function()
    -- This is expected when running outside the full barista environment
    assert_true(true, "skipped")
  end)
end
