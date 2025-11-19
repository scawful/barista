-- Google C++ Development Integration
-- Specialized integration for Google's C++ development workflows

local google_cpp = {}

google_cpp.enabled = false
google_cpp.config = {}

-- Google-specific tools
google_cpp.tools = {
  bazel = {
    name = "Bazel",
    icon = "󰆍",
    build_cmd = "bazel build //...",
    test_cmd = "bazel test //...",
    query_cmd = "bazel query //...",
  },
  critter = {
    name = "Critter",
    icon = "󰨞",
    url = "https://critter.corp.google.com",
  },
  codesearch = {
    name = "CodeSearch",
    icon = "󰦨",
    url = "https://cs.corp.google.com",
  },
  gerrit = {
    name = "Gerrit",
    icon = "󰨞",
    url = "https://critique.corp.google.com",
  },
  g3 = {
    name = "G3",
    icon = "󰨞",
    url = "https://g3doc.corp.google.com",
  },
}

function google_cpp.init(sbar, config)
  if not config.integrations or not config.integrations.google_cpp then
    return
  end
  
  local gcpp_config = config.integrations.google_cpp
  if not gcpp_config.enabled then
    return
  end
  
  google_cpp.enabled = true
  google_cpp.config = gcpp_config
  
  print("Google C++ Development integration enabled")
end

function google_cpp.get_menu_items(ctx)
  if not google_cpp.enabled then
    return {}
  end
  
  local items = {}
  
  table.insert(items, {
    type = "header",
    name = "menu.google_cpp.header",
    label = "Google C++ Tools",
  })
  
  -- Code Review
  table.insert(items, {
    type = "item",
    name = "menu.google_cpp.gerrit",
    icon = google_cpp.tools.gerrit.icon,
    label = "Gerrit (Code Review)",
    action = "open -a 'Google Chrome' '" .. google_cpp.tools.gerrit.url .. "'",
  })
  
  table.insert(items, {
    type = "item",
    name = "menu.google_cpp.critter",
    icon = google_cpp.tools.critter.icon,
    label = "Critter",
    action = "open -a 'Google Chrome' '" .. google_cpp.tools.critter.url .. "'",
  })
  
  table.insert(items, { type = "separator", name = "menu.google_cpp.sep1" })
  
  -- Code Search
  table.insert(items, {
    type = "item",
    name = "menu.google_cpp.codesearch",
    icon = google_cpp.tools.codesearch.icon,
    label = "CodeSearch",
    action = "open -a 'Google Chrome' '" .. google_cpp.tools.codesearch.url .. "'",
  })
  
  table.insert(items, {
    type = "item",
    name = "menu.google_cpp.g3",
    icon = google_cpp.tools.g3.icon,
    label = "G3 Documentation",
    action = "open -a 'Google Chrome' '" .. google_cpp.tools.g3.url .. "'",
  })
  
  table.insert(items, { type = "separator", name = "menu.google_cpp.sep2" })
  
  -- Bazel Commands
  local project_path = google_cpp.config.project_path or os.getenv("HOME") .. "/google3"
  local current_target = google_cpp.config.current_target or "//..."
  
  table.insert(items, {
    type = "item",
    name = "menu.google_cpp.bazel_build",
    icon = google_cpp.tools.bazel.icon,
    label = "Bazel Build",
    action = string.format("osascript -e 'tell application \"Terminal\" to do script \"cd %s && bazel build %s\"'", 
      project_path, current_target),
  })
  
  table.insert(items, {
    type = "item",
    name = "menu.google_cpp.bazel_test",
    icon = google_cpp.tools.bazel.icon,
    label = "Bazel Test",
    action = string.format("osascript -e 'tell application \"Terminal\" to do script \"cd %s && bazel test %s\"'", 
      project_path, current_target),
  })
  
  table.insert(items, {
    type = "item",
    name = "menu.google_cpp.bazel_query",
    icon = google_cpp.tools.bazel.icon,
    label = "Bazel Query",
    action = string.format("osascript -e 'tell application \"Terminal\" to do script \"cd %s && bazel query %s\"'", 
      project_path, current_target),
  })
  
  -- CI/CD Status
  if google_cpp.config.ci_enabled then
    table.insert(items, { type = "separator", name = "menu.google_cpp.sep3" })
    table.insert(items, {
      type = "item",
      name = "menu.google_cpp.ci_status",
      icon = "󰨞",
      label = "CI/CD Status",
      action = ctx.call_script(ctx.scripts.ci_status or "", "show"),
    })
  end
  
  return items
end

-- Create Bazel build status widget
function google_cpp.create_bazel_widget(sbar, factory, theme, state_data)
  if not google_cpp.enabled then
    return nil
  end
  
  local widget = factory.create("bazel_status", {
    icon = "󰆍",
    label = "Bazel",
    update_freq = 10,
    script = os.getenv("HOME") .. "/.config/sketchybar/plugins/bazel_status.sh",
    click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
    popup = {
      background = {
        border_width = 2,
        corner_radius = 4,
        border_color = theme.WHITE,
        color = theme.bar.bg,
      }
    }
  })
  
  return widget
end

return google_cpp

