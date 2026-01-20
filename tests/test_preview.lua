-- Tests for patchview preview module (split diff view)
-- Run with: nvim --headless -u NONE -c "set rtp+=." -c "lua dofile('tests/test_preview.lua')" -c "q"

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
  assert(a == b, msg or string.format("Expected %s, got %s", tostring(b), tostring(a)))
end

local function assert_true(a, msg)
  assert(a == true, msg or "Expected true")
end

local function assert_false(a, msg)
  assert(a == false, msg or "Expected false")
end

local function assert_not_nil(a, msg)
  assert(a ~= nil, msg or "Expected non-nil value")
end

-- Load modules
package.path = package.path .. ";lua/?.lua;lua/?/init.lua"

print("\n=== Patchview Preview/Split Diff Tests ===\n")

test("preview module loads", function()
  local preview = require("patchview.preview")
  assert_not_nil(preview, "Preview module should load")
end)

test("preview module has split diff functions", function()
  local preview = require("patchview.preview")
  assert_not_nil(preview.show_split_diff, "Preview should have show_split_diff function")
  assert_not_nil(preview.close_split_diff, "Preview should have close_split_diff function")
  assert_not_nil(preview.toggle_split_diff, "Preview should have toggle_split_diff function")
  assert_not_nil(preview.is_split_diff_open, "Preview should have is_split_diff_open function")
end)

test("is_split_diff_open returns false initially", function()
  local preview = require("patchview.preview")
  assert_false(preview.is_split_diff_open(), "Split diff should not be open initially")
end)

test("close_split_diff works when not open", function()
  local preview = require("patchview.preview")
  -- Should not error when split diff is not open
  preview.close_split_diff()
  assert_false(preview.is_split_diff_open(), "Split diff should still be closed")
end)

test("main module exposes split_diff", function()
  local patchview = require("patchview")
  assert_not_nil(patchview.split_diff, "Patchview should have split_diff function")
  assert_not_nil(patchview.close_split_diff, "Patchview should have close_split_diff function")
end)

test("config has split_diff keymap", function()
  local config = require("patchview.config")
  config.setup({})
  assert_not_nil(config.options.keymaps.split_diff, "Config should have split_diff keymap")
  assert_eq(config.options.keymaps.split_diff, "<leader>pd", "Default split_diff keymap should be <leader>pd")
end)

test("split_diff keymap can be disabled", function()
  local config = require("patchview.config")
  config.setup({
    keymaps = {
      split_diff = false
    }
  })
  assert_eq(config.options.keymaps.split_diff, false, "split_diff keymap should be disabled")
end)

test("split_diff keymap can be customized", function()
  local config = require("patchview.config")
  config.setup({
    keymaps = {
      split_diff = "<leader>sd"
    }
  })
  assert_eq(config.options.keymaps.split_diff, "<leader>sd", "split_diff keymap should be customizable")
end)

print("\n=== Preview/Split Diff Tests Complete ===\n")
