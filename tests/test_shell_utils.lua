-- test_shell_utils.lua - Tests for modules/shell_utils.lua

local shell_utils = require("shell_utils")

run_test("shell_quote: simple string", function()
  local result = shell_utils.shell_quote("hello")
  assert_equal(result, "'hello'", "simple quoting")
end)

run_test("shell_quote: string with single quote", function()
  local result = shell_utils.shell_quote("it's")
  assert_equal(result, "'it'\\''s'", "escaped single quote")
end)

run_test("shell_quote: empty string", function()
  local result = shell_utils.shell_quote("")
  assert_equal(result, "''", "empty string")
end)

run_test("shell_quote: number", function()
  local result = shell_utils.shell_quote(42)
  assert_equal(result, "'42'", "number coercion")
end)

run_test("env_prefix: empty table", function()
  local result = shell_utils.env_prefix({})
  assert_equal(result, "", "empty returns empty string")
end)

run_test("env_prefix: nil", function()
  local result = shell_utils.env_prefix(nil)
  assert_equal(result, "", "nil returns empty string")
end)

run_test("env_prefix: filters non-string values", function()
  local result = shell_utils.env_prefix({ A = "val", B = 123, C = true })
  -- Only A should appear (string value)
  assert_true(result:find("A="), "should contain A")
  assert_true(not result:find("B="), "should not contain B (number)")
  assert_true(not result:find("C="), "should not contain C (boolean)")
end)

run_test("env_prefix: sorted keys", function()
  local result = shell_utils.env_prefix({ Z = "z", A = "a", M = "m" })
  local a_pos = result:find("A=")
  local m_pos = result:find("M=")
  local z_pos = result:find("Z=")
  assert_true(a_pos < m_pos, "A before M")
  assert_true(m_pos < z_pos, "M before Z")
end)

run_test("file_exists: nil path", function()
  assert_true(not shell_utils.file_exists(nil), "nil returns false")
end)

run_test("file_exists: empty path", function()
  assert_true(not shell_utils.file_exists(""), "empty returns false")
end)

run_test("file_exists: nonexistent path", function()
  assert_true(not shell_utils.file_exists("/nonexistent/path/foo.bar"), "nonexistent returns false")
end)

run_test("call_script: nil path", function()
  local result = shell_utils.call_script(nil)
  assert_equal(result, "", "nil returns empty")
end)

run_test("call_script: empty path", function()
  local result = shell_utils.call_script("")
  assert_equal(result, "", "empty returns empty")
end)

run_test("call_script: path with args", function()
  local result = shell_utils.call_script("/usr/bin/test", "arg1", "arg2")
  assert_true(result:find("bash"), "should use bash")
  assert_true(result:find("arg1"), "should contain arg1")
  assert_true(result:find("arg2"), "should contain arg2")
end)

run_test("open_path: builds open command", function()
  local result = shell_utils.open_path("/Applications/Test.app")
  assert_true(result:find("open"), "should contain open")
  assert_true(result:find("Test.app"), "should contain path")
end)

run_test("command_available: nil returns false", function()
  assert_true(not shell_utils.command_available(nil), "nil returns false")
end)

run_test("command_available: empty returns false", function()
  assert_true(not shell_utils.command_available(""), "empty returns false")
end)

run_test("command_available: ls exists", function()
  assert_true(shell_utils.command_available("ls"), "ls should exist")
end)

run_test("command_available: nonexistent binary", function()
  assert_true(not shell_utils.command_available("this_binary_does_not_exist_xyz"), "nonexistent returns false")
end)

run_test("check_service: nil returns false", function()
  assert_true(not shell_utils.check_service(nil), "nil returns false")
end)

run_test("check_service: empty returns false", function()
  assert_true(not shell_utils.check_service(""), "empty returns false")
end)

run_test("check_service: nonexistent process", function()
  assert_true(not shell_utils.check_service("this_process_does_not_exist_xyz"), "nonexistent returns false")
end)
