-- patchview.nvim - Status information module
-- Provides status display and statusline integration

local M = {}

--- Show status in a floating window
function M.show()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")
  local watcher = require("patchview.watcher")
  local config = require("patchview.config")

  local lines = {
    "Patchview Status",
    "================",
    "",
    string.format("Plugin enabled: %s", patchview.state.enabled and "Yes" or "No"),
    string.format("Mode: %s", config.options.mode),
    string.format("Git-aware: %s", config.options.git.enabled and "Yes" or "No"),
    "",
    "Watched Buffers:",
    "----------------",
  }

  local watched = watcher.get_watched_buffers()
  if #watched == 0 then
    table.insert(lines, "  (none)")
  else
    for _, bufnr in ipairs(watched) do
      local buf_state = patchview.state.buffers[bufnr]
      local filename = buf_state and buf_state.filename or vim.api.nvim_buf_get_name(bufnr)
      local short_name = vim.fn.fnamemodify(filename, ":t")
      local hunk_count = buf_state and #buf_state.hunks or 0

      local stats = ""
      if hunk_count > 0 then
        local hunk_stats = hunks_mod.get_stats(buf_state.hunks)
        stats = string.format(" [%d hunks: +%d -%d]",
          hunk_stats.total, hunk_stats.additions, hunk_stats.deletions)
      end

      table.insert(lines, string.format("  %d: %s%s", bufnr, short_name, stats))
    end
  end

  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].modifiable = false

  local width = 50
  local height = #lines + 2

  for _, line in ipairs(lines) do
    width = math.max(width, #line + 4)
  end

  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Patchview Status ",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Close on any key
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  -- Auto-close on buffer leave
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

--- Get statusline component
---@return string Statusline string
function M.statusline()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")

  if not patchview.state.enabled then
    return ""
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = patchview.state.buffers[bufnr]

  if not buf_state then
    return ""
  end

  if not buf_state.watching then
    return ""
  end

  local hunk_count = #buf_state.hunks
  if hunk_count == 0 then
    return "PV:watching"
  end

  local stats = hunks_mod.get_stats(buf_state.hunks)
  return string.format("PV:%d(+%d -%d)", stats.pending, stats.additions, stats.deletions)
end

--- Get detailed statusline component (for lualine etc.)
---@return table|nil Component data
function M.statusline_component()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")

  if not patchview.state.enabled then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = patchview.state.buffers[bufnr]

  if not buf_state or not buf_state.watching then
    return nil
  end

  local hunk_count = #buf_state.hunks

  return {
    watching = true,
    hunks = hunk_count,
    stats = hunk_count > 0 and hunks_mod.get_stats(buf_state.hunks) or nil,
  }
end

--- Get status for a specific buffer
---@param bufnr number Buffer number
---@return table Status info
function M.get_buffer_status(bufnr)
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")
  local watcher = require("patchview.watcher")

  local buf_state = patchview.state.buffers[bufnr]
  local is_watching = watcher.is_watching(bufnr)

  local status = {
    bufnr = bufnr,
    filename = buf_state and buf_state.filename or vim.api.nvim_buf_get_name(bufnr),
    watching = is_watching,
    hunks = buf_state and #buf_state.hunks or 0,
    stats = nil,
  }

  if buf_state and #buf_state.hunks > 0 then
    status.stats = hunks_mod.get_stats(buf_state.hunks)
  end

  return status
end

--- Get global status
---@return table Global status info
function M.get_global_status()
  local patchview = require("patchview")
  local watcher = require("patchview.watcher")
  local config = require("patchview.config")

  local watched = watcher.get_watched_buffers()
  local total_hunks = 0

  for _, bufnr in ipairs(watched) do
    local buf_state = patchview.state.buffers[bufnr]
    if buf_state then
      total_hunks = total_hunks + #buf_state.hunks
    end
  end

  return {
    enabled = patchview.state.enabled,
    mode = config.options.mode,
    git_aware = config.options.git.enabled,
    watched_buffers = #watched,
    total_hunks = total_hunks,
  }
end

return M
