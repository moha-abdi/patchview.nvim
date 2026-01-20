-- patchview.nvim - Preview mode logic module
-- Handles preview mode display and interactions

local M = {}

-- Preview window state
M.preview_win = nil
M.preview_buf = nil

-- Split diff state
M.split_diff_win = nil
M.split_diff_buf = nil
M.split_diff_source_win = nil

--- Show a floating preview window for a hunk
---@param hunk table Hunk object
function M.show_hunk_preview(hunk)
  local hunks_mod = require("patchview.hunks")

  -- Get diff lines
  local lines = hunks_mod.to_unified_diff(hunk)

  -- Add some context
  table.insert(lines, 1, string.format("Hunk: %s (%d lines)", hunk.type, hunk.new_count + hunk.old_count))
  table.insert(lines, 2, "")

  -- Create or reuse buffer
  if not M.preview_buf or not vim.api.nvim_buf_is_valid(M.preview_buf) then
    M.preview_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.preview_buf].buftype = "nofile"
    vim.bo[M.preview_buf].filetype = "diff"
  end

  -- Set content
  vim.api.nvim_buf_set_lines(M.preview_buf, 0, -1, false, lines)

  -- Calculate window size
  local width = 60
  local height = math.min(#lines, 20)

  for _, line in ipairs(lines) do
    width = math.max(width, #line + 4)
  end
  width = math.min(width, 80)

  -- Get editor dimensions
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines

  -- Calculate position (centered)
  local row = math.floor((editor_height - height) / 2)
  local col = math.floor((editor_width - width) / 2)

  -- Window options
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Patchview Preview ",
    title_pos = "center",
  }

  -- Create or update window
  if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
    vim.api.nvim_win_set_config(M.preview_win, opts)
  else
    M.preview_win = vim.api.nvim_open_win(M.preview_buf, false, opts)
    vim.wo[M.preview_win].wrap = false
    vim.wo[M.preview_win].cursorline = true
  end

  -- Apply syntax highlighting
  M._highlight_preview()
end

--- Close the preview window
function M.close_preview()
  if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
    vim.api.nvim_win_close(M.preview_win, true)
    M.preview_win = nil
  end
end

--- Toggle preview window
---@param hunk table|nil Hunk to preview (nil to close)
function M.toggle_preview(hunk)
  if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
    M.close_preview()
  elseif hunk then
    M.show_hunk_preview(hunk)
  end
end

--- Apply syntax highlighting to preview buffer
function M._highlight_preview()
  if not M.preview_buf or not vim.api.nvim_buf_is_valid(M.preview_buf) then
    return
  end

  local ns = vim.api.nvim_create_namespace("patchview_preview_hl")
  vim.api.nvim_buf_clear_namespace(M.preview_buf, ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(M.preview_buf, 0, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^%+") and not line:match("^%+%+%+") then
      vim.api.nvim_buf_set_extmark(M.preview_buf, ns, i - 1, 0, {
        end_row = i - 1,
        end_col = #line,
        hl_group = "DiffAdd",
        hl_eol = true,
      })
    elseif line:match("^%-") and not line:match("^%-%-%-") then
      vim.api.nvim_buf_set_extmark(M.preview_buf, ns, i - 1, 0, {
        end_row = i - 1,
        end_col = #line,
        hl_group = "DiffDelete",
        hl_eol = true,
      })
    elseif line:match("^@@") then
      vim.api.nvim_buf_set_extmark(M.preview_buf, ns, i - 1, 0, {
        end_row = i - 1,
        end_col = #line,
        hl_group = "DiffChange",
        hl_eol = true,
      })
    end
  end
end

--- Check if split diff view is currently open
---@return boolean True if split diff is open
function M.is_split_diff_open()
  return M.split_diff_win ~= nil and vim.api.nvim_win_is_valid(M.split_diff_win)
end

--- Show a split diff view showing old (baseline) vs new (current) content
--- Opens the baseline content in a vertical split on the left with Neovim's diff mode
---@param bufnr number|nil Buffer number (defaults to current buffer)
function M.show_split_diff(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Close existing split diff first
  if M.is_split_diff_open() then
    M.close_split_diff()
  end
  
  -- Get original content
  local patchview = require("patchview")
  local buf_state = patchview.state.buffers[bufnr]

  if not buf_state or not buf_state.baseline then
    vim.notify("Patchview: No baseline available for split view", vim.log.levels.WARN)
    return
  end

  -- Store source window
  M.split_diff_source_win = vim.api.nvim_get_current_win()
  
  -- Get current cursor position to sync later
  local cursor = vim.api.nvim_win_get_cursor(0)

  -- Create a temporary buffer with old content
  local old_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(old_buf, 0, -1, false, buf_state.baseline)
  vim.bo[old_buf].buftype = "nofile"
  vim.bo[old_buf].bufhidden = "wipe"
  vim.bo[old_buf].modifiable = false
  vim.bo[old_buf].swapfile = false
  
  -- Set buffer name for identification
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local short_name = vim.fn.fnamemodify(filename, ":t")
  vim.api.nvim_buf_set_name(old_buf, "[Patchview] " .. short_name .. " (baseline)")

  -- Get current buffer filetype for syntax highlighting
  local ft = vim.bo[bufnr].filetype
  vim.bo[old_buf].filetype = ft

  -- Store the buffer
  M.split_diff_buf = old_buf

  -- Open in vertical split to the left
  vim.cmd("leftabove vsplit")
  M.split_diff_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.split_diff_win, old_buf)

  -- Enable diff mode in both windows
  vim.cmd("diffthis")
  vim.cmd("wincmd p")  -- Go back to source window
  vim.cmd("diffthis")

  -- Set up buffer-local keymap to close the split diff with 'q' in the old buffer
  vim.api.nvim_buf_set_keymap(old_buf, "n", "q", 
    "<cmd>lua require('patchview.preview').close_split_diff()<CR>",
    { noremap = true, silent = true, desc = "Close split diff" })

  -- Jump to the same line in both windows (diff mode syncs scrolling)
  -- First set cursor in source window
  pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  
  -- Then sync cursor in old content window
  vim.api.nvim_set_current_win(M.split_diff_win)
  local old_line_count = vim.api.nvim_buf_line_count(old_buf)
  local target_line = math.min(cursor[1], old_line_count)
  pcall(vim.api.nvim_win_set_cursor, M.split_diff_win, { target_line, 0 })
  
  -- Return focus to source window
  vim.api.nvim_set_current_win(M.split_diff_source_win)
  
  -- Jump to first diff if there are changes
  vim.cmd("normal! ]c")
end

--- Close split diff view
function M.close_split_diff()
  -- Disable diff mode in all windows
  vim.cmd("diffoff!")
  
  -- Close the split diff window if it exists
  if M.split_diff_win and vim.api.nvim_win_is_valid(M.split_diff_win) then
    vim.api.nvim_win_close(M.split_diff_win, true)
  end
  
  -- Clean up the buffer (should be auto-wiped due to bufhidden=wipe, but just in case)
  if M.split_diff_buf and vim.api.nvim_buf_is_valid(M.split_diff_buf) then
    vim.api.nvim_buf_delete(M.split_diff_buf, { force = true })
  end
  
  -- Reset state
  M.split_diff_win = nil
  M.split_diff_buf = nil
  M.split_diff_source_win = nil
end

--- Toggle split diff view
---@param bufnr number|nil Buffer number (defaults to current buffer)
function M.toggle_split_diff(bufnr)
  if M.is_split_diff_open() then
    M.close_split_diff()
  else
    M.show_split_diff(bufnr)
  end
end

return M
