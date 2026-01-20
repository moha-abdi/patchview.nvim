-- patchview.nvim - User notifications module
-- Handles user notifications and messages

local M = {}

--- Notify that changes were detected
---@param bufnr number Buffer number
---@param hunk_count number Number of hunks detected
function M.change_detected(bufnr, hunk_count)
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  local msg = string.format("Patchview: %d change(s) detected in %s", hunk_count, filename)
  vim.notify(msg, vim.log.levels.INFO)
end

--- Notify that a hunk was accepted
function M.hunk_accepted()
  vim.notify("Patchview: Hunk accepted", vim.log.levels.INFO)
end

--- Notify that a hunk was rejected
function M.hunk_rejected()
  vim.notify("Patchview: Hunk rejected", vim.log.levels.INFO)
end

--- Notify that watching started
---@param bufnr number Buffer number
function M.watching_started(bufnr)
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  vim.notify(string.format("Patchview: Watching %s", filename), vim.log.levels.INFO)
end

--- Notify that watching stopped
---@param bufnr number Buffer number
function M.watching_stopped(bufnr)
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  vim.notify(string.format("Patchview: Stopped watching %s", filename), vim.log.levels.INFO)
end

--- Notify an error
---@param msg string Error message
function M.error(msg)
  vim.notify("Patchview: " .. msg, vim.log.levels.ERROR)
end

--- Notify a warning
---@param msg string Warning message
function M.warn(msg)
  vim.notify("Patchview: " .. msg, vim.log.levels.WARN)
end

--- Notify info
---@param msg string Info message
function M.info(msg)
  vim.notify("Patchview: " .. msg, vim.log.levels.INFO)
end

--- Show a more prominent notification (using floating window)
---@param title string Notification title
---@param lines string[] Notification content
---@param level number|nil Log level (default INFO)
function M.show_floating(title, lines, level)
  level = level or vim.log.levels.INFO

  -- Determine highlight based on level
  local hl = "Normal"
  if level == vim.log.levels.ERROR then
    hl = "ErrorMsg"
  elseif level == vim.log.levels.WARN then
    hl = "WarningMsg"
  end

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  local content = { title, string.rep("-", #title), "" }
  vim.list_extend(content, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].modifiable = false

  -- Calculate size
  local width = #title + 4
  for _, line in ipairs(lines) do
    width = math.max(width, #line + 4)
  end
  local height = #content + 2

  -- Position in top-right corner
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = 1,
    col = vim.o.columns - width - 2,
    style = "minimal",
    border = "rounded",
  }

  local win = vim.api.nvim_open_win(buf, false, opts)

  -- Auto-close after delay
  vim.defer_fn(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, 3000)
end

return M
