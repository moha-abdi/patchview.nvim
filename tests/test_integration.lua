-- Integration tests for patchview
-- Run with: nvim --headless -u NONE -c "set rtp+=." -c "lua dofile('tests/test_integration.lua')" -c "q"

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

-- Load modules
package.path = package.path .. ";lua/?.lua;lua/?/init.lua"

print("\n=== Patchview Integration Tests ===\n")

test("config module loads", function()
  local config = require("patchview.config")
  assert(config.defaults, "Config should have defaults")
  assert(config.defaults.watch, "Config should have watch defaults")
end)

test("config setup works", function()
  local config = require("patchview.config")
  config.setup({ mode = "preview" })
  assert_eq(config.options.mode, "preview")
end)

test("config get works", function()
  local config = require("patchview.config")
  config.setup({ watch = { debounce_ms = 200 } })
  assert_eq(config.get("watch.debounce_ms"), 200)
end)

test("diff module loads", function()
  local diff = require("patchview.diff")
  assert(diff.compute, "Diff should have compute function")
end)

test("hunks module loads", function()
  local hunks = require("patchview.hunks")
  assert(hunks.create_from_diff, "Hunks should have create_from_diff function")
end)

test("watcher module loads", function()
  local watcher = require("patchview.watcher")
  assert(watcher.watch, "Watcher should have watch function")
  assert(watcher.unwatch, "Watcher should have unwatch function")
end)

test("render module loads", function()
  local render = require("patchview.render")
  assert(render.show_hunks, "Render should have show_hunks function")
  assert(render.clear, "Render should have clear function")
end)

test("highlights module loads", function()
  local highlights = require("patchview.highlights")
  assert(highlights.setup, "Highlights should have setup function")
end)

test("signs module loads", function()
  local signs = require("patchview.signs")
  assert(signs.setup, "Signs should have setup function")
end)

test("actions module loads", function()
  local actions = require("patchview.actions")
  assert(actions.next_hunk, "Actions should have next_hunk function")
  assert(actions.accept_hunk, "Actions should have accept_hunk function")
end)

test("status module loads", function()
  local status = require("patchview.status")
  assert(status.statusline, "Status should have statusline function")
end)

test("notify module loads", function()
  local notify = require("patchview.notify")
  assert(notify.change_detected, "Notify should have change_detected function")
end)

test("git module loads", function()
  local git = require("patchview.git")
  assert(git.is_git_repo, "Git should have is_git_repo function")
end)

test("telescope module loads", function()
  local telescope = require("patchview.telescope")
  assert(telescope.open, "Telescope should have open function")
end)

test("main module loads", function()
  local patchview = require("patchview")
  assert(patchview.setup, "Patchview should have setup function")
end)

test("full setup works", function()
  local patchview = require("patchview")
  patchview.setup({
    mode = "auto",
    watch = { enabled = false }, -- Don't actually watch files in test
  })
  assert_true(patchview.state.enabled, "Patchview should be enabled after setup")
end)

print("\n=== Tests Complete ===\n")
