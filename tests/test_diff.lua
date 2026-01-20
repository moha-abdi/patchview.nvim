-- Tests for patchview diff module
-- Run with: nvim --headless -u NONE -c "set rtp+=." -c "lua dofile('tests/test_diff.lua')" -c "q"

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("PASS: " .. name)
  else
    print("FAIL: " .. name)
    print("  " .. tostring(err))
  end
end

local function assert_eq(a, b, msg)
  if type(a) == "table" and type(b) == "table" then
    assert(vim.deep_equal(a, b), msg or string.format("Expected %s, got %s", vim.inspect(b), vim.inspect(a)))
  else
    assert(a == b, msg or string.format("Expected %s, got %s", tostring(b), tostring(a)))
  end
end

-- Load the diff module
package.path = package.path .. ";lua/?.lua;lua/?/init.lua"
local diff = require("patchview.diff")

print("\n=== Patchview Diff Tests ===\n")

test("empty to empty", function()
  local result = diff.compute({}, {})
  assert_eq(#result, 0)
end)

test("empty to lines (all additions)", function()
  local result = diff.compute({}, {"a", "b", "c"})
  assert_eq(#result, 1)
  assert_eq(result[1].type, "add")
  assert_eq(result[1].new_count, 3)
end)

test("lines to empty (all deletions)", function()
  local result = diff.compute({"a", "b", "c"}, {})
  assert_eq(#result, 1)
  assert_eq(result[1].type, "delete")
  assert_eq(result[1].old_count, 3)
end)

test("identical lines (no changes)", function()
  local result = diff.compute({"a", "b", "c"}, {"a", "b", "c"})
  assert_eq(#result, 0)
end)

test("single line change", function()
  local result = diff.compute({"a", "b", "c"}, {"a", "X", "c"})
  assert_eq(#result, 1)
  assert_eq(result[1].type, "change")
  assert_eq(result[1].old_lines[1], "b")
  assert_eq(result[1].new_lines[1], "X")
end)

test("single line insertion", function()
  local result = diff.compute({"a", "c"}, {"a", "b", "c"})
  assert_eq(#result, 1)
  assert_eq(result[1].type, "add")
  assert_eq(result[1].new_lines[1], "b")
end)

test("single line deletion", function()
  local result = diff.compute({"a", "b", "c"}, {"a", "c"})
  assert_eq(#result, 1)
  assert_eq(result[1].type, "delete")
  assert_eq(result[1].old_lines[1], "b")
end)

test("multiple changes", function()
  local old = {"line1", "line2", "line3", "line4", "line5"}
  local new = {"line1", "CHANGED", "line3", "INSERTED", "line4", "line5"}
  local result = diff.compute(old, new)
  assert(#result >= 1, "Expected at least 1 change")
end)

test("lines_equal - same", function()
  assert(diff.lines_equal({"a", "b"}, {"a", "b"}))
end)

test("lines_equal - different", function()
  assert(not diff.lines_equal({"a", "b"}, {"a", "c"}))
end)

test("lines_equal - different length", function()
  assert(not diff.lines_equal({"a", "b"}, {"a", "b", "c"}))
end)

print("\n=== Tests Complete ===\n")
