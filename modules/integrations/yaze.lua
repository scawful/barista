-- Yaze Editor Integration Module
-- Integration with the Yaze ROM hacking toolkit

local yaze = {}

local HOME = os.getenv("HOME")
local CODE_DIR = os.getenv("BARISTA_CODE_DIR") or (HOME .. "/src")
local YAZE_DIR = CODE_DIR .. "/yaze"

-- Configuration
yaze.config = {
  repo_path = YAZE_DIR,
  build_dir = YAZE_DIR .. "/build/bin",
  binary_path = YAZE_DIR .. "/build/bin/yaze.app/Contents/MacOS/yaze",
  app_bundle = YAZE_DIR .. "/build/bin/yaze.app",
  rom_dir = YAZE_DIR .. "/roms",
  docs_dir = CODE_DIR .. "/docs/workflow",
  rom_workflow_doc = CODE_DIR .. "/docs/workflow/rom-hacking.org",
}

-- Check if Yaze is installed
function yaze.is_installed()
  local file = io.open(yaze.config.binary_path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

-- Check if Yaze repo exists
function yaze.repo_exists()
  local handle = io.popen(string.format("test -d %q && echo 1 || echo 0", yaze.config.repo_path))
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1")
end

-- Get Yaze build status
function yaze.get_build_status()
  if not yaze.repo_exists() then
    return "not_found"
  end

  if not yaze.is_installed() then
    return "not_built"
  end

  -- Check if binary is recent
  local handle = io.popen(string.format(
    "find %q -name 'yaze' -mtime -1 2>/dev/null | wc -l",
    yaze.config.build_dir
  ))
  if handle then
    local result = handle:read("*a")
    handle:close()
    if result and tonumber(result) and tonumber(result) > 0 then
      return "recent"
    end
  end

  return "ready"
end

-- Launch Yaze
function yaze.launch()
  if not yaze.is_installed() then
    return false, "Yaze is not built. Run 'make' in " .. yaze.config.repo_path
  end

  local cmd = string.format("open -a %q", yaze.config.app_bundle)
  os.execute(cmd)
  return true
end

-- Launch Yaze with a specific ROM
function yaze.launch_with_rom(rom_path)
  if not yaze.is_installed() then
    return false, "Yaze is not built"
  end

  local cmd = string.format("open -a %q %q", yaze.config.app_bundle, rom_path)
  os.execute(cmd)
  return true
end

-- Build Yaze
function yaze.build()
  if not yaze.repo_exists() then
    return false, "Yaze repository not found at " .. yaze.config.repo_path
  end

  local cmd = string.format(
    "cd %q && make -j$(sysctl -n hw.ncpu) 2>&1",
    yaze.config.repo_path
  )
  local handle = io.popen(cmd)
  if not handle then
    return false, "Failed to start build"
  end

  local output = handle:read("*a")
  local success = handle:close()

  return success, output
end

-- Get recent ROM files
function yaze.get_recent_roms(max_count)
  max_count = max_count or 5

  if not yaze.repo_exists() then
    return {}
  end

  local cmd = string.format(
    "find %q -type f \\( -name '*.smc' -o -name '*.sfc' -o -name '*.gba' -o -name '*.gb' -o -name '*.nes' \\) -exec stat -f '%%m %%N' {} \\; 2>/dev/null | sort -rn | head -n %d",
    yaze.config.rom_dir,
    max_count
  )

  local handle = io.popen(cmd)
  if not handle then
    return {}
  end

  local roms = {}
  for line in handle:lines() do
    local timestamp, path = line:match("^(%d+)%s+(.+)$")
    if path then
      local name = path:match("([^/]+)$")
      table.insert(roms, {
        path = path,
        name = name,
        timestamp = tonumber(timestamp) or 0,
      })
    end
  end
  handle:close()

  return roms
end

-- Open ROM workflow documentation
function yaze.open_docs()
  local cmd = string.format("open %q", yaze.config.rom_workflow_doc)
  os.execute(cmd)
end

-- Open Yaze repository in editor
function yaze.open_repo(editor)
  editor = editor or "Visual Studio Code"
  local cmd = string.format("open -a %q %q", editor, yaze.config.repo_path)
  os.execute(cmd)
end

-- Get Yaze git status (for development)
function yaze.get_git_status()
  if not yaze.repo_exists() then
    return nil
  end

  local cmd = string.format(
    "cd %q && git status --porcelain 2>/dev/null | wc -l",
    yaze.config.repo_path
  )
  local handle = io.popen(cmd)
  if not handle then
    return nil
  end

  local result = handle:read("*a")
  handle:close()

  local changes = tonumber(result)
  if changes then
    return {
      has_changes = changes > 0,
      change_count = changes,
    }
  end

  return nil
end

-- Get current branch
function yaze.get_git_branch()
  if not yaze.repo_exists() then
    return nil
  end

  local cmd = string.format(
    "cd %q && git branch --show-current 2>/dev/null",
    yaze.config.repo_path
  )
  local handle = io.popen(cmd)
  if not handle then
    return nil
  end

  local branch = handle:read("*a")
  handle:close()

  if branch then
    return branch:gsub("%s+$", "")
  end

  return nil
end

-- Create menu items for Yaze integration
function yaze.create_menu_items(ctx)
  local items = {}

  local build_status = yaze.get_build_status()
  local status_icon = "󰯙"
  local status_label = "Launch Yaze"

  if build_status == "not_found" then
    status_icon = ""
    status_label = "Yaze Not Found"
  elseif build_status == "not_built" then
    status_icon = ""
    status_label = "Build Yaze First"
  elseif build_status == "recent" then
    status_icon = "󰯙"
    status_label = "Launch Yaze ✨"
  end

  -- Launch Yaze
  table.insert(items, {
    type = "item",
    name = "yaze.launch",
    icon = status_icon,
    label = status_label,
    action = string.format("open -a %q", yaze.config.app_bundle),
  })

  -- Recent ROMs submenu
  local recent_roms = yaze.get_recent_roms(5)
  if #recent_roms > 0 then
    local rom_items = {}
    for i, rom in ipairs(recent_roms) do
      table.insert(rom_items, {
        type = "item",
        name = "yaze.rom." .. i,
        icon = "󰯙",
        label = rom.name,
        action = string.format("open -a %q %q", yaze.config.app_bundle, rom.path),
      })
    end

    table.insert(items, {
      type = "submenu",
      name = "yaze.recent_roms",
      icon = "󰋜",
      label = "Recent ROMs",
      items = rom_items,
    })
  end

  -- Open repo
  table.insert(items, {
    type = "item",
    name = "yaze.repo",
    icon = "󰋜",
    label = "Open Yaze Repo",
    action = ctx.open_path(yaze.config.repo_path),
  })

  -- Build Yaze
  if build_status ~= "not_found" then
    table.insert(items, {
      type = "item",
      name = "yaze.build",
      icon = "",
      label = "Build Yaze",
      action = string.format(
        "osascript -e 'tell app \"Terminal\" to do script \"cd %s && make -j$(sysctl -n hw.ncpu)\"'",
        yaze.config.repo_path
      ),
    })
  end

  -- Documentation
  table.insert(items, {
    type = "item",
    name = "yaze.docs",
    icon = "󰊕",
    label = "ROM Workflow Docs",
    action = ctx.open_path(yaze.config.rom_workflow_doc),
  })

  return items
end

-- Get status text for display
function yaze.get_status_text()
  local build_status = yaze.get_build_status()

  if build_status == "not_found" then
    return "Not Found"
  elseif build_status == "not_built" then
    return "Not Built"
  elseif build_status == "recent" then
    return "Ready ✨"
  else
    return "Ready"
  end
end

-- Get icon for status
function yaze.get_status_icon()
  local build_status = yaze.get_build_status()

  if build_status == "not_found" or build_status == "not_built" then
    return ""
  else
    return "󰯙"
  end
end

return yaze
