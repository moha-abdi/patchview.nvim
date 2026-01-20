-- Tests for patchview hunks module
-- Run with: nvim --headless -u NONE -c "set rtp+=." -c "lua dofile('tests/test_hunks.lua')" -c "q"

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

-- Load modules
package.path = package.path .. ";lua/?.lua;lua/?/init.lua"
local hunks = require("patchview.hunks")
local diff = require("patchview.diff")

print("\n=== Patchview Hunks Tests ===\n")

test("create_from_diff - empty", function()
  local result = hunks.create_from_diff({}, 3)
  assert_eq(#result, 0)
end)

test("create_from_diff - single change", function()
  local changes = {{
    type = "add",
    old_start = 1,
    old_count = 0,
    new_start = 2,
    new_count = 1,
    old_lines = {},
    new_lines = {"new line"},
  }}
  local result = hunks.create_from_diff(changes, 3)
  assert_eq(#result, 1)
  assert_eq(result[1].type, "add")
  assert_eq(result[1].status, "pending")
end)

test("get_line_range - add", function()
  local hunk = {
    type = "add",
    old_start = 0,
    old_count = 0,
    new_start = 5,
    new_count = 3,
  }
  local start_line, end_line = hunks.get_line_range(hunk)
  assert_eq(start_line, 5)
  assert_eq(end_line, 7)
end)

test("get_line_range - delete", function()
  local hunk = {
    type = "delete",
    old_start = 5,
    old_count = 3,
    new_start = 0,
    new_count = 0,
  }
  local start_line, end_line = hunks.get_line_range(hunk)
  assert_eq(start_line, 5)
  assert_eq(end_line, 5)
end)

test("get_stats", function()
  local test_hunks = {
    { status = "pending", new_count = 5, old_count = 2 },
    { status = "accepted", new_count = 3, old_count = 1 },
    { status = "pending", new_count = 1, old_count = 4 },
  }
  local stats = hunks.get_stats(test_hunks)
  assert_eq(stats.total, 3)
  assert_eq(stats.pending, 2)
  assert_eq(stats.accepted, 1)
  assert_eq(stats.additions, 9)
  assert_eq(stats.deletions, 7)
end)

test("accept/reject", function()
  local hunk = { status = "pending" }
  hunks.accept(hunk)
  assert_eq(hunk.status, "accepted")
  
  hunk.status = "pending"
  hunks.reject(hunk)
  assert_eq(hunk.status, "rejected")
end)

test("get_pending", function()
  local test_hunks = {
    { id = 1, status = "pending" },
    { id = 2, status = "accepted" },
    { id = 3, status = "pending" },
  }
  local pending = hunks.get_pending(test_hunks)
  assert_eq(#pending, 2)
  assert_eq(pending[1].id, 1)
  assert_eq(pending[2].id, 3)
end)

test("to_unified_diff", function()
  local hunk = {
    old_start = 5,
    old_count = 2,
    new_start = 5,
    new_count = 3,
    old_lines = {"old1", "old2"},
    new_lines = {"new1", "new2", "new3"},
  }
  local lines = hunks.to_unified_diff(hunk)
  assert(lines[1]:match("^@@"), "Expected hunk header")
  assert_eq(lines[2], "-old1")
  assert_eq(lines[3], "-old2")
  assert_eq(lines[4], "+new1")
end)

print("\n=== Tests Complete ===\n")
