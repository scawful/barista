-- C++ Development Integration for Barista
-- Provides widgets and menu items for C++ development workflows

local cpp_dev = {}

cpp_dev.enabled = false
cpp_dev.config = {}

-- Default build systems
cpp_dev.build_systems = {
  cmake = {
    name = "CMake",
    icon = "󰨞",
    build_cmd = "cmake --build build",
    test_cmd = "ctest --test-dir build",
    clean_cmd = "rm -rf build",
  },
  bazel = {
    name = "Bazel",
    icon = "󰆍",
    build_cmd = "bazel build //...",
    test_cmd = "bazel test //...",
    clean_cmd = "bazel clean",
  },
  make = {
    name = "Make",
    icon = "󰨞",
    build_cmd = "make",
    test_cmd = "make test",
    clean_cmd = "make clean",
  },
}

-- Project detection
function cpp_dev.detect_build_system(project_path)
  if os.execute("test -f " .. project_path .. "/BUILD.bazel") == 0 or
     os.execute("test -f " .. project_path .. "/WORKSPACE") == 0 then
    return "bazel"
  elseif os.execute("test -f " .. project_path .. "/CMakeLists.txt") == 0 then
    return "cmake"
  elseif os.execute("test -f " .. project_path .. "/Makefile") == 0 then
    return "make"
  end
  return nil
end

function cpp_dev.init(sbar, config)
  if not config.integrations or not config.integrations.cpp_dev then
    return
  end
  
  local cpp_config = config.integrations.cpp_dev
  if not cpp_config.enabled then
    return
  end
  
  cpp_dev.enabled = true
  cpp_dev.config = cpp_config
  
  -- Merge custom build systems
  if cpp_config.build_systems then
    for k, v in pairs(cpp_config.build_systems) do
      cpp_dev.build_systems[k] = v
    end
  end
  
  print("C++ Development integration enabled")
end

function cpp_dev.get_menu_items(ctx)
  if not cpp_dev.enabled then
    return {}
  end
  
  local items = {}
  local project_path = cpp_dev.config.project_path or os.getenv("HOME") .. "/Code"
  
  -- Detect current project
  local current_project = cpp_dev.config.current_project or "default"
  local build_system = cpp_dev.detect_build_system(project_path .. "/" .. current_project)
  
  -- Build system menu
  table.insert(items, {
    type = "header",
    name = "menu.cpp.header",
    label = "C++ Development",
  })
  
  if build_system then
    local bs = cpp_dev.build_systems[build_system]
    table.insert(items, {
      type = "item",
      name = "menu.cpp.build",
      icon = "󰨞",
      label = "Build (" .. bs.name .. ")",
      action = string.format("cd %s/%s && %s", project_path, current_project, bs.build_cmd),
    })
    table.insert(items, {
      type = "item",
      name = "menu.cpp.test",
      icon = "󰈔",
      label = "Run Tests",
      action = string.format("cd %s/%s && %s", project_path, current_project, bs.test_cmd),
    })
    table.insert(items, {
      type = "item",
      name = "menu.cpp.clean",
      icon = "󰆑",
      label = "Clean Build",
      action = string.format("cd %s/%s && %s", project_path, current_project, bs.clean_cmd),
    })
  end
  
  table.insert(items, { type = "separator", name = "menu.cpp.sep1" })
  
  -- Project switcher
  table.insert(items, {
    type = "item",
    name = "menu.cpp.project_switch",
    icon = "󰨞",
    label = "Switch Project",
    action = ctx.call_script(ctx.scripts.cpp_project_switch or "", "list"),
  })
  
  -- Code navigation
  table.insert(items, {
    type = "item",
    name = "menu.cpp.find_symbol",
    icon = "󰦨",
    label = "Find Symbol",
    action = "osascript -e 'tell application \"System Events\" to keystroke \"t\" using {command down, option down}'",
  })
  
  table.insert(items, {
    type = "item",
    name = "menu.cpp.goto_definition",
    icon = "󰁔",
    label = "Go to Definition",
    action = "osascript -e 'tell application \"System Events\" to keystroke \"d\" using {command down}'",
  })
  
  -- Debugger
  table.insert(items, { type = "separator", name = "menu.cpp.sep2" })
  table.insert(items, {
    type = "item",
    name = "menu.cpp.debug",
    icon = "󰆍",
    label = "Start Debugger",
    action = "osascript -e 'tell application \"System Events\" to keystroke \"d\" using {command down, shift down}'",
  })
  
  -- Google-specific: Bazel
  if build_system == "bazel" then
    table.insert(items, { type = "separator", name = "menu.cpp.sep3" })
    table.insert(items, {
      type = "item",
      name = "menu.cpp.bazel_query",
      icon = "󰆍",
      label = "Bazel Query",
      action = string.format("osascript -e 'tell application \"Terminal\" to do script \"cd %s/%s && bazel query //...\"'", project_path, current_project),
    })
    table.insert(items, {
      type = "item",
      name = "menu.cpp.bazel_info",
      icon = "󰆍",
      label = "Bazel Info",
      action = string.format("osascript -e 'tell application \"Terminal\" to do script \"cd %s/%s && bazel info\"'", project_path, current_project),
    })
  end
  
  return items
end

-- Create build status widget
function cpp_dev.create_build_widget(sbar, factory, theme, state_data)
  if not cpp_dev.enabled then
    return nil
  end
  
  local widget = factory.create("cpp_build_status", {
    icon = "󰨞",
    label = "…",
    update_freq = 5,
    script = os.getenv("HOME") .. "/.config/sketchybar/plugins/cpp_build_status.sh",
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

return cpp_dev

