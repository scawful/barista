-- Yaze Editor Integration Module
-- Integration with the Yaze ROM hacking toolkit

local yaze = {}

local HOME = os.getenv("HOME")
local CODE_DIR = os.getenv("BARISTA_CODE_DIR") or (HOME .. "/src")
local YAZE_DIR = os.getenv("BARISTA_YAZE_DIR") or (CODE_DIR .. "/yaze")

-- Helper to check file existence
local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function expand_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  end
  return path
end

local function path_is_executable(path)
  if not path or path == "" then
    return false
  end
  local handle = io.popen(string.format("test -x %q && printf 1 || printf 0", path))
  if not handle then
    return false
  end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1") ~= nil
end

local function command_path(command)
  if not command or command == "" then
    return nil
  end
  local handle = io.popen(string.format("command -v %q 2>/dev/null", command))
  if not handle then
    return nil
  end
  local result = handle:read("*a") or ""
  handle:close()
  result = result:gsub("%s+$", "")
  if result == "" then
    return nil
  end
  return result
end

local function shell_quote(value)
  return string.format("%q", tostring(value))
end

local function resolve_nightly_prefix()
  return os.getenv("BARISTA_YAZE_NIGHTLY_PREFIX")
    or os.getenv("YAZE_NIGHTLY_PREFIX")
    or (HOME .. "/.local/yaze/nightly")
end

local function resolve_external_yaze_app()
  local nightly_prefix = resolve_nightly_prefix()
  local candidates = {
    os.getenv("BARISTA_YAZE_APP"),
    os.getenv("YAZE_APP"),
    nightly_prefix and (nightly_prefix .. "/current/yaze.app") or nil,
    nightly_prefix and (nightly_prefix .. "/yaze.app") or nil,
    HOME .. "/Applications/Yaze Nightly.app",
    HOME .. "/Applications/yaze nightly.app",
    HOME .. "/applications/Yaze Nightly.app",
    HOME .. "/applications/yaze nightly.app",
    "/Applications/Yaze Nightly.app",
    "/Applications/yaze nightly.app",
  }
  for _, candidate in ipairs(candidates) do
    if candidate and candidate ~= "" then
      candidate = expand_path(candidate)
      local binary = candidate .. "/Contents/MacOS/yaze"
      if file_exists(binary) then
        return candidate
      end
    end
  end
  return nil
end

local function resolve_yaze_launcher()
  local override = os.getenv("BARISTA_YAZE_LAUNCHER") or os.getenv("YAZE_LAUNCHER")
  if override and override ~= "" then
    local expanded = expand_path(override)
    if expanded and path_is_executable(expanded) then
      return expanded
    end
    local resolved = command_path(override)
    if resolved then
      return resolved
    end
  end

  local resolved = command_path("yaze-nightly")
  if resolved then
    return resolved
  end

  return nil
end

-- Resolve Yaze build directory (prefer build_ai)
local function resolve_yaze_paths(repo_path)
  local root = repo_path or YAZE_DIR
  local candidates = {
    root .. "/build_ai/bin/Debug",
    root .. "/build_ai/bin/Release",
    root .. "/build_ai/bin",
    root .. "/build/bin/Release",
    root .. "/build/bin/Debug",
    root .. "/build/bin",
  }

  for _, candidate in ipairs(candidates) do
    if file_exists(candidate .. "/yaze.app/Contents/MacOS/yaze") then
      return candidate
    end
  end

  return root .. "/build/bin"
end

local function build_config(repo_path, docs_dir, rom_workflow_doc, launcher_override)
  local root = repo_path or YAZE_DIR
  local build_dir = resolve_yaze_paths(root)
  local external_app = resolve_external_yaze_app()
  local launcher = launcher_override or resolve_yaze_launcher()
  local app_bundle = external_app or (build_dir .. "/yaze.app")
  return {
    repo_path = root,
    build_dir = build_dir,
    binary_path = app_bundle .. "/Contents/MacOS/yaze",
    app_bundle = app_bundle,
    launch_cmd = launcher,
    rom_dir = root .. "/roms",
    docs_dir = docs_dir or (CODE_DIR .. "/docs/workflow"),
    rom_workflow_doc = rom_workflow_doc or (CODE_DIR .. "/docs/workflow/rom-hacking.org"),
  }
end

-- Configuration
yaze.config = build_config(YAZE_DIR)

-- Allow runtime overrides (e.g., profile paths)
function yaze.configure(opts)
  opts = opts or {}
  local repo_path = opts.repo_path or opts.yaze_dir or opts.repo or yaze.config.repo_path
  local docs_dir = opts.docs_dir or yaze.config.docs_dir
  local rom_workflow_doc = opts.rom_workflow_doc or opts.rom_doc or yaze.config.rom_workflow_doc
  local launcher = opts.launcher or opts.launch_cmd
  yaze.config = build_config(repo_path, docs_dir, rom_workflow_doc, launcher)
  return yaze.config
end

-- Check if Yaze is installed
function yaze.is_installed()
  if yaze.config.launch_cmd and yaze.config.launch_cmd ~= "" then
    return true
  end
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
    if yaze.is_installed() then
      return "external"
    end
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

local function launch_action(rom_path)
  if yaze.config.launch_cmd and yaze.config.launch_cmd ~= "" then
    if rom_path then
      return string.format("%s %s", shell_quote(yaze.config.launch_cmd), shell_quote(rom_path))
    end
    return shell_quote(yaze.config.launch_cmd)
  end

  if rom_path then
    return string.format("open -a %q %q", yaze.config.app_bundle, rom_path)
  end
  return string.format("open -a %q", yaze.config.app_bundle)
end

-- Launch Yaze
function yaze.launch()
  if not yaze.is_installed() then
    return false, "Yaze is not built. Run 'make' in " .. yaze.config.repo_path
  end

  local cmd = launch_action()
  os.execute(cmd)
  return true
end

-- Launch Yaze with a specific ROM
function yaze.launch_with_rom(rom_path)
  if not yaze.is_installed() then
    return false, "Yaze is not built"
  end

  local cmd = launch_action(rom_path)
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
  elseif build_status == "external" then
    status_icon = "󰯙"
    status_label = "Launch Yaze (External)"
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
    action = launch_action(),
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
        action = launch_action(rom.path),
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
  elseif build_status == "external" then
    return "External"
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
