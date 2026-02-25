-- Journal/Org-mode integration for Barista
-- Shows inbox item count, provides quick capture via emacsclient

local journal = {}

local HOME = os.getenv("HOME") or ""
local INBOX_FILE = HOME .. "/Journal/inbox.org"

local function expand_path(path)
  if type(path) ~= "string" or path == "" then return nil end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  end
  return path
end

local function path_exists(path)
  if not path or path == "" then return false end
  local handle = io.popen(string.format("test -e %q && printf 1 || printf 0", path))
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1") ~= nil
end

local function exec(cmd)
  local handle = io.popen(cmd)
  if not handle then return nil end
  local result = handle:read("*a")
  handle:close()
  return result
end

local function get_inbox_count()
  if not path_exists(INBOX_FILE) then return 0 end
  local result = exec(string.format(
    "grep -c '^\\*\\+ \\(TODO\\|NEXT\\|ACTIVE\\|WAITING\\)' %q 2>/dev/null",
    INBOX_FILE))
  return tonumber((result or "0"):match("%d+")) or 0
end

local function emacsclient_capture(template_key)
  return string.format(
    "emacsclient -e '(org-capture nil \"%s\")' 2>/dev/null || "
    .. "emacsclient -c -e '(org-capture nil \"%s\")'",
    template_key, template_key)
end

function journal.is_available()
  return path_exists(INBOX_FILE)
end

function journal.get_status()
  local count = get_inbox_count()
  if count > 0 then
    return string.format("%d", count), "󰎚", "0xfff9e2af"
  end
  return "0", "󰎚", "0xffa6e3a1"
end

function journal.create_menu_items(ctx)
  local count = get_inbox_count()
  local items = {}

  -- Header
  table.insert(items, {
    type = "header",
    name = "journal.header",
    label = string.format("Journal (Inbox: %d)", count),
  })

  -- Quick capture submenu
  table.insert(items, {
    type = "item",
    name = "journal.capture.task",
    icon = "󰝖",
    label = "Quick Task",
    action = emacsclient_capture("t"),
  })

  table.insert(items, {
    type = "item",
    name = "journal.capture.journal",
    icon = "󰺿",
    label = "Journal Thought",
    action = emacsclient_capture("j"),
  })

  table.insert(items, {
    type = "item",
    name = "journal.capture.worklog",
    icon = "󰉻",
    label = "Worklog Entry",
    action = emacsclient_capture("l"),
  })

  table.insert(items, {
    type = "item",
    name = "journal.capture.idea",
    icon = "󰛨",
    label = "Idea",
    action = emacsclient_capture("i"),
  })

  table.insert(items, {
    type = "item",
    name = "journal.capture.decision",
    icon = "󱃔",
    label = "Decision",
    action = emacsclient_capture("d"),
  })

  table.insert(items, { type = "separator", name = "journal.sep1" })

  -- Open actions
  table.insert(items, {
    type = "item",
    name = "journal.open.agenda",
    icon = "󰃭",
    label = "Open Agenda",
    action = "emacsclient -e '(org-agenda-list)' 2>/dev/null || emacsclient -c -e '(org-agenda-list)'",
  })

  table.insert(items, {
    type = "item",
    name = "journal.open.inbox",
    icon = "󰇮",
    label = "Open Inbox",
    action = string.format(
      "emacsclient -e '(find-file %q)' 2>/dev/null || emacsclient -c -e '(find-file %q)'",
      INBOX_FILE, INBOX_FILE),
  })

  table.insert(items, {
    type = "item",
    name = "journal.weekly_review",
    icon = "󰋚",
    label = "Generate Weekly Review",
    action = "emacsclient -e '(scawful/generate-weekly-review)' 2>/dev/null",
  })

  table.insert(items, {
    type = "item",
    name = "journal.close_day",
    icon = "󰗠",
    label = "Close Day (Worklog)",
    action = "emacsclient -e '(scawful/worklog-close-day)' 2>/dev/null",
  })

  return items
end

return journal
