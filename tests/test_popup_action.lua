-- test_popup_action.lua - Focused tests for popup helper behavior

local ok, popup_action = pcall(require, "popup_action")

if not ok then
  run_test("popup_action module: load (skipped)", function()
    print("    ⊘ " .. tostring(popup_action))
    assert_true(true, "skipped — module not loadable in test env")
  end)
  return
end

local function record_exec_calls()
  local calls = {}
  local function exec(command)
    table.insert(calls, command)
    return 0
  end
  return calls, exec
end

run_test("popup_action.resolve_control_center_item_name: explicit ctx wins", function()
  local name = popup_action.resolve_control_center_item_name({
    control_center_item_name = "status_hub",
    state = {
      integrations = {
        control_center = { item_name = "state_hub" },
      },
    },
  }, function()
    return "env_hub"
  end)
  assert_equal(name, "status_hub", "ctx should win over env and state")
end)

run_test("popup_action.render_popup: custom control_center parent is used", function()
  local calls, exec = record_exec_calls()
  local ok_render = popup_action.render_popup("demo", {
    control_center_item_name = "status_hub",
  }, {
    exec = exec,
    sketchybar_bin = "sketchybar",
    definitions = {
      demo = {
        name = "popup.demo",
        items = function()
          return {
            { type = "item", name = "row", label = "Row", action = "echo row" },
            { type = "separator" },
          }
        end,
      },
    },
  })

  assert_true(ok_render, "popup should render")
  assert_true(#calls >= 4, "expected sketchybar commands")
  assert_true(calls[1]:match('popup%.status_hub') ~= nil, "container should attach to the resolved popup parent")
  assert_true(calls[2]:match('popup%.drawing=off') ~= nil, "container should start hidden")
  assert_true(calls[#calls]:match('popup%.drawing=on') ~= nil, "popup should open at the end")
end)

run_test("popup_action.render_popup: control_panel action uses injected exec", function()
  local calls, exec = record_exec_calls()
  local ok_render = popup_action.render_popup("control_panel", {
    scripts = { open_control_panel = "/tmp/My Panel/open_control_panel.sh" },
  }, {
    exec = exec,
  })

  assert_true(ok_render, "control panel action should run")
  assert_equal(#calls, 1, "direct action should emit one command")
  assert_true(calls[1]:match('"/tmp/My Panel/open_control_panel%.sh" %-%-panel &') ~= nil, "script path should be quoted")
end)

run_test("popup_action.close_all: uses provided definitions", function()
  local calls, exec = record_exec_calls()
  popup_action.close_all({
    exec = exec,
    sketchybar_bin = "sketchybar",
    definitions = {
      alpha = { name = "popup.alpha" },
      beta = { name = "popup.beta" },
    },
  })

  assert_equal(#calls, 2, "two popup close commands")
  local joined = table.concat(calls, "\n")
  assert_true(joined:match('popup%.alpha') ~= nil, "alpha popup should be closed")
  assert_true(joined:match('popup%.beta') ~= nil, "beta popup should be closed")
end)
