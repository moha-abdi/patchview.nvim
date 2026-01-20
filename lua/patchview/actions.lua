-- patchview.nvim - User action handlers module
-- Handles accept/reject/navigation actions

local M = {}

--- Navigate to the next hunk
function M.next_hunk()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")
  local render = require("patchview.render")

  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = patchview.state.buffers[bufnr]

  if not buf_state or #buf_state.hunks == 0 then
    vim.notify("Patchview: No hunks in current buffer", vim.log.levels.INFO)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = hunks_mod.get_next(buf_state.hunks, line)

  if hunk then
    local start_line, _ = hunks_mod.get_line_range(hunk)
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    render.highlight_hunk(bufnr, hunk)
  end
end

--- Navigate to the previous hunk
function M.prev_hunk()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")
  local render = require("patchview.render")

  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = patchview.state.buffers[bufnr]

  if not buf_state or #buf_state.hunks == 0 then
    vim.notify("Patchview: No hunks in current buffer", vim.log.levels.INFO)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = hunks_mod.get_prev(buf_state.hunks, line)

  if hunk then
    local start_line, _ = hunks_mod.get_line_range(hunk)
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    render.highlight_hunk(bufnr, hunk)
  end
end

--- Accept the current hunk (at cursor position)
function M.accept_hunk()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")
  local render = require("patchview.render")
  local config = require("patchview.config")
  local notify_mod = require("patchview.notify")

  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = patchview.state.buffers[bufnr]

  if not buf_state or #buf_state.hunks == 0 then
    vim.notify("Patchview: No hunks in current buffer", vim.log.levels.INFO)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = hunks_mod.get_at_line(buf_state.hunks, line)

  if not hunk then
    -- Try to find the nearest hunk
    hunk = hunks_mod.get_next(buf_state.hunks, line - 1)
  end

  if hunk and hunk.status == "pending" then
    -- In preview mode, apply the change
    if config.options.mode == "preview" then
      M._apply_hunk(bufnr, hunk)
    end

    -- Mark as accepted
    hunks_mod.accept(hunk)

    -- Update rendering
    render.show_hunks(bufnr, buf_state.hunks, "pending")

    -- Update widget if enabled
    if config.options.widget and config.options.widget.enabled then
      local widget = require("patchview.widget")
      -- Filter pending hunks and update widget
      local pending = vim.tbl_filter(function(h)
        return h.status == "pending"
      end, buf_state.hunks)
      if #pending == 0 then
        widget.hide(bufnr)
      else
        widget.show(bufnr, buf_state.hunks)
      end
    end

    -- Notify if enabled
    if config.options.notify.on_accept then
      notify_mod.hunk_accepted()
    end

    -- Move to next hunk
    M.next_hunk()
  else
    vim.notify("Patchview: No pending hunk at cursor", vim.log.levels.INFO)
  end
end

--- Reject the current hunk (at cursor position)
function M.reject_hunk()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")
  local render = require("patchview.render")
  local config = require("patchview.config")
  local notify_mod = require("patchview.notify")

  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = patchview.state.buffers[bufnr]

  if not buf_state or #buf_state.hunks == 0 then
    vim.notify("Patchview: No hunks in current buffer", vim.log.levels.INFO)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = hunks_mod.get_at_line(buf_state.hunks, line)

  if not hunk then
    hunk = hunks_mod.get_next(buf_state.hunks, line - 1)
  end

  if hunk and hunk.status == "pending" then
    -- In preview mode, revert the change
    if config.options.mode == "preview" then
      M._revert_hunk(bufnr, hunk)
    end

    -- Mark as rejected
    hunks_mod.reject(hunk)

    -- Update rendering
    render.show_hunks(bufnr, buf_state.hunks, "pending")

    -- Update widget if enabled
    if config.options.widget and config.options.widget.enabled then
      local widget = require("patchview.widget")
      -- Filter pending hunks and update widget
      local pending = vim.tbl_filter(function(h)
        return h.status == "pending"
      end, buf_state.hunks)
      if #pending == 0 then
        widget.hide(bufnr)
      else
        widget.show(bufnr, buf_state.hunks)
      end
    end

    -- Notify if enabled
    if config.options.notify.on_reject then
      notify_mod.hunk_rejected()
    end

    -- Move to next hunk
    M.next_hunk()
  else
    vim.notify("Patchview: No pending hunk at cursor", vim.log.levels.INFO)
  end
end

--- Accept all pending hunks
function M.accept_all()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")
  local render = require("patchview.render")
  local config = require("patchview.config")
  local notify_mod = require("patchview.notify")

  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = patchview.state.buffers[bufnr]

  if not buf_state or #buf_state.hunks == 0 then
    vim.notify("Patchview: No hunks in current buffer", vim.log.levels.INFO)
    return
  end

  local pending = hunks_mod.get_pending(buf_state.hunks)
  if #pending == 0 then
    vim.notify("Patchview: No pending hunks", vim.log.levels.INFO)
    return
  end

  -- In preview mode, apply all changes
  if config.options.mode == "preview" then
    -- Apply in reverse order to maintain line numbers
    for i = #pending, 1, -1 do
      M._apply_hunk(bufnr, pending[i])
    end
  end

  -- Mark all as accepted
  for _, hunk in ipairs(pending) do
    hunks_mod.accept(hunk)
  end

  -- Clear rendering
  render.clear(bufnr)

  -- Update baseline
  patchview._take_buffer_snapshot(bufnr)
  buf_state.hunks = {}

  vim.notify(string.format("Patchview: Accepted %d hunks", #pending), vim.log.levels.INFO)
end

--- Reject all pending hunks
function M.reject_all()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")
  local render = require("patchview.render")
  local config = require("patchview.config")

  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = patchview.state.buffers[bufnr]

  if not buf_state or #buf_state.hunks == 0 then
    vim.notify("Patchview: No hunks in current buffer", vim.log.levels.INFO)
    return
  end

  local pending = hunks_mod.get_pending(buf_state.hunks)
  if #pending == 0 then
    vim.notify("Patchview: No pending hunks", vim.log.levels.INFO)
    return
  end

  -- In preview mode, revert all changes
  if config.options.mode == "preview" then
    -- Revert in reverse order to maintain line numbers
    for i = #pending, 1, -1 do
      M._revert_hunk(bufnr, pending[i])
    end
  else
    -- In auto mode, restore from baseline
    if buf_state.baseline then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buf_state.baseline)
    end
  end

  -- Mark all as rejected
  for _, hunk in ipairs(pending) do
    hunks_mod.reject(hunk)
  end

  -- Clear rendering
  render.clear(bufnr)
  buf_state.hunks = {}

  vim.notify(string.format("Patchview: Rejected %d hunks", #pending), vim.log.levels.INFO)
end

--- Apply a single hunk to the buffer
---@param bufnr number Buffer number
---@param hunk table Hunk object
function M._apply_hunk(bufnr, hunk)
  -- This is called in preview mode to apply changes
  -- In auto mode, changes are already applied via checktime

  if hunk.type == "add" then
    -- Insert new lines
    vim.api.nvim_buf_set_lines(bufnr, hunk.new_start - 1, hunk.new_start - 1, false, hunk.new_lines)
  elseif hunk.type == "delete" then
    -- Remove old lines
    vim.api.nvim_buf_set_lines(bufnr, hunk.old_start - 1, hunk.old_start - 1 + hunk.old_count, false, {})
  elseif hunk.type == "change" then
    -- Replace old lines with new lines
    vim.api.nvim_buf_set_lines(bufnr, hunk.old_start - 1, hunk.old_start - 1 + hunk.old_count, false, hunk.new_lines)
  end
end

--- Revert a single hunk in the buffer
---@param bufnr number Buffer number
---@param hunk table Hunk object
function M._revert_hunk(bufnr, hunk)
  if hunk.type == "add" then
    -- Remove added lines
    vim.api.nvim_buf_set_lines(bufnr, hunk.new_start - 1, hunk.new_start - 1 + hunk.new_count, false, {})
  elseif hunk.type == "delete" then
    -- Restore deleted lines
    vim.api.nvim_buf_set_lines(bufnr, hunk.old_start - 1, hunk.old_start - 1, false, hunk.old_lines)
  elseif hunk.type == "change" then
    -- Restore old lines
    vim.api.nvim_buf_set_lines(bufnr, hunk.new_start - 1, hunk.new_start - 1 + hunk.new_count, false, hunk.old_lines)
  end
end

--- Undo the last action
function M.undo()
  -- Use Neovim's built-in undo
  vim.cmd("undo")
end

return M
