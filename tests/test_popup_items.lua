local popup_items = require("popup_items")

run_test("popup_items: popup rows do not attach hover by default", function()
  local entry = popup_items.make_add("test", { hover_script = "hover.sh" })("test.row", {
    icon = "x",
    label = "Row",
  })

  assert_equal(entry.attach_hover, false, "popup row hover should be opt-in")
  assert_nil(entry.props.script, "popup row should not get hover script by default")
end)

run_test("popup_items: popup rows can opt into hover explicitly", function()
  local entry = popup_items.make_add("test", { hover_script = "hover.sh" })("test.row", {
    icon = "x",
    label = "Row",
    hover = true,
  })

  assert_equal(entry.attach_hover, true, "popup row hover should be enabled explicitly")
  assert_equal(entry.props.script, "hover.sh", "popup row should inherit hover script when enabled")
end)
