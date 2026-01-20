-- patchview.nvim - Preview mode logic module
-- Handles preview mode display and interactions

local M = {}

-- Preview window state
M.preview_win = nil
M.preview_buf = nil

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

--- Show a split diff view
---@param bufnr number Buffer number
---@param hunk table Hunk object
function M.show_split_diff(bufnr, hunk)
  -- Get original content
  local patchview = require("patchview")
  local buf_state = patchview.state.buffers[bufnr]

  if not buf_state or not buf_state.baseline then
    vim.notify("Patchview: No baseline available for split view", vim.log.levels.WARN)
    return
  end

  -- Create a temporary buffer with old content
  local old_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(old_buf, 0, -1, false, buf_state.baseline)
  vim.bo[old_buf].buftype = "nofile"
  vim.bo[old_buf].modifiable = false

  -- Get current buffer filetype for syntax
  local ft = vim.bo[bufnr].filetype
  vim.bo[old_buf].filetype = ft

  -- Open in vertical split
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, old_buf)

  -- Enable diff mode
  vim.cmd("diffthis")
  vim.cmd("wincmd p")
  vim.cmd("diffthis")

  -- Jump to hunk location
  local hunks_mod = require("patchview.hunks")
  local start_line, _ = hunks_mod.get_line_range(hunk)
  vim.api.nvim_win_set_cursor(0, { start_line, 0 })
end

--- Close split diff view
function M.close_split_diff()
  vim.cmd("diffoff!")
  -- Close the split if it's a patchview temp buffer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "nofile" then
      local name = vim.api.nvim_buf_get_name(buf)
      if name == "" then
        vim.api.nvim_win_close(win, true)
        break
      end
    end
  end
end

return M
