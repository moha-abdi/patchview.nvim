-- patchview.nvim - User action handlers module
-- Handles accept/reject/navigation actions

local M = {}

-- Action history for undo functionality
-- Structure: { [bufnr] = { {action = "accept"|"reject", hunk = hunk_copy, prev_status = string} } }
local action_history = {}

--- Clear action history for a buffer
---@param bufnr number Buffer number
local function clear_history(bufnr)
  action_history[bufnr] = nil
end

--- Add an action to history
---@param bufnr number Buffer number
---@param action string "accept" or "reject"
---@param hunk table Hunk that was acted upon
local function push_history(bufnr, action, hunk)
  if not action_history[bufnr] then
    action_history[bufnr] = {}
  end
  -- Store a copy of the hunk with its previous state
  table.insert(action_history[bufnr], {
    action = action,
    hunk = vim.deepcopy(hunk),
    prev_status = hunk.status,
  })
end

--- Get the last action from history
---@param bufnr number Buffer number
---@return table|nil Last action entry
local function pop_history(bufnr)
  if not action_history[bufnr] or #action_history[bufnr] == 0 then
    return nil
  end
  return table.remove(action_history[bufnr])
end

--- Navigate to the next hunk (only pending hunks)
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

  -- Only navigate through pending hunks
  local pending = vim.tbl_filter(function(h)
    return h.status == "pending"
  end, buf_state.hunks)

  if #pending == 0 then
    vim.notify("Patchview: No pending hunks", vim.log.levels.INFO)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = hunks_mod.get_next(pending, line)

  if hunk then
    local start_line, _ = hunks_mod.get_line_range(hunk)
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    render.highlight_hunk(bufnr, hunk)
  end
end

--- Navigate to the previous hunk (only pending hunks)
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

  -- Only navigate through pending hunks
  local pending = vim.tbl_filter(function(h)
    return h.status == "pending"
  end, buf_state.hunks)

  if #pending == 0 then
    vim.notify("Patchview: No pending hunks", vim.log.levels.INFO)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = hunks_mod.get_prev(pending, line)

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
    -- Store previous state for undo
    local prev_status = hunk.status

    -- In preview mode, apply the change
    if config.options.mode == "preview" then
      M._apply_hunk(bufnr, hunk)
    end

    -- Mark as accepted
    hunks_mod.accept(hunk)

    -- Record action for undo
    push_history(bufnr, "accept", hunk)

    -- Check remaining pending hunks
    local pending = vim.tbl_filter(function(h)
      return h.status == "pending"
    end, buf_state.hunks)

    -- If no more pending hunks, update baseline and cleanup
    if #pending == 0 then
      patchview._take_buffer_snapshot(bufnr)
      buf_state.hunks = {}
      render.clear(bufnr)
      patchview._clear_buffer_nav_keymaps(bufnr)
    else
      -- Update rendering for remaining hunks
      render.show_hunks(bufnr, buf_state.hunks, "pending")
    end

    -- Update widget if enabled
    if config.options.widget and config.options.widget.enabled then
      local widget = require("patchview.widget")
      if #pending == 0 then
        widget.hide(bufnr)
      else
        widget.show(bufnr, buf_state.hunks)
      end
    end

    -- Always show feedback
    vim.notify("Patchview: Hunk accepted (" .. #pending .. " remaining)", vim.log.levels.INFO)

    -- Move to next hunk if there are more
    if #pending > 0 then
      M.next_hunk()
    end
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
    -- Store previous state for undo
    local prev_status = hunk.status

    -- Revert the hunk content (restore old lines)
    M._revert_hunk(bufnr, hunk)

    -- Mark as rejected
    hunks_mod.reject(hunk)

    -- Record action for undo
    push_history(bufnr, "reject", hunk)

    -- Check remaining pending hunks
    local pending = vim.tbl_filter(function(h)
      return h.status == "pending"
    end, buf_state.hunks)

    -- If no more pending hunks, update baseline and cleanup
    if #pending == 0 then
      patchview._take_buffer_snapshot(bufnr)
      buf_state.hunks = {}
      render.clear(bufnr)
      patchview._clear_buffer_nav_keymaps(bufnr)
    else
      -- Update rendering for remaining hunks
      render.show_hunks(bufnr, buf_state.hunks, "pending")
    end

    -- Update widget if enabled
    if config.options.widget and config.options.widget.enabled then
      local widget = require("patchview.widget")
      if #pending == 0 then
        widget.hide(bufnr)
      else
        widget.show(bufnr, buf_state.hunks)
      end
    end

    -- Always show feedback
    vim.notify("Patchview: Hunk rejected (" .. #pending .. " remaining)", vim.log.levels.INFO)

    -- Move to next hunk if there are more
    if #pending > 0 then
      M.next_hunk()
    end
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

  -- Clear undo history (accept all is a bulk action)
  clear_history(bufnr)

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

  -- Clear undo history (reject all is a bulk action)
  clear_history(bufnr)

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

--- Undo the last accept/reject action
function M.undo()
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

  -- Get the last action from history
  local last_action = pop_history(bufnr)

  if not last_action then
    vim.notify("Patchview: Nothing to undo", vim.log.levels.INFO)
    return
  end

  -- Find the current hunk by ID (the hunk in the buffer may have been modified)
  local hunk = hunks_mod.find_by_id(buf_state.hunks, last_action.hunk.id)

  if not hunk then
    -- Hunk may have been removed from the list
    -- We need to restore it
    hunk = last_action.hunk
    table.insert(buf_state.hunks, hunk)
  end

  -- Undo the action
  if last_action.action == "accept" then
    -- Undo accept: restore to pending
    hunk.status = "pending"

    -- In preview mode, revert the applied change
    if config.options.mode == "preview" then
      M._revert_hunk(bufnr, hunk)
    end

    notify_mod.info("Undid accept (hunk restored to pending)")
  elseif last_action.action == "reject" then
    -- Undo reject: restore to pending
    hunk.status = "pending"

    -- In preview mode, re-apply the rejected change
    if config.options.mode == "preview" then
      M._apply_hunk(bufnr, hunk)
    end

    notify_mod.info("Undid reject (hunk restored to pending)")
  end

  -- Update rendering
  render.show_hunks(bufnr, buf_state.hunks, "pending")

  -- Update widget if enabled
  if config.options.widget and config.options.widget.enabled then
    local widget = require("patchview.widget")
    local pending = vim.tbl_filter(function(h)
      return h.status == "pending"
    end, buf_state.hunks)
    if #pending == 0 then
      widget.hide(bufnr)
    else
      widget.show(bufnr, buf_state.hunks)
    end
  end

  -- Move cursor to the undone hunk
  local start_line, _ = hunks_mod.get_line_range(hunk)
  vim.api.nvim_win_set_cursor(0, { start_line, 0 })
  render.highlight_hunk(bufnr, hunk)
end

--- Clear action history (called on buffer write)
---@param bufnr number Buffer number
function M.clear_history(bufnr)
  clear_history(bufnr)
end

return M
