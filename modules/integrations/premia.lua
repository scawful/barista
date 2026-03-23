-- Premia Integration Module
-- Financial market data platform: API backend, iOS app, desktop client

local premia = {}

local HOME = os.getenv("HOME")
local CODE_DIR = os.getenv("BARISTA_CODE_DIR") or (HOME .. "/src")
local PREMIA_DIR = CODE_DIR .. "/lab/premia"

-- Configuration
premia.config = {
  repo_path      = PREMIA_DIR,
  build_dir      = PREMIA_DIR .. "/build-arch-next",
  api_binary     = PREMIA_DIR .. "/build-arch-next/bin/premia_api",
  desktop_binary = PREMIA_DIR .. "/build-arch-next/bin/premia",
  contract       = PREMIA_DIR .. "/contracts/openapi/premia-v1.yaml",
  status_doc     = PREMIA_DIR .. "/STATUS.md",
  roadmap        = PREMIA_DIR .. "/ROADMAP.md",
  mobile_dir     = PREMIA_DIR .. "/apps/mobile-ios",
}

-- Allow runtime overrides
function premia.configure(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    premia.config[k] = v
  end
  return premia.config
end

-- Check if repo exists
function premia.repo_exists()
  local handle = io.popen(string.format("test -d %q && echo 1 || echo 0", premia.config.repo_path))
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1")
end

-- Check if API binary is built
function premia.api_built()
  local handle = io.popen(string.format("test -f %q && echo 1 || echo 0", premia.config.api_binary))
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1")
end

-- Check if desktop binary is built
function premia.desktop_built()
  local handle = io.popen(string.format("test -f %q && echo 1 || echo 0", premia.config.desktop_binary))
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1")
end

-- Create menu items for Premia integration
function premia.create_menu_items(ctx)
  local items = {}

  -- Open repository
  table.insert(items, {
    type   = "item",
    name   = "premia.repo",
    icon   = "",
    label  = "Open Premia Repo",
    action = ctx.open_path(premia.config.repo_path),
  })

  -- Launch desktop if built
  if premia.desktop_built() then
    table.insert(items, {
      type   = "item",
      name   = "premia.launch",
      icon   = "",
      label  = "Launch Premia Desktop",
      action = string.format("open %q", premia.config.desktop_binary),
    })
  end

  table.insert(items, { type = "separator", name = "premia.sep1" })

  -- Build API server
  table.insert(items, {
    type   = "item",
    name   = "premia.build.api",
    icon   = "",
    label  = "Build API Server",
    action = string.format(
      "osascript -e 'tell app \"Terminal\" to do script \"cd %s && cmake -S . -B build-arch-next && cmake --build build-arch-next --target premia_api -j$(sysctl -n hw.ncpu)\"'",
      premia.config.repo_path
    ),
  })

  -- Build desktop
  table.insert(items, {
    type   = "item",
    name   = "premia.build.desktop",
    icon   = "",
    label  = "Build Desktop",
    action = string.format(
      "osascript -e 'tell app \"Terminal\" to do script \"cd %s && cmake -S . -B build-arch-next && cmake --build build-arch-next --target premia -j$(sysctl -n hw.ncpu)\"'",
      premia.config.repo_path
    ),
  })

  table.insert(items, { type = "separator", name = "premia.sep2" })

  -- View status doc
  table.insert(items, {
    type   = "item",
    name   = "premia.status",
    icon   = "󰈙",
    label  = "View STATUS.md",
    action = ctx.open_path(premia.config.status_doc),
  })

  -- View roadmap
  table.insert(items, {
    type   = "item",
    name   = "premia.roadmap",
    icon   = "󰃤",
    label  = "Roadmap",
    action = ctx.open_path(premia.config.roadmap),
  })

  -- OpenAPI contract
  table.insert(items, {
    type   = "item",
    name   = "premia.contract",
    icon   = "󰊕",
    label  = "OpenAPI Contract",
    action = ctx.open_path(premia.config.contract),
  })

  return items
end

-- Status text for bar display
function premia.get_status_text()
  if not premia.repo_exists() then return "Not Found" end
  if premia.api_built() then return "Ready" end
  return "Not Built"
end

-- Icon for bar display
function premia.get_status_icon()
  if not premia.repo_exists() or not premia.api_built() then
    return ""
  end
  return ""
end

return premia
