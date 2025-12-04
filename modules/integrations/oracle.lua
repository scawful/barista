-- Oracle of Secrets Integration Module
-- Integration with the Oracle of Secrets ROM hack

local oracle = {}

local HOME = os.getenv("HOME")
local CODE_DIR = HOME .. "/Code"
local ORACLE_DIR = CODE_DIR .. "/Oracle-of-Secrets"

-- Configuration
oracle.config = {
  repo_path = ORACLE_DIR,
  run_script = ORACLE_DIR .. "/run.sh",
  build_script = ORACLE_DIR .. "/build.sh",
  rom_path = ORACLE_DIR .. "/Roms/oos91x.sfc",
  docs_dir = ORACLE_DIR .. "/Docs",
  todo_file = ORACLE_DIR .. "/oracle.org",
}

-- Check if repo exists
function oracle.repo_exists()
  local handle = io.popen(string.format("test -d %q && echo 1 || echo 0", oracle.config.repo_path))
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1")
end

-- Check if ROM exists (built)
function oracle.rom_exists()
  local handle = io.popen(string.format("test -f %q && echo 1 || echo 0", oracle.config.rom_path))
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1")
end

-- Launch ROM
function oracle.launch()
  if not oracle.rom_exists() then
    return false, "ROM not found. Run build first."
  end

  local cmd = string.format("open %q", oracle.config.rom_path)
  os.execute(cmd)
  return true
end

-- Run Build (Fast)
function oracle.run_build()
  if not oracle.repo_exists() then
    return false, "Repo not found"
  end

  local cmd = string.format(
    "osascript -e 'tell app \"Terminal\" to do script \"cd %s && ./run.sh\"'",
    oracle.config.repo_path
  )
  os.execute(cmd)
  return true
end

-- Full Build
function oracle.full_build()
  if not oracle.repo_exists() then
    return false, "Repo not found"
  end

  local cmd = string.format(
    "osascript -e 'tell app \"Terminal\" to do script \"cd %s && ./build.sh\"'",
    oracle.config.repo_path
  )
  os.execute(cmd)
  return true
end

-- Create menu items
function oracle.create_menu_items(ctx)
  local items = {}
  local rom_exists = oracle.rom_exists()
  local status_icon = rom_exists and "󰯙" or "⚠️"
  local status_label = rom_exists and "Launch Oracle" or "ROM Missing"

  -- Header
  table.insert(items, {
    type = "header",
    name = "oracle.header",
    label = "Oracle of Secrets"
  })

  -- Launch
  if rom_exists then
    table.insert(items, {
      type = "item",
      name = "oracle.launch",
      icon = "󰯙",
      label = "Launch ROM (oos91x)",
      action = string.format("open %q", oracle.config.rom_path),
    })
  end

  -- Build Actions
  table.insert(items, {
    type = "item",
    name = "oracle.run",
    icon = "󰑐",
    label = "Fast Build & Run",
    action = string.format(
      "osascript -e 'tell app \"Terminal\" to do script \"cd %s && ./run.sh\"'",
      oracle.config.repo_path
    ),
  })

  table.insert(items, {
    type = "item",
    name = "oracle.build",
    icon = "󰓅",
    label = "Full Clean Build",
    action = string.format(
      "osascript -e 'tell app \"Terminal\" to do script \"cd %s && ./build.sh\"'",
      oracle.config.repo_path
    ),
  })

  table.insert(items, { type = "separator", name = "oracle.sep1" })

  -- Docs
  table.insert(items, {
    type = "item",
    name = "oracle.todo",
    icon = "󰃤",
    label = "Open Tasks (oracle.org)",
    action = ctx.open_path(oracle.config.todo_file),
  })

  table.insert(items, {
    type = "item",
    name = "oracle.repo",
    icon = "󰋜",
    label = "Open Repository",
    action = ctx.open_path(oracle.config.repo_path),
  })

  return items
end

return oracle
