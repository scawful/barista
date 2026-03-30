-- Oracle of Secrets Integration Module
-- Emacs-first workbench bridge for Oracle workflow actions.

local oracle = {}

local locator = require("tool_locator")

local HOME = os.getenv("HOME")
local CODE_DIR = os.getenv("BARISTA_CODE_DIR") or (HOME .. "/src")
local DOTFILES_DIR = CODE_DIR .. "/config/dotfiles"
local ORACLE_DIR = CODE_DIR .. "/hobby/oracle-of-secrets"

oracle.config = {
  repo_path = ORACLE_DIR,
  workbench = DOTFILES_DIR .. "/bin/oos-workbench",
  legacy_workbench = DOTFILES_DIR .. "/bin/oos-cockpit",
  handoff = ORACLE_DIR .. "/.context/scratchpad/agent_handoff.md",
  tracker = ORACLE_DIR .. "/oracle.org",
  workflow_plan = ORACLE_DIR .. "/Docs/Planning/Plans/development_workflow_alignment_2026-03-28.md",
  runbook = ORACLE_DIR .. "/RUNBOOK.md",
}

local function path_exists(path, want_dir)
  return locator.path_exists(path, want_dir)
end

local function shell_quote(value)
  return string.format("%q", tostring(value))
end

local function open_terminal(command)
  if not command or command == "" then
    return ""
  end
  return string.format("osascript -e 'tell application \"Terminal\" to do script %q'", command)
end

local function open_target(ctx, path)
  if ctx and ctx.open_path then
    return ctx.open_path(path)
  end
  return string.format("open %q", path)
end

local function workbench_path()
  if path_exists(oracle.config.workbench, false) then
    return oracle.config.workbench
  end
  if path_exists(oracle.config.legacy_workbench, false) then
    return oracle.config.legacy_workbench
  end
  return nil
end

local function workbench_action(args)
  local bin = workbench_path()
  if not bin then
    return ""
  end
  return string.format("%q %s", bin, args)
end

local function shell_fallback(primary, fallback)
  if not primary or primary == "" then
    return fallback or ""
  end
  if not fallback or fallback == "" then
    return primary
  end
  return string.format("bash -lc %q", string.format("%s >/dev/null 2>&1 || %s", primary, fallback))
end

local function focus_or_open_app(ctx, app_name, fallback_action)
  local yabai_control = ctx and ctx.scripts and ctx.scripts.yabai_control or nil
  if yabai_control and yabai_control ~= "" then
    return shell_fallback(
      string.format("%s space-focus-app %s", shell_quote(yabai_control), shell_quote(app_name)),
      fallback_action
    )
  end
  return fallback_action or ""
end

local function resolved_yaze_launch_action(ctx)
  local yaze_launcher, yaze_launcher_ok = locator.resolve_yaze_launcher()
  if yaze_launcher_ok and yaze_launcher then
    return shell_quote(yaze_launcher)
  end

  local yaze_app, yaze_app_ok = locator.resolve_yaze_app(ctx)
  if yaze_app_ok and yaze_app then
    return string.format("open %s", shell_quote(yaze_app))
  end

  local yaze_dir = select(1, locator.resolve_yaze_dir(ctx))
  if yaze_dir and ctx and ctx.open_path then
    return ctx.open_path(yaze_dir)
  end

  return ""
end

local function build_state(ctx)
  local repo_ok = path_exists(oracle.config.repo_path, true)
  local workbench = workbench_path()
  local workbench_ok = workbench ~= nil
  local workbench_dashboard = workbench_ok and workbench_action("dashboard") or open_target(ctx, oracle.config.repo_path)
  local terminal_action = open_terminal(string.format("cd %s", shell_quote(oracle.config.repo_path)))

  local mesen_run, mesen_run_ok = locator.resolve_mesen_run(ctx)
  local mesen_action = mesen_run_ok and mesen_run and shell_quote(mesen_run) or ""
  local yaze_action = resolved_yaze_launch_action(ctx)

  local emacs_focus_action = focus_or_open_app(ctx, "Emacs", "open -a Emacs")
  local mesen_focus_action = focus_or_open_app(ctx, "Mesen2 OOS", mesen_action)
  local yaze_focus_action = focus_or_open_app(ctx, "Yaze", yaze_action)

  local balance_windows_action = ctx and ctx.scripts and ctx.scripts.yabai_control
    and ctx.call_script(ctx.scripts.yabai_control, "balance")
    or ""
  local rotate_layout_action = ctx and ctx.scripts and ctx.scripts.yabai_control
    and ctx.call_script(ctx.scripts.yabai_control, "space-rotate")
    or ""

  return {
    repo_ok = repo_ok,
    workbench_ok = workbench_ok,
    dashboard_action = workbench_dashboard,
    terminal_action = terminal_action,
    quick_action = workbench_ok and workbench_action("quick-build") or "",
    verify_action = workbench_ok and workbench_action("verify") or "",
    maku_action = workbench_ok and workbench_action("session maku") or "",
    d4_action = workbench_ok and workbench_action("session d4") or "",
    d6_action = workbench_ok and workbench_action("session d6") or "",
    menu_action = workbench_ok and workbench_action("session menu") or "",
    handoff_action = open_target(ctx, oracle.config.handoff),
    tracker_action = open_target(ctx, oracle.config.tracker),
    workflow_action = open_target(ctx, oracle.config.workflow_plan),
    runbook_action = open_target(ctx, oracle.config.runbook),
    repo_action = open_target(ctx, oracle.config.repo_path),
    emacs_focus_action = emacs_focus_action,
    mesen_focus_action = mesen_focus_action,
    yaze_focus_action = yaze_focus_action,
    balance_windows_action = balance_windows_action,
    rotate_layout_action = rotate_layout_action,
  }
end

function oracle.create_popup_items(ctx)
  local state = build_state(ctx)
  local items = {}

  table.insert(items, {
    type = "header",
    id = "workspace",
    label = "Workspace",
  })
  table.insert(items, {
    name = "oracle.workbench",
    icon = "󰊕",
    label = "Open Workbench",
    action = state.dashboard_action,
  })
  table.insert(items, {
    name = "oracle.terminal",
    icon = "󰆍",
    label = "Project Terminal",
    action = state.terminal_action,
  })
  table.insert(items, {
    name = "oracle.workflow",
    icon = "󰣖",
    label = "Open Workflow Plan",
    action = state.workflow_action,
  })

  if state.workbench_ok then
    table.insert(items, { type = "separator", name = "oracle.sep.build" })
    table.insert(items, {
      type = "header",
      id = "build",
      label = "Build And Jump",
    })
    table.insert(items, {
      name = "oracle.quick",
      icon = "󰑐",
      label = "Quick Build",
      action = state.quick_action,
    })
    table.insert(items, {
      name = "oracle.verify",
      icon = "󰓅",
      label = "Verify Build",
      action = state.verify_action,
    })
    table.insert(items, {
      name = "oracle.session.maku",
      icon = "󰐃",
      label = "Jump: Maku",
      action = state.maku_action,
    })
    table.insert(items, {
      name = "oracle.session.d4",
      icon = "󰁆",
      label = "Jump: D4",
      action = state.d4_action,
    })
    table.insert(items, {
      name = "oracle.session.d6",
      icon = "󰁆",
      label = "Jump: D6",
      action = state.d6_action,
    })
    table.insert(items, {
      name = "oracle.session.menu",
      icon = "󰍜",
      label = "Jump: Menu",
      action = state.menu_action,
    })
  end

  table.insert(items, { type = "separator", name = "oracle.sep.windows" })
  table.insert(items, {
    type = "header",
    id = "windows",
    label = "Windows",
  })
  table.insert(items, {
    name = "oracle.focus.emacs",
    icon = "󰘔",
    label = "Focus Emacs",
    action = state.emacs_focus_action,
  })
  if state.mesen_focus_action ~= "" then
    table.insert(items, {
      name = "oracle.focus.mesen",
      icon = "󰁆",
      label = "Focus Mesen2",
      action = state.mesen_focus_action,
    })
  end
  if state.yaze_focus_action ~= "" then
    table.insert(items, {
      name = "oracle.focus.yaze",
      icon = "󰯙",
      label = "Focus Yaze",
      action = state.yaze_focus_action,
    })
  end
  if state.balance_windows_action ~= "" then
    table.insert(items, {
      name = "oracle.balance",
      icon = "󰓅",
      label = "Balance Windows",
      action = state.balance_windows_action,
    })
  end
  if state.rotate_layout_action ~= "" then
    table.insert(items, {
      name = "oracle.rotate",
      icon = "󰑞",
      label = "Rotate Layout",
      action = state.rotate_layout_action,
    })
  end

  table.insert(items, { type = "separator", name = "oracle.sep.notes" })
  table.insert(items, {
    type = "header",
    id = "notes",
    label = "Notes",
  })
  table.insert(items, {
    name = "oracle.handoff",
    icon = "󰣖",
    label = "Open Handoff",
    action = state.handoff_action,
  })
  table.insert(items, {
    name = "oracle.tracker",
    icon = "󰃤",
    label = "Open Tracker",
    action = state.tracker_action,
  })
  table.insert(items, {
    name = "oracle.runbook",
    icon = "󰈙",
    label = "Open Runbook",
    action = state.runbook_action,
  })
  table.insert(items, {
    name = "oracle.repo",
    icon = "󰋜",
    label = "Open Repository",
    action = state.repo_action,
  })

  return items
end

function oracle.create_apple_menu_entry(ctx, opts)
  local state = build_state(ctx)
  if not state.repo_ok then
    return nil
  end

  opts = opts or {}
  return {
    id = opts.id or "oracle_oos",
    label = opts.label or "Oracle",
    icon = opts.icon or "󰊕",
    icon_color = opts.icon_color,
    section = opts.section or "apps",
    action = state.dashboard_action,
    available = true,
    default_enabled = opts.default_enabled ~= false,
    submenu = true,
    items = oracle.create_popup_items(ctx),
    arrow_icon = opts.arrow_icon or "󰅂",
    order = opts.order,
  }
end

function oracle.create_menu_items(ctx)
  local state = build_state(ctx)
  local items = {}

  table.insert(items, {
    type = "header",
    name = "oracle.header",
    label = "Oracle",
  })

  if not state.repo_ok then
    table.insert(items, {
      type = "item",
      name = "oracle.missing",
      icon = "⚠️",
      label = "Oracle repo missing",
      action = open_target(ctx, CODE_DIR .. "/hobby"),
    })
    return items
  end

  table.insert(items, {
    type = "item",
    name = "oracle.dashboard",
    icon = "󰊕",
    label = "Open Workbench",
    action = state.dashboard_action,
  })

  if state.workbench_ok then
    table.insert(items, {
      type = "item",
      name = "oracle.quick",
      icon = "󰑐",
      label = "Quick Build",
      action = state.quick_action,
    })
    table.insert(items, {
      type = "item",
      name = "oracle.verify",
      icon = "󰓅",
      label = "Verify Build",
      action = state.verify_action,
    })
    table.insert(items, { type = "separator", name = "oracle.sep.sessions" })
    table.insert(items, {
      type = "item",
      name = "oracle.session.maku",
      icon = "󰐃",
      label = "Maku Session",
      action = state.maku_action,
    })
    table.insert(items, {
      type = "item",
      name = "oracle.session.d4",
      icon = "󰁆",
      label = "D4 Session",
      action = state.d4_action,
    })
    table.insert(items, {
      type = "item",
      name = "oracle.session.d6",
      icon = "󰁆",
      label = "D6 Session",
      action = state.d6_action,
    })
    table.insert(items, {
      type = "item",
      name = "oracle.session.menu",
      icon = "󰍜",
      label = "Menu Session",
      action = state.menu_action,
    })
  end

  table.insert(items, { type = "separator", name = "oracle.sep.docs" })
  table.insert(items, {
    type = "item",
    name = "oracle.handoff",
    icon = "󰣖",
    label = "Open Handoff",
    action = state.handoff_action,
  })
  table.insert(items, {
    type = "item",
    name = "oracle.tracker",
    icon = "󰃤",
    label = "Open Tracker",
    action = state.tracker_action,
  })
  table.insert(items, {
    type = "item",
    name = "oracle.workflow",
    icon = "󰣖",
    label = "Open Workflow Plan",
    action = state.workflow_action,
  })
  table.insert(items, {
    type = "item",
    name = "oracle.runbook",
    icon = "󰈙",
    label = "Open Runbook",
    action = state.runbook_action,
  })
  table.insert(items, {
    type = "item",
    name = "oracle.repo",
    icon = "󰋜",
    label = "Open Repository",
    action = state.repo_action,
  })

  return items
end

return oracle
