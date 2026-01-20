-- patchview.nvim - User notifications module
-- Handles user notifications and messages

local M = {}

-- Runtime quiet mode state (can be toggled independently of config)
M._quiet_mode = false

--- Initialize notify module with config
---@param config table Configuration table
function M.setup(config)
  M._quiet_mode = config.options.notify.quiet_mode or false
end

--- Check if quiet mode is enabled
---@return boolean True if quiet mode is active
function M.is_quiet()
  return M._quiet_mode
end

--- Set quiet mode state
---@param enabled boolean Whether to enable quiet mode
function M.set_quiet(enabled)
  M._quiet_mode = enabled
end

--- Toggle quiet mode
---@return boolean New quiet mode state
function M.toggle_quiet()
  M._quiet_mode = not M._quiet_mode
  return M._quiet_mode
end

--- Internal notification function that respects quiet mode
---@param msg string Message to display
---@param level number Log level (vim.log.levels)
local function notify_if_not_quiet(msg, level)
  if not M._quiet_mode then
    vim.notify(msg, level)
  end
end

--- Notify that changes were detected
---@param bufnr number Buffer number
---@param hunk_count number Number of hunks detected
function M.change_detected(bufnr, hunk_count)
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  local msg = string.format("Patchview: %d change(s) detected in %s", hunk_count, filename)
  notify_if_not_quiet(msg, vim.log.levels.INFO)
end

--- Notify that a hunk was accepted
function M.hunk_accepted()
  notify_if_not_quiet("Patchview: Hunk accepted", vim.log.levels.INFO)
end

--- Notify that a hunk was rejected
function M.hunk_rejected()
  notify_if_not_quiet("Patchview: Hunk rejected", vim.log.levels.INFO)
end

--- Notify that watching started
---@param bufnr number Buffer number
function M.watching_started(bufnr)
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  notify_if_not_quiet(string.format("Patchview: Watching %s", filename), vim.log.levels.INFO)
end

--- Notify that watching stopped
---@param bufnr number Buffer number
function M.watching_stopped(bufnr)
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  notify_if_not_quiet(string.format("Patchview: Stopped watching %s", filename), vim.log.levels.INFO)
end

--- Notify an error (errors are never suppressed by quiet mode)
---@param msg string Error message
function M.error(msg)
  -- Errors are always shown, even in quiet mode
  vim.notify("Patchview: " .. msg, vim.log.levels.ERROR)
end

--- Notify a warning (warnings are never suppressed by quiet mode)
---@param msg string Warning message
function M.warn(msg)
  -- Warnings are always shown, even in quiet mode
  vim.notify("Patchview: " .. msg, vim.log.levels.WARN)
end

--- Notify info
---@param msg string Info message
function M.info(msg)
  notify_if_not_quiet("Patchview: " .. msg, vim.log.levels.INFO)
end

--- Show a more prominent notification (using floating window)
--- Respects quiet mode
---@param title string Notification title
---@param lines string[] Notification content
---@param level number|nil Log level (default INFO)
function M.show_floating(title, lines, level)
  if M._quiet_mode then
    return
  end

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
