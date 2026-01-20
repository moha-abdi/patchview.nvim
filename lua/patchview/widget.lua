-- patchview.nvim - Inline action widget module
-- Shows Accept/Reject actions inline when cursor is on a hunk (like Cursor IDE)

local M = {}

-- Namespace for widget extmarks
M.namespace = nil

-- State for inline widgets per buffer
M.state = {}

-- Augroup for widget autocmds
M.augroup = nil

--- Initialize widget module
function M.setup()
  M.namespace = vim.api.nvim_create_namespace("patchview_widget")
  M.augroup = vim.api.nvim_create_augroup("patchview_widget", { clear = true })

  -- Define highlight groups for the inline widget
  local function set_hl(name, opts)
    vim.api.nvim_set_hl(0, name, opts)
  end

  -- Get Normal background to use for widget (prevents color bleeding)
  local normal_bg = vim.api.nvim_get_hl(0, { name = "Normal" }).bg

  -- Accept button styling (green tones)
  set_hl("PatchviewAcceptKey", { fg = "#2ecc71", bg = normal_bg, bold = true })
  set_hl("PatchviewAcceptText", { fg = "#27ae60", bg = normal_bg })

  -- Reject button styling (red tones)
  set_hl("PatchviewRejectKey", { fg = "#e74c3c", bg = normal_bg, bold = true })
  set_hl("PatchviewRejectText", { fg = "#c0392b", bg = normal_bg })

  -- Separator/dimmed text
  set_hl("PatchviewWidgetDim", { fg = "#7f8c8d", bg = normal_bg })
end

--- Show widget system for a buffer (sets up autocmds to show/hide based on cursor)
---@param bufnr number Buffer number
---@param hunks table[] List of hunks
function M.show(bufnr, hunks)
  -- Clear existing state
  M.hide(bufnr)

  if not hunks or #hunks == 0 then
    return
  end

  -- Filter to only pending hunks
  local pending_hunks = vim.tbl_filter(function(h)
    return h.status == "pending"
  end, hunks)

  if #pending_hunks == 0 then
    return
  end

  -- Initialize state for this buffer
  M.state[bufnr] = {
    current_extmark = nil,
    pending = pending_hunks,
  }

  -- Set up autocmd to show/hide widget based on cursor position
  M._setup_cursor_autocmd(bufnr)

  -- Show widget for current position immediately
  M._update_widget_for_cursor(bufnr)
end

--- Hide all inline widgets for a buffer
---@param bufnr number Buffer number
function M.hide(bufnr)
  -- Clear extmarks
  if M.namespace and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
  end

  -- Clear autocmds for this buffer
  if M.augroup then
    pcall(vim.api.nvim_clear_autocmds, {
      group = M.augroup,
      buffer = bufnr,
    })
  end

  -- Clear state
  M.state[bufnr] = nil
end

--- Hide all widgets in all buffers
function M.hide_all()
  for bufnr, _ in pairs(M.state) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.hide(bufnr)
    end
  end
  M.state = {}
end

--- Set up autocmd to update widget when cursor moves
---@param bufnr number Buffer number
function M._setup_cursor_autocmd(bufnr)
  if not M.augroup then
    M.augroup = vim.api.nvim_create_augroup("patchview_widget", { clear = true })
  end

  -- Clear existing autocmds for this buffer
  pcall(vim.api.nvim_clear_autocmds, {
    group = M.augroup,
    buffer = bufnr,
  })

  -- Update widget on cursor move
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = M.augroup,
    buffer = bufnr,
    callback = function()
      M._update_widget_for_cursor(bufnr)
    end,
    desc = "Patchview: Update widget on cursor move",
  })

  -- Hide widget on buffer leave
  vim.api.nvim_create_autocmd("BufLeave", {
    group = M.augroup,
    buffer = bufnr,
    callback = function()
      if M.namespace and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
      end
    end,
    desc = "Patchview: Hide widget on buffer leave",
  })

  -- Show widget again on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = M.augroup,
    buffer = bufnr,
    callback = function()
      M._update_widget_for_cursor(bufnr)
    end,
    desc = "Patchview: Show widget on buffer enter",
  })
end

--- Update widget based on current cursor position
---@param bufnr number Buffer number
function M._update_widget_for_cursor(bufnr)
  local state = M.state[bufnr]
  if not state then
    return
  end

  -- Clear existing widget
  if M.namespace and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
  end

  -- Get current cursor line
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]

  -- Find if cursor is on a hunk
  local hunks_mod = require("patchview.hunks")
  local current_hunk = nil

  for _, hunk in ipairs(state.pending) do
    local start_line, end_line = hunks_mod.get_line_range(hunk)
    if cursor_line >= start_line and cursor_line <= end_line then
      current_hunk = hunk
      break
    end
  end

  -- Only show widget if cursor is on a hunk
  if current_hunk then
    M._create_inline_widget(bufnr, current_hunk)
  end
end

--- Create an inline widget for a hunk (right-aligned on line after hunk)
---@param bufnr number Buffer number
---@param hunk table Hunk data
function M._create_inline_widget(bufnr, hunk)
  local hunks_mod = require("patchview.hunks")
  local config = require("patchview.config")

  -- Get the end line of the hunk
  local _, end_line = hunks_mod.get_line_range(hunk)

  -- Clamp to valid buffer range
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  end_line = math.min(end_line, line_count)
  end_line = math.max(end_line, 1)

  -- Target line is the line AFTER the hunk
  local target_line = end_line + 1

  -- Get keymaps from config  
  local keymaps = config.options.keymaps or {}
  local accept_key = keymaps.accept_hunk or "<leader>pa"
  local reject_key = keymaps.reject_hunk or "<leader>pr"

  -- Format key display (make it readable)
  local function format_key(key)
    if not key or key == false then
      return ""
    end
    -- Make leader notation more readable
    key = key:gsub("<leader>", "SPC ")
    key = key:gsub("<CR>", "RET")
    key = key:gsub("<Tab>", "TAB")
    key = key:gsub("<Esc>", "ESC")
    return key
  end

  local accept_key_display = format_key(accept_key)
  local reject_key_display = format_key(reject_key)

  -- Build the virtual text content (right-aligned)
  -- Style: "✓ Accept (SPC pa)  ✗ Reject (SPC pr)"
  local virt_text = {
    { "  ", "PatchviewWidgetDim" },
    { "✓ ", "PatchviewAcceptKey" },
    { "Accept", "PatchviewAcceptText" },
    { " (", "PatchviewWidgetDim" },
    { accept_key_display, "PatchviewAcceptKey" },
    { ")  ", "PatchviewWidgetDim" },
    { "✗ ", "PatchviewRejectKey" },
    { "Reject", "PatchviewRejectText" },
    { " (", "PatchviewWidgetDim" },
    { reject_key_display, "PatchviewRejectKey" },
    { ")", "PatchviewWidgetDim" },
  }

  -- Check if target line exists in buffer
  if target_line <= line_count then
    -- Line exists - put virtual text at the end of that line (right-aligned)
    vim.api.nvim_buf_set_extmark(bufnr, M.namespace, target_line - 1, 0, {
      virt_text = virt_text,
      virt_text_pos = "right_align",
    })
  else
    -- No line after hunk (end of file) - create virtual line below
    vim.api.nvim_buf_set_extmark(bufnr, M.namespace, end_line - 1, 0, {
      virt_lines = { virt_text },
      virt_lines_above = false,
    })
  end
end

--- Update widgets when hunks change
---@param bufnr number Buffer number
---@param hunks table[] Updated list of hunks
function M.update(bufnr, hunks)
  M.show(bufnr, hunks)
end

--- Toggle the widget display for the current buffer
function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  local patchview = require("patchview")

  if M.state[bufnr] then
    M.hide(bufnr)
  else
    local buf_state = patchview.state.buffers[bufnr]
    if buf_state and #buf_state.hunks > 0 then
      M.show(bufnr, buf_state.hunks)
    end
  end
end

return M
