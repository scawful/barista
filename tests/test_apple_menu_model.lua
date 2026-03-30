local apple_menu_model = require("apple_menu_model")

run_test("apple_menu_model: builds rendered items from metadata", function()
  local result = apple_menu_model.build({
    base_items = {
      {
        id = "alpha",
        label = "Alpha",
        icon = "A",
        section = "apps",
        action = "echo alpha",
        available = true,
        default_enabled = true,
      },
      {
        id = "missing_item",
        label = "Missing",
        icon = "M",
        section = "support",
        action = "",
        available = false,
        default_enabled = true,
      },
    },
    sections = {
      apps = { id = "apps", label = "Apps", order = 0 },
      support = { id = "support", label = "Support", order = 1 },
      custom = { id = "custom", label = "Custom", order = 2 },
    },
    menu_config = {
      items = {
        alpha = { label = "Alpha Prime" },
      },
      sections = {
        support = { label = "Support Docs", order = 5 },
      },
      custom = {
        {
          id = "tools",
          label = "Toolbox",
          section = "custom",
          items = {
            { label = "Open Notes", action = "echo notes" },
            { type = "separator" },
            { type = "header", label = "Links" },
            { label = "Example", url = "https://example.com" },
          },
        },
      },
      work_google_apps = {
        {
          id = "calendar",
          label = "Calendar",
          url = "https://calendar.google.com",
        },
      },
    },
    project_shortcuts = {
      enabled = true,
      items = {
        {
          id = "project_alpha",
          label = "Project Alpha",
          action = "echo project",
          available = true,
          section = "apps",
          order = 1250,
        },
      },
    },
    show_missing = true,
    theme = { BLUE = "0xff89b4fa" },
  })

  assert_equal(result.sections.support.label, "Support Docs", "section override label")

  local by_id = {}
  for _, entry in ipairs(result.rendered) do
    by_id[entry.id] = entry
  end

  assert_equal(by_id.alpha.label, "Alpha Prime", "base item override label")
  assert_true(by_id.missing_item.missing == true, "missing base item should be surfaced when show_missing=true")
  assert_true(by_id.project_alpha ~= nil, "project shortcut should be included")
  assert_true(by_id.custom_tools.submenu == true, "custom item should support submenu rendering")
  assert_equal(by_id.custom_tools.items[1].label, "Open Notes", "submenu item label")
  assert_equal(by_id.custom_tools.items[2].type, "separator", "submenu separator")
  assert_equal(by_id.custom_tools.items[3].type, "header", "submenu header")
  assert_true(by_id.custom_tools.items[4].action:find("https://example.com", 1, true) ~= nil, "submenu URL item")
end)
