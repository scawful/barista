-- Emacs Integration Module
-- Integration with Emacs and org-mode workflows

local emacs = {}

local HOME = os.getenv("HOME")
local CODE_DIR = HOME .. "/Code"
local EMACS_DIR = CODE_DIR .. "/lisp"
local DOCS_DIR = CODE_DIR .. "/docs/workflow"

-- Configuration
emacs.config = {
  emacs_dir = EMACS_DIR,
  docs_dir = DOCS_DIR,
  tasks_file = DOCS_DIR .. "/tasks.org",
  rom_workflow = DOCS_DIR .. "/rom-hacking.org",
  dev_workflow = DOCS_DIR .. "/development.org",
  workspace_name = "Emacs", -- Default workspace/space name for Emacs
}

-- Check if Emacs is installed
function emacs.is_installed()
  local handle = io.popen("command -v emacs 2>/dev/null")
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result ~= ""
end

-- Check if Emacs is running
function emacs.is_running()
  local handle = io.popen("pgrep -x Emacs 2>/dev/null")
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result ~= ""
end

-- Launch Emacs
function emacs.launch()
  os.execute("open -a Emacs &")
  return true
end

-- Launch Emacs with a specific file
function emacs.open_file(file_path)
  local cmd = string.format("open -a Emacs %q &", file_path)
  os.execute(cmd)
  return true
end

-- Launch emacsclient (if server is running)
function emacs.emacsclient(file_path)
  if file_path then
    local cmd = string.format("emacsclient -n %q 2>/dev/null || open -a Emacs %q", file_path, file_path)
    os.execute(cmd)
  else
    os.execute("emacsclient -n -c 2>/dev/null || open -a Emacs")
  end
  return true
end

-- Focus Emacs workspace using yabai
function emacs.focus_workspace(yabai_control_script)
  if not yabai_control_script then
    yabai_control_script = HOME .. "/.config/scripts/yabai_control.sh"
  end

  local cmd = string.format(
    "bash %q space-focus-app Emacs",
    yabai_control_script
  )
  os.execute(cmd)
  return true
end

-- Get recent org files
function emacs.get_recent_org_files(max_count)
  max_count = max_count or 5

  local cmd = string.format(
    "find %q -type f -name '*.org' -exec stat -f '%%m %%N' {} \\; 2>/dev/null | sort -rn | head -n %d",
    emacs.config.docs_dir,
    max_count
  )

  local handle = io.popen(cmd)
  if not handle then
    return {}
  end

  local org_files = {}
  for line in handle:lines() do
    local timestamp, path = line:match("^(%d+)%s+(.+)$")
    if path then
      local name = path:match("([^/]+)$")
      table.insert(org_files, {
        path = path,
        name = name,
        timestamp = tonumber(timestamp) or 0,
      })
    end
  end
  handle:close()

  return org_files
end

-- Get org-mode task count from tasks.org
function emacs.get_task_count()
  local tasks_file = emacs.config.tasks_file
  local file = io.open(tasks_file, "r")
  if not file then
    return 0
  end

  local todo_count = 0
  for line in file:lines() do
    if line:match("^%*+%s+TODO") then
      todo_count = todo_count + 1
    end
  end
  file:close()

  return todo_count
end

-- Get done task count
function emacs.get_done_count()
  local tasks_file = emacs.config.tasks_file
  local file = io.open(tasks_file, "r")
  if not file then
    return 0
  end

  local done_count = 0
  for line in file:lines() do
    if line:match("^%*+%s+DONE") then
      done_count = done_count + 1
    end
  end
  file:close()

  return done_count
end

-- Parse tasks from tasks.org
function emacs.get_tasks(max_count)
  max_count = max_count or 10
  local tasks_file = emacs.config.tasks_file
  local file = io.open(tasks_file, "r")
  if not file then
    return {}
  end

  local tasks = {}
  for line in file:lines() do
    if #tasks >= max_count then
      break
    end

    local status, title = line:match("^%*+%s+(TODO)%s+(.+)$")
    if not status then
      status, title = line:match("^%*+%s+(DONE)%s+(.+)$")
    end
    if status and title then
      table.insert(tasks, {
        status = status,
        title = title,
      })
    end
  end
  file:close()

  return tasks
end

-- Open tasks.org
function emacs.open_tasks()
  return emacs.open_file(emacs.config.tasks_file)
end

-- Open ROM workflow
function emacs.open_rom_workflow()
  return emacs.open_file(emacs.config.rom_workflow)
end

-- Open dev workflow
function emacs.open_dev_workflow()
  return emacs.open_file(emacs.config.dev_workflow)
end

-- Execute org-capture (requires emacsclient)
function emacs.org_capture(template_key)
  local cmd
  if template_key then
    cmd = string.format("emacsclient -e '(org-capture nil \"%s\")' 2>/dev/null", template_key)
  else
    cmd = "emacsclient -e '(org-capture)' 2>/dev/null"
  end
  os.execute(cmd)
  return true
end

-- Execute arbitrary elisp command
function emacs.eval_elisp(elisp_code)
  local cmd = string.format("emacsclient -e %q 2>/dev/null", elisp_code)
  local handle = io.popen(cmd)
  if not handle then
    return nil
  end

  local result = handle:read("*a")
  handle:close()
  return result
end

-- Check if Emacs server is running
function emacs.server_running()
  local result = emacs.eval_elisp("(server-running-p)")
  return result and result:match("t")
end

-- Create menu items for Emacs integration
function emacs.create_menu_items(ctx)
  local items = {}

  -- Launch/Focus Emacs
  local emacs_running = emacs.is_running()
  local emacs_icon = emacs_running and "" or ""
  local emacs_label = emacs_running and "Focus Emacs" or "Launch Emacs"

  table.insert(items, {
    type = "item",
    name = "emacs.launch",
    icon = emacs_icon,
    label = emacs_label,
    action = emacs_running
      and ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs")
      or "open -a Emacs",
  })

  -- Workflow documents
  table.insert(items, {
    type = "item",
    name = "emacs.tasks",
    icon = "󰩹",
    label = "Tasks.org",
    action = ctx.open_path(emacs.config.tasks_file),
  })

  table.insert(items, {
    type = "item",
    name = "emacs.rom_workflow",
    icon = "󰊕",
    label = "ROM Workflow",
    action = ctx.open_path(emacs.config.rom_workflow),
  })

  table.insert(items, {
    type = "item",
    name = "emacs.dev_workflow",
    icon = "",
    label = "Dev Workflow",
    action = ctx.open_path(emacs.config.dev_workflow),
  })

  -- Recent org files
  local recent_files = emacs.get_recent_org_files(5)
  if #recent_files > 0 then
    local org_items = {}
    for i, file in ipairs(recent_files) do
      table.insert(org_items, {
        type = "item",
        name = "emacs.org." .. i,
        icon = "󰈙",
        label = file.name,
        action = ctx.open_path(file.path),
      })
    end

    table.insert(items, {
      type = "submenu",
      name = "emacs.recent_org",
      icon = "󰋜",
      label = "Recent Org Files",
      items = org_items,
    })
  end

  -- Org capture (if server is running)
  if emacs.server_running() then
    table.insert(items, {
      type = "separator",
      name = "emacs.sep1",
    })

    table.insert(items, {
      type = "item",
      name = "emacs.capture",
      icon = "󰄀",
      label = "Org Capture",
      action = "emacsclient -e '(org-capture)' 2>/dev/null &",
    })
  end

  -- Open Emacs config directory
  if emacs.config.emacs_dir then
    table.insert(items, {
      type = "item",
      name = "emacs.config",
      icon = "󰒓",
      label = "Emacs Config",
      action = ctx.open_path(emacs.config.emacs_dir),
    })
  end

  return items
end

-- Get status text for display
function emacs.get_status_text()
  if emacs.is_running() then
    local task_count = emacs.get_task_count()
    if task_count > 0 then
      return string.format("%d tasks", task_count)
    else
      return "Running"
    end
  else
    return "Not Running"
  end
end

-- Get icon for status
function emacs.get_status_icon()
  if emacs.is_running() then
    return ""
  else
    return ""
  end
end

return emacs
