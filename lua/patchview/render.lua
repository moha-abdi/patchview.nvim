-- patchview.nvim - Visual rendering module
-- Handles extmark-based inline highlighting and virtual text

local M = {}

-- Namespace for extmarks
M.namespace = nil

-- Active extmarks per buffer: { [bufnr] = { extmark_ids... } }
M.extmarks = {}

-- Topfill state per buffer: { [bufnr] = number_of_virtual_lines_above_row_0 }
-- WORKAROUND for neovim/neovim#16166: virt_lines_above doesn't render on row 0.
-- We use winrestview({ topfill = N }) to scroll viewport and reveal virtual lines.
-- See: https://github.com/neovim/neovim/issues/16166
M.topfill = {}

-- Augroup for topfill maintenance autocmds
M.augroup = nil

--- Initialize render module
function M.setup()
  M.namespace = vim.api.nvim_create_namespace("patchview_render")
  M.augroup = vim.api.nvim_create_augroup("patchview_topfill", { clear = true })
end

--- Get or create namespace
---@return number Namespace ID
local function get_namespace()
  if not M.namespace then
    M.namespace = vim.api.nvim_create_namespace("patchview_render")
  end
  return M.namespace
end

--- Show hunks in a buffer
---@param bufnr number Buffer number
---@param hunks table[] Hunk objects
---@param mode string "pending"|"applied" Display mode
function M.show_hunks(bufnr, hunks, mode)
  local config = require("patchview.config")
  local highlights = require("patchview.highlights")
  local signs = require("patchview.signs")

  -- Clear existing marks (also clears topfill state and autocmds)
  M.clear(bufnr)

  -- Update density indicators if enabled
  if config.options.density.enabled then
    local density = require("patchview.density")
    density.update(bufnr, hunks)
  end

  local ns = get_namespace()
  M.extmarks[bufnr] = M.extmarks[bufnr] or {}

  local render_style = config.options.render.style or "inline"
  local show_virtual = config.options.render.show_removed_virtual
  
  -- Track total topfill needed (virtual lines above row 0)
  local total_topfill = 0

  for _, hunk in ipairs(hunks) do
    if hunk.status == "pending" or mode == "applied" then
      local hl_mode = mode == "applied" and "applied" or "preview"

      -- Add signs only if using "signs" style alone (inline style uses extmark signs)
      if render_style == "signs" then
        signs.place_for_hunk(bufnr, hunk)
      end

      -- Add inline highlights (includes sign via extmark)
      -- Skip for pure deletes - there's no line in the buffer to highlight
      if render_style == "inline" or render_style == "both" then
        if hunk.type ~= "delete" then
          M._render_hunk_inline(bufnr, hunk, hl_mode, ns)
        end
      end

      -- Show removed lines as virtual text
      if show_virtual and (hunk.type == "delete" or hunk.type == "change") then
        local topfill_count = M._render_deleted_virtual(bufnr, hunk, ns)
        total_topfill = total_topfill + topfill_count
      end
    end
  end
  
  -- Apply topfill workaround if we have virtual lines above row 0
  -- This works around neovim/neovim#16166 where virt_lines_above doesn't show on row 0
  if total_topfill > 0 then
    M.topfill[bufnr] = total_topfill
    M._setup_topfill_autocmd(bufnr)
    M._apply_topfill(bufnr)
  end
  
  -- Force redraw to ensure virtual text is visible immediately
  -- Use defer to ensure we're outside any textlock and redraw! for forced update
  vim.defer_fn(function()
    vim.cmd("redraw!")
  end, 1)
end

--- Render a hunk with inline highlighting
---@param bufnr number Buffer number
---@param hunk table Hunk object
---@param mode string "preview"|"applied"
---@param ns number Namespace
function M._render_hunk_inline(bufnr, hunk, mode, ns)
  local highlights = require("patchview.highlights")
  local hunks_mod = require("patchview.hunks")

  -- For "change" hunks, new lines should show as ADD (green), not CHANGE (yellow)
  -- The deleted lines are shown as virtual text separately
  local hl_type = hunk.type
  if hl_type == "change" then
    hl_type = "add"  -- New lines in a change are additions
  end
  
  local hl_group = highlights.get_hl_group(hl_type, mode)
  local linenr_hl_group = highlights.get_linenr_hl(hl_type)
  local sign_hl_group = highlights.get_sign_hl(hl_type)
  local start_line, end_line = hunks_mod.get_line_range(hunk)

  -- Ensure lines are valid
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  start_line = math.max(1, math.min(start_line, line_count))
  end_line = math.max(1, math.min(end_line, line_count))

  -- Highlight full line: sign column + line number + text area
  for line = start_line, end_line do
    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
      sign_text = "┃",
      sign_hl_group = sign_hl_group,      -- Sign with bg to fill sign column
      line_hl_group = hl_group,           -- Text area highlight  
      number_hl_group = linenr_hl_group,  -- Line number highlight
      priority = 100,
    })
    table.insert(M.extmarks[bufnr], extmark_id)
  end
end

--- Render deleted lines as virtual text
---@param bufnr number Buffer number
---@param hunk table Hunk object
---@param ns number Namespace
---@return number Number of virtual lines added above row 0 (for topfill workaround)
function M._render_deleted_virtual(bufnr, hunk, ns)
  if #hunk.old_lines == 0 then
    return 0
  end

  -- Position virtual text at the start of the hunk
  local line = hunk.new_start
  if hunk.type == "delete" then
    line = hunk.old_start
  end

  -- Ensure line is valid
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  line = math.max(1, math.min(line, line_count))

  -- Get window info for exact gutter dimensions
  local win = vim.api.nvim_get_current_win()
  local win_width = vim.api.nvim_win_get_width(win)
  local win_info = vim.fn.getwininfo(win)[1]
  
  -- textoff is the exact number of columns used by gutter (signs + line numbers + fold)
  local textoff = win_info.textoff or 0
  local show_numbers = vim.wo[win].number or vim.wo[win].relativenumber

  -- Create virtual lines for deleted content
  -- Match added lines: sign (fg only) + gap (no bg) + line number (bg) + content (bg)
  local sign_col_width = 2  -- sign column is 2 chars: ┃ + space
  local virt_lines = {}
  for i, old_line in ipairs(hunk.old_lines) do
    -- Calculate the old line number for this deleted line
    local old_lnum = hunk.old_start + i - 1
    
    -- Line number area width (textoff minus sign column)
    local linenr_width = textoff - sign_col_width
    local lnum_str = ""
    if show_numbers and linenr_width > 0 then
      -- Right-align number in available space, matching real line number format
      lnum_str = string.format("%" .. linenr_width .. "s", old_lnum .. " ")
    elseif linenr_width > 0 then
      lnum_str = string.rep(" ", linenr_width)
    end
    
    -- Content with trailing padding to fill window width
    local content = old_line
    local content_width = vim.fn.strdisplaywidth(content)
    local text_area_width = win_width - textoff
    local trailing_pad = text_area_width - content_width
    if trailing_pad > 0 then
      content = content .. string.rep(" ", trailing_pad)
    end
    
    -- Build virtual line matching added lines:
    -- ┃ (fg only) + space (no bg) + line_number (bg) + content (bg)
    table.insert(virt_lines, {
      { "┃", "PatchviewSignDelete" },
      { " ", "Normal" },
      { lnum_str, "PatchviewDeleteLineNr" },
      { content, "PatchviewDeleteLine" },
    })
  end

  -- Always use virt_lines_above = true for consistent positioning
  -- For line 1 (row 0), we'll use winrestview({ topfill = N }) workaround
  -- to make the virtual lines visible (neovim/neovim#16166)
  local anchor_line = line - 1
  local topfill_count = 0
  
  if line == 1 then
    -- Track how many virtual lines are above row 0 for topfill workaround
    topfill_count = #virt_lines
  end
  
  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, anchor_line, 0, {
    virt_lines = virt_lines,
    virt_lines_above = true,  -- Always above for consistent visual positioning
    virt_lines_leftcol = true,  -- Start at leftmost column (sign column area)
    priority = 90,
  })
  table.insert(M.extmarks[bufnr], extmark_id)
  
  return topfill_count
end

--- Apply topfill to make virtual lines above row 0 visible.
---
--- WORKAROUND: Neovim's `virt_lines_above = true` doesn't work on row 0.
--- Virtual lines placed "above" row 0 are rendered off-screen and invisible.
--- This is a known Neovim limitation tracked in:
---   - Issue: https://github.com/neovim/neovim/issues/16166
---   - PR: https://github.com/neovim/neovim/pull/15351
---
--- The workaround uses `winrestview({ topfill = N })` to scroll the viewport
--- and reveal the virtual lines. An autocmd maintains this on cursor movement.
--- Credit to MagicDuck and zeertzjq for discovering this workaround.
---
---@param bufnr number Buffer number
function M._apply_topfill(bufnr)
  local topfill = M.topfill[bufnr]
  if not topfill or topfill == 0 then
    return
  end
  
  -- Find windows showing this buffer
  local wins = vim.fn.win_findbuf(bufnr)
  for _, win in ipairs(wins) do
    -- Only apply if cursor is near the top (within first few lines)
    -- This prevents jarring scroll when user is elsewhere in the file
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local view = vim.fn.winsaveview()
    
    -- Apply topfill if we're viewing the top of the file
    if view.topline == 1 then
      vim.fn.win_execute(win, string.format(
        'lua vim.fn.winrestview({ topfill = %d })',
        topfill
      ))
    end
  end
end

--- Set up autocmd to maintain topfill on cursor movement
--- This ensures virtual lines above row 0 stay visible
---@param bufnr number Buffer number
function M._setup_topfill_autocmd(bufnr)
  if not M.augroup then
    M.augroup = vim.api.nvim_create_augroup("patchview_topfill", { clear = true })
  end
  
  -- Clear any existing autocmds for this buffer
  M._clear_topfill_autocmd(bufnr)
  
  -- Set up autocmd to maintain topfill
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinScrolled" }, {
    group = M.augroup,
    buffer = bufnr,
    callback = function()
      -- Only apply if we still have topfill state for this buffer
      if M.topfill[bufnr] and M.topfill[bufnr] > 0 then
        M._apply_topfill(bufnr)
      end
    end,
    desc = "Patchview: maintain topfill for virtual lines above row 0",
  })
end

--- Clear topfill autocmd for a buffer
---@param bufnr number Buffer number
function M._clear_topfill_autocmd(bufnr)
  if M.augroup then
    -- Clear autocmds for this specific buffer
    pcall(vim.api.nvim_clear_autocmds, {
      group = M.augroup,
      buffer = bufnr,
    })
  end
end

--- Clear all rendering in a buffer
---@param bufnr number Buffer number
function M.clear(bufnr)
  local ns = get_namespace()

  -- Clear extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  M.extmarks[bufnr] = {}

  -- Clear topfill state and autocmds
  M.topfill[bufnr] = nil
  M._clear_topfill_autocmd(bufnr)

  -- Clear signs
  local signs = require("patchview.signs")
  signs.clear(bufnr)

  -- Clear density indicators
  local density = require("patchview.density")
  density.clear(bufnr)
end

--- Clear all rendering in all buffers
function M.clear_all()
  local ns = get_namespace()
  for bufnr, _ in pairs(M.extmarks) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
    -- Clear topfill state and autocmds for each buffer
    M.topfill[bufnr] = nil
    M._clear_topfill_autocmd(bufnr)
  end
  M.extmarks = {}
  M.topfill = {}

  -- Clear the entire augroup
  if M.augroup then
    pcall(vim.api.nvim_clear_autocmds, { group = M.augroup })
  end

  local signs = require("patchview.signs")
  signs.clear_all()

  local density = require("patchview.density")
  density.clear_all()
end

--- Fade out highlights (for animation)
---@param bufnr number Buffer number
function M.fade_out(bufnr)
  local config = require("patchview.config")
  if not config.options.render.animation.enabled then
    M.clear(bufnr)
    return
  end

  -- Simple fade: just clear after a delay
  -- For true animation, would need to gradually change highlight colors
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.clear(bufnr)
    end
  end, config.options.render.animation.duration_ms)
end

--- Highlight a specific hunk (for navigation)
---@param bufnr number Buffer number
---@param hunk table Hunk object
function M.highlight_hunk(bufnr, hunk)
  local hunks_mod = require("patchview.hunks")
  local start_line, end_line = hunks_mod.get_line_range(hunk)

  -- Use a temporary highlight that fades
  local ns = get_namespace()
  for line = start_line, end_line do
    local line_content = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
    if line_content then
      vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
        end_row = line - 1,
        end_col = #line_content,
        hl_group = "Visual",
        hl_eol = true,
        priority = 200,
      })
    end
  end

  -- Clear highlight after a short delay
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      -- Just redraw the hunks to reset highlighting
      local patchview = require("patchview")
      if patchview.state.buffers[bufnr] then
        M.show_hunks(bufnr, patchview.state.buffers[bufnr].hunks, "pending")
      end
    end
  end, 200)
end

--- Get extmark info for debugging
---@param bufnr number Buffer number
---@return table[] Extmark info
function M.get_extmarks(bufnr)
  local ns = get_namespace()
  return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
end

return M
