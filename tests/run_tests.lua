#!/usr/bin/env lua
-- Lightweight Lua test runner for Barista
-- Usage: lua tests/run_tests.sh
--        lua tests/run_tests.sh tests/test_state.lua

-- Ensure modules can be found
local HOME = os.getenv("HOME") or ""
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
local SCRIPT_DIR = arg[0]:match("^(.+)/[^/]+$") or "."
local PROJECT_DIR = SCRIPT_DIR:match("^(.+)/tests$") or SCRIPT_DIR:match("^(.+)/tests/$") or "."

package.path = table.concat({
  package.path,
  PROJECT_DIR .. "/modules/?.lua",
  PROJECT_DIR .. "/modules/integrations/?.lua",
  PROJECT_DIR .. "/helpers/lib/?.lua",
  PROJECT_DIR .. "/?.lua",
}, ";")

-- Colors
local RED    = "\27[31m"
local GREEN  = "\27[32m"
local YELLOW = "\27[33m"
local RESET  = "\27[0m"

local total, passed, failed, errors = 0, 0, 0, {}

local function run_test(name, fn)
  total = total + 1
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write(GREEN .. "  ✓ " .. RESET .. name .. "\n")
  else
    failed = failed + 1
    table.insert(errors, { name = name, err = tostring(err) })
    io.write(RED .. "  ✗ " .. RESET .. name .. "\n")
    io.write("    " .. tostring(err) .. "\n")
  end
end

-- Simple assertion helpers
function assert_equal(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %q, got %q", msg or "assert_equal", tostring(b), tostring(a)), 2)
  end
end

function assert_true(v, msg)
  if not v then
    error(msg or "assert_true failed", 2)
  end
end

function assert_nil(v, msg)
  if v ~= nil then
    error(string.format("%s: expected nil, got %q", msg or "assert_nil", tostring(v)), 2)
  end
end

function assert_type(v, expected_type, msg)
  if type(v) ~= expected_type then
    error(string.format("%s: expected type %s, got %s", msg or "assert_type", expected_type, type(v)), 2)
  end
end

-- Export test runner for test files
_G.run_test = run_test
_G.assert_equal = assert_equal
_G.assert_true = assert_true
_G.assert_nil = assert_nil
_G.assert_type = assert_type

-- Discover and run test files
local test_files = {}
if #arg > 0 then
  -- Run specific test files
  for i = 1, #arg do
    table.insert(test_files, arg[i])
  end
else
  -- Auto-discover test_*.lua in tests/
  local handle = io.popen('ls "' .. SCRIPT_DIR .. '"/test_*.lua 2>/dev/null')
  if handle then
    for line in handle:lines() do
      table.insert(test_files, line)
    end
    handle:close()
  end
end

if #test_files == 0 then
  print(YELLOW .. "No test files found." .. RESET)
  os.exit(0)
end

print("\n" .. YELLOW .. "Running Barista tests..." .. RESET .. "\n")

for _, file in ipairs(test_files) do
  local basename = file:match("([^/]+)$") or file
  print(YELLOW .. "━━ " .. basename .. " ━━" .. RESET)
  local chunk, load_err = loadfile(file)
  if chunk then
    local ok, exec_err = pcall(chunk)
    if not ok then
      total = total + 1
      failed = failed + 1
      table.insert(errors, { name = basename .. " (load)", err = tostring(exec_err) })
      io.write(RED .. "  ✗ " .. RESET .. "failed to execute: " .. tostring(exec_err) .. "\n")
    end
  else
    total = total + 1
    failed = failed + 1
    table.insert(errors, { name = basename .. " (parse)", err = tostring(load_err) })
    io.write(RED .. "  ✗ " .. RESET .. "failed to parse: " .. tostring(load_err) .. "\n")
  end
end

-- Summary
print()
if failed == 0 then
  print(GREEN .. string.format("All %d tests passed ✓", passed) .. RESET)
else
  print(RED .. string.format("%d/%d tests failed", failed, total) .. RESET)
  print()
  for _, e in ipairs(errors) do
    print(RED .. "  FAIL: " .. e.name .. RESET)
    print("        " .. e.err)
  end
end

os.exit(failed == 0 and 0 or 1)
