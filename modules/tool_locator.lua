local locator = {}

local HOME = os.getenv("HOME") or ""

local path_cache = {}

local function option_value(opts, key)
  if type(opts) ~= "table" then
    return nil
  end
  if type(opts.paths) == "table" then
    local path_value = opts.paths[key]
    if type(path_value) == "string" and path_value ~= "" then
      return path_value
    end
  end
  local direct_value = opts[key]
  if type(direct_value) == "string" and direct_value ~= "" then
    return direct_value
  end
  return nil
end

function locator.expand_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  end
  return path
end

function locator.path_exists(path, want_dir)
  path = locator.expand_path(path) or path
  if not path or path == "" then
    return false
  end

  local cache_key = (want_dir and "d:" or "f:") .. path
  if path_cache[cache_key] ~= nil then
    return path_cache[cache_key]
  end

  local result
  if want_dir then
    local ok = os.execute(string.format("test -d %q", path))
    result = ok == true or ok == 0
  else
    local file = io.open(path, "r")
    if file then
      file:close()
      result = true
    else
      result = false
    end
  end

  path_cache[cache_key] = result
  return result
end

function locator.path_is_executable(path)
  path = locator.expand_path(path) or path
  if not path or path == "" then
    return false
  end

  local cache_key = "x:" .. path
  if path_cache[cache_key] ~= nil then
    return path_cache[cache_key]
  end

  local file = io.open(path, "r")
  if not file then
    path_cache[cache_key] = false
    return false
  end
  file:close()

  local ok = os.execute(string.format("test -x %q", path))
  local result = ok == true or ok == 0
  path_cache[cache_key] = result
  return result
end

function locator.command_path(command)
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

function locator.resolve_path(candidates, want_dir)
  local fallback = nil
  local max_index = 0

  for index in pairs(candidates or {}) do
    if type(index) == "number" and index > max_index then
      max_index = index
    end
  end

  for i = 1, max_index do
    local candidate = locator.expand_path(candidates[i])
    if candidate and candidate ~= "" then
      fallback = fallback or candidate
      if locator.path_exists(candidate, want_dir) then
        return candidate, true
      end
    end
  end

  return fallback, false
end

function locator.resolve_executable_path(candidates)
  local fallback = nil
  local max_index = 0

  for index in pairs(candidates or {}) do
    if type(index) == "number" and index > max_index then
      max_index = index
    end
  end

  for i = 1, max_index do
    local candidate = locator.expand_path(candidates[i])
    if candidate and candidate ~= "" then
      fallback = fallback or candidate
      if locator.path_is_executable(candidate) then
        return candidate, true
      end
    end
  end

  return fallback, false
end

function locator.resolve_config_dir(opts)
  local config_dir = option_value(opts, "config_dir")
    or os.getenv("BARISTA_CONFIG_DIR")
    or (HOME .. "/.config/sketchybar")
  return locator.expand_path(config_dir) or config_dir
end

function locator.load_state(config_dir)
  local ok_json, json = pcall(require, "json")
  if not ok_json then
    return nil
  end

  local file = io.open((config_dir or locator.resolve_config_dir()) .. "/state.json", "r")
  if not file then
    return nil
  end

  local contents = file:read("*a")
  file:close()

  local ok_decode, data = pcall(json.decode, contents)
  if not ok_decode or type(data) ~= "table" then
    return nil
  end
  return data
end

function locator.resolve_code_dir(opts)
  local state_paths = type(opts) == "table"
    and type(opts.state) == "table"
    and type(opts.state.paths) == "table"
    and opts.state.paths
    or nil

  local candidate = option_value(opts, "code_dir")
    or os.getenv("BARISTA_CODE_DIR")
    or (state_paths and (state_paths.code_dir or state_paths.code))
    or (HOME .. "/src")

  candidate = locator.expand_path(candidate) or (HOME .. "/src")
  local fallback = HOME .. "/src"

  if candidate:match("/Code/?$") and locator.path_exists(fallback, true) then
    return fallback
  end
  if not locator.path_exists(candidate, true) and locator.path_exists(fallback, true) then
    return fallback
  end
  if not locator.path_exists(candidate .. "/lab", true) and locator.path_exists(fallback .. "/lab", true) then
    return fallback
  end
  return candidate
end

function locator.resolve_yaze_dir(opts)
  local code_dir = locator.resolve_code_dir(opts)
  return locator.resolve_path({
    option_value(opts, "yaze"),
    os.getenv("BARISTA_YAZE_DIR"),
    code_dir .. "/yaze",
    code_dir .. "/hobby/yaze",
  }, true)
end

function locator.resolve_afs_root(opts)
  local code_dir = locator.resolve_code_dir(opts)
  return locator.resolve_path({
    option_value(opts, "afs"),
    os.getenv("AFS_ROOT"),
    code_dir .. "/lab/afs",
    code_dir .. "/afs",
  }, true)
end

function locator.resolve_afs_studio_root(opts, afs_root)
  local code_dir = locator.resolve_code_dir(opts)
  return locator.resolve_path({
    option_value(opts, "afs_studio"),
    os.getenv("AFS_STUDIO_ROOT"),
    afs_root and (afs_root .. "/apps/studio") or nil,
    code_dir .. "/lab/afs_suite",
    code_dir .. "/lab/afs/apps/studio",
    code_dir .. "/lab/afs_studio",
    code_dir .. "/afs/apps/studio",
    code_dir .. "/afs_studio",
  }, true)
end

function locator.resolve_afs_browser_app(opts)
  local code_dir = locator.resolve_code_dir(opts)
  return locator.resolve_path({
    option_value(opts, "afs_browser_app"),
    os.getenv("AFS_BROWSER_APP"),
    code_dir .. "/lab/afs_suite/build/apps/browser/afs-browser.app",
    code_dir .. "/lab/afs_suite/build_ai/apps/browser/afs-browser.app",
    code_dir .. "/lab/afs_suite/build/apps/browser/Debug/afs-browser.app",
    code_dir .. "/lab/afs_suite/build/apps/browser/Release/afs-browser.app",
  }, true)
end

function locator.resolve_stemforge_app(opts)
  local code_dir = locator.resolve_code_dir(opts)
  return locator.resolve_path({
    option_value(opts, "stemforge_app"),
    os.getenv("STEMFORGE_APP"),
    code_dir .. "/tools/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app",
    code_dir .. "/tools/stemforge/build_ai/StemForge_artefacts/Release/Standalone/StemForge.app",
    code_dir .. "/tools/stemforge/build/StemForge_artefacts/Debug/Standalone/StemForge.app",
    code_dir .. "/lab/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app",
    code_dir .. "/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app",
    HOME .. "/Applications/StemForge.app",
    "/Applications/StemForge.app",
  }, true)
end

function locator.resolve_stem_sampler_app(opts)
  local code_dir = locator.resolve_code_dir(opts)
  return locator.resolve_path({
    option_value(opts, "stem_sampler_app"),
    os.getenv("STEM_SAMPLER_APP"),
    code_dir .. "/tools/stem-sampler/StemSampler.app",
    code_dir .. "/tools/stemsampler/StemSampler.app",
    code_dir .. "/tools/stem_sampler/StemSampler.app",
    HOME .. "/Applications/StemSampler.app",
    "/Applications/StemSampler.app",
  }, true)
end

function locator.resolve_yaze_app(opts)
  local code_dir = locator.resolve_code_dir(opts)
  local yaze_dir = os.getenv("BARISTA_YAZE_DIR")
    or option_value(opts, "yaze")
    or select(1, locator.resolve_yaze_dir(opts))
  local nightly_prefix = os.getenv("BARISTA_YAZE_NIGHTLY_PREFIX")
    or os.getenv("YAZE_NIGHTLY_PREFIX")
    or (HOME .. "/.local/yaze/nightly")

  return locator.resolve_path({
    option_value(opts, "yaze_app"),
    os.getenv("BARISTA_YAZE_APP") or os.getenv("YAZE_APP"),
    nightly_prefix .. "/current/yaze.app",
    nightly_prefix .. "/yaze.app",
    HOME .. "/Applications/Yaze Nightly.app",
    HOME .. "/Applications/yaze nightly.app",
    HOME .. "/applications/Yaze Nightly.app",
    HOME .. "/applications/yaze nightly.app",
    "/Applications/Yaze Nightly.app",
    "/Applications/yaze nightly.app",
    yaze_dir and (yaze_dir .. "/build_ai/bin/Debug/yaze.app") or nil,
    yaze_dir and (yaze_dir .. "/build_ai/bin/Release/yaze.app") or nil,
    yaze_dir and (yaze_dir .. "/build_ai/bin/yaze.app") or nil,
    yaze_dir and (yaze_dir .. "/build/bin/Release/yaze.app") or nil,
    yaze_dir and (yaze_dir .. "/build/bin/Debug/yaze.app") or nil,
    yaze_dir and (yaze_dir .. "/build/bin/yaze.app") or nil,
    code_dir .. "/hobby/yaze/build_ai/bin/Debug/yaze.app",
    code_dir .. "/hobby/yaze/build_ai/bin/Release/yaze.app",
    code_dir .. "/hobby/yaze/build_ai/bin/yaze.app",
    code_dir .. "/hobby/yaze/build/bin/Release/yaze.app",
    code_dir .. "/hobby/yaze/build/bin/Debug/yaze.app",
    code_dir .. "/hobby/yaze/build/bin/yaze.app",
    code_dir .. "/yaze/build_ai/bin/Debug/yaze.app",
    code_dir .. "/yaze/build_ai/bin/Release/yaze.app",
    code_dir .. "/yaze/build_ai/bin/yaze.app",
    code_dir .. "/yaze/build/bin/Release/yaze.app",
    code_dir .. "/yaze/build/bin/Debug/yaze.app",
    code_dir .. "/yaze/build/bin/yaze.app",
  }, true)
end

function locator.resolve_yaze_launcher()
  local override = os.getenv("BARISTA_YAZE_LAUNCHER") or os.getenv("YAZE_LAUNCHER")
  if override and override ~= "" then
    override = locator.expand_path(override) or override
    if locator.path_is_executable(override) then
      return override, true
    end
    local resolved = locator.command_path(override)
    if resolved then
      return resolved, true
    end
  end

  local resolved = locator.command_path("yaze-nightly")
  if resolved then
    return resolved, true
  end

  return nil, false
end

function locator.resolve_sys_manual_binary(opts)
  local code_dir = locator.resolve_code_dir(opts)
  return locator.resolve_executable_path({
    code_dir .. "/lab/sys_manual/build/sys_manual",
    code_dir .. "/sys_manual/build/sys_manual",
    "/Applications/sys_manual.app/Contents/MacOS/sys_manual",
  })
end

function locator.resolve_help_center_bin(config_dir)
  return locator.resolve_executable_path({
    config_dir .. "/gui/bin/help_center",
    config_dir .. "/build/bin/help_center",
  })
end

function locator.resolve_icon_browser_bin(config_dir)
  return locator.resolve_executable_path({
    config_dir .. "/gui/bin/icon_browser",
    config_dir .. "/build/bin/icon_browser",
  })
end

function locator.resolve_mesen_run(opts)
  local override = option_value(opts, "mesen_run")
    or os.getenv("MESEN_RUN")
    or os.getenv("MESEN_RUN_BIN")
  if override and override ~= "" then
    override = locator.expand_path(override) or override
    if locator.path_is_executable(override) then
      return override, true
    end
    local resolved = locator.command_path(override)
    if resolved then
      return resolved, true
    end
  end

  local resolved = locator.command_path("mesen-run")
  if resolved then
    return resolved, true
  end

  local code_dir = locator.resolve_code_dir(opts)
  return locator.resolve_executable_path({
    code_dir .. "/config/dotfiles/bin/mesen-run",
    HOME .. "/src/config/dotfiles/bin/mesen-run",
    HOME .. "/bin/mesen-run",
    HOME .. "/.local/bin/mesen-run",
  })
end

function locator.resolve_oracle_agent_manager(opts)
  local code_dir = locator.resolve_code_dir(opts)
  return locator.resolve_executable_path({
    code_dir .. "/hobby/oracle-agent-manager/build/oracle_manager_gui",
    code_dir .. "/hobby/oracle-agent-manager/oracle_manager_gui",
    code_dir .. "/hobby/oracle-agent-manager/build/oracle_hub",
    code_dir .. "/hobby/oracle-agent-manager/oracle_hub",
  })
end

function locator.resolve_afs_studio_binary(studio_root)
  return locator.resolve_path({
    studio_root and (studio_root .. "/build_ai/apps/studio/afs-studio.app") or nil,
    studio_root and (studio_root .. "/build_ai/apps/studio/afs-studio") or nil,
    studio_root and (studio_root .. "/build/apps/studio/afs-studio.app") or nil,
    studio_root and (studio_root .. "/build/apps/studio/afs-studio") or nil,
    studio_root and (studio_root .. "/build/afs_studio") or nil,
    studio_root and (studio_root .. "/build/bin/afs_studio") or nil,
  }, false)
end

function locator.resolve_afs_studio_launcher(opts)
  local code_dir = locator.resolve_code_dir(opts)
  return locator.resolve_executable_path({
    option_value(opts, "afs_studio_launcher"),
    os.getenv("AFS_STUDIO_LAUNCHER"),
    code_dir .. "/lab/afs-scawful/scripts/afs/utils/afs-studio",
    code_dir .. "/afs-scawful/scripts/afs/utils/afs-studio",
  })
end

function locator.resolve_afs_labeler_binary(studio_root)
  return locator.resolve_path({
    studio_root and (studio_root .. "/build_ai/apps/studio/afs-labeler.app") or nil,
    studio_root and (studio_root .. "/build_ai/apps/studio/afs-labeler") or nil,
    studio_root and (studio_root .. "/build/apps/studio/afs-labeler.app") or nil,
    studio_root and (studio_root .. "/build/apps/studio/afs-labeler") or nil,
    studio_root and (studio_root .. "/build/afs_labeler") or nil,
    studio_root and (studio_root .. "/build/bin/afs_labeler") or nil,
  }, false)
end

function locator.afs_studio_layout(studio_root)
  if not studio_root or studio_root == "" then
    return "legacy"
  end
  if locator.path_exists(studio_root .. "/apps/studio", true)
      or locator.path_exists(studio_root .. "/build_ai/apps/studio", true)
      or locator.path_exists(studio_root .. "/build/apps/studio", true) then
    return "suite"
  end
  return "legacy"
end

function locator.afs_build_dir(studio_root)
  if locator.path_exists(studio_root .. "/build_ai", true) then
    return "build_ai"
  end
  if locator.path_exists(studio_root .. "/build", true) then
    return "build"
  end
  return "build"
end

return locator
