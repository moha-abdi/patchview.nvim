-- patchview.nvim - Floating action bar widget module
-- Shows navigation and quick actions near changes (like Cursor IDE)

local M = {}

-- Namespace for widget extmarks
M.namespace = nil

-- State for the floating widget per buffer
M.state = {}

-- Augroup for widget autocmds
M.augroup = nil

-- Widget content templates
local widget_content = {
  -- Navigation buttons
  prev_btn = { text = "◀", hl = "PatchviewWidgetBtn" },
  next_btn = { text = "▶", hl = "PatchviewWidgetBtn" },

  -- Action buttons
  undo_btn = { text = "Undo", hl = "PatchviewWidgetUndo" },
  keep_btn = { text = "Keep", hl = "PatchviewWidgetKeep" },

  -- Position indicator
  separator = { text = " ", hl = "Normal" },
  pos_indicator = { text = "%d/%d", hl = "PatchviewWidgetPos" },
}

-- Default widget position relative to hunk
local widget_offset = 1 -- Lines below the hunk start

--- Initialize widget module
function M.setup()
  M.namespace = vim.api.nvim_create_namespace("patchview_widget")
  M.augroup = vim.api.nvim_create_augroup("patchview_widget", { clear = true })
end

--- Show the floating action bar for a buffer
---@param bufnr number Buffer number
---@param hunks table[] List of hunks
function M.show(bufnr, hunks)
  if not hunks or #hunks == 0 then
    M.hide(bufnr)
    return
  end

  -- Filter to only pending hunks
  local pending_hunks = vim.tbl_filter(function(h)
    return h.status == "pending"
  end, hunks)

  if #pending_hunks == 0 then
    M.hide(bufnr)
    return
  end

  -- Initialize state for this buffer if needed
  if not M.state[bufnr] then
    M.state[bufnr] = {
      win = nil,
      current_idx = 1,
      pending = pending_hunks,
    }
  else
    M.state[bufnr].pending = pending_hunks
  end

  -- Position the widget near the current hunk
  M._position_widget(bufnr)

  -- Set up autocmds for widget behavior
  M._setup_autocmds(bufnr)
end

--- Hide the floating action bar for a buffer
---@param bufnr number Buffer number
function M.hide(bufnr)
  local state = M.state[bufnr]
  if not state then
    return
  end

  -- Close the floating window if it exists
  if state.win and vim.api.nvim_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end

  -- Clear extmarks
  if M.namespace then
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

--- Hide all widgets
function M.hide_all()
  for bufnr, _ in pairs(M.state) do
    M.hide(bufnr)
  end
end

--- Position the widget near the current hunk
---@param bufnr number Buffer number
function M._position_widget(bufnr)
  local state = M.state[bufnr]
  if not state or #state.pending == 0 then
    return
  end

  local hunks_mod = require("patchview.hunks")

  -- Get current hunk
  local current_hunk = state.pending[state.current_idx]
  if not current_hunk then
    current_hunk = state.pending[1]
    state.current_idx = 1
  end

  -- Calculate position for the widget
  local start_line, _ = hunks_mod.get_line_range(current_hunk)
  local widget_line = math.min(start_line + widget_offset, vim.api.nvim_buf_line_count(bufnr))

  -- Create or update the floating window
  M._create_or_update_widget(bufnr, widget_line, state.current_idx, #state.pending)
end

--- Create or update the floating widget window
---@param bufnr number Source buffer number
---@param line number Line number (1-indexed)
---@param current_idx number Current hunk index
---@param total number Total number of hunks
function M._create_or_update_widget(bufnr, line, current_idx, total)
  local state = M.state[bufnr]
  local config = require("patchview.config")

  -- Build widget content
  local pos_text = string.format(widget_content.pos_indicator.text, current_idx, total)

  -- Widget line content: [◀] Undo 1/3 Keep [▶]
  -- Using bracket-style buttons for clarity
  local widget_lines = {
    string.format(" %s Undo %s Keep %s ",
      widget_content.prev_btn.text,
      pos_text,
      widget_content.next_btn.text
    ),
  }

  -- Create a buffer for the widget if needed
  local widget_buf
  if state.widget_buf and vim.api.nvim_buf_is_valid(state.widget_buf) then
    widget_buf = state.widget_buf
    vim.api.nvim_buf_set_lines(widget_buf, 0, -1, false, widget_lines)
  else
    widget_buf = vim.api.nvim_create_buf(false, true)
    state.widget_buf = widget_buf
    vim.api.nvim_buf_set_lines(widget_buf, 0, -1, false, widget_lines)

    -- Set buffer options
    vim.bo[widget_buf].buftype = "nofile"
    vim.bo[widget_buf].bufhidden = "wipe"
    vim.bo[widget_buf].modifiable = false
  end

  -- Apply highlighting to widget buffer
  M._apply_widget_highlights(widget_buf, pos_text)

  -- Get window dimensions for positioning
  local win = vim.api.nvim_get_current_win()
  local win_info = vim.fn.getwininfo(win)[1]
  local win_width = win_info and win_info.width or 80

  -- Calculate widget width (add padding)
  local widget_width = vim.fn.strdisplaywidth(widget_lines[1]) + 4

  -- Center the widget horizontally in the window
  -- Position it near the hunk line
  local cursor = vim.api.nvim_win_get_cursor(win)
  local screen_row = cursor[1]

  -- Get window position
  local win_row = vim.fn.winline()
  local win_height = vim.api.nvim_win_get_height(win)

  -- Position widget below the hunk, but keep it in view
  local row = win_row + 2
  if row > win_height - 2 then
    row = win_row - 2 -- Move above if not enough space below
  end
  row = math.max(1, math.min(row, win_height))

  -- Anchor: "N" (north) means row is the top row
  -- Position centered horizontally
  local col = math.max(0, (win_width - widget_width) / 2)

  -- Window config options
  local widget_config = config.options.widget or {}
  local win_config = {
    relative = "win",
    win = win,
    row = row,
    col = col,
    width = widget_width,
    height = 1,
    style = "minimal",
    border = widget_config.border_style or "rounded",
    focusable = true,
    zindex = 50,
  }

  -- Create or move the floating window
  if state.win and vim.api.nvim_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, win_config)
  else
    state.win = vim.api.nvim_open_win(widget_buf, false, win_config)

    -- Set window options
    vim.wo[state.win].winblend = widget_config.winblend or 0
    vim.wo[state.win].winhl = "NormalFloat:PatchviewWidgetNormal"

    -- Set up keymaps for the widget
    M._setup_widget_keymaps(state.win, bufnr)
  end
end

--- Apply syntax highlighting to the widget content
---@param widget_buf number Widget buffer number
---@param pos_text string Position text (e.g., "1/3")
function M._apply_widget_highlights(widget_buf, pos_text)
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(widget_buf, M.namespace, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(widget_buf, 0, 1, false)
  local line = lines and lines[1]
  if not line then
    return
  end

  local col = 0

  -- Highlight prev button (◀)
  local prev_text = widget_content.prev_btn.text
  vim.api.nvim_buf_add_highlight(widget_buf, M.namespace, widget_content.prev_btn.hl, 0, col, col + #prev_text)
  col = col + #prev_text + 1

  -- Highlight "Undo"
  local undo_text = "Undo"
  local undo_start = col
  col = col + #undo_text + 1
  vim.api.nvim_buf_add_highlight(widget_buf, M.namespace, widget_content.undo_btn.hl, 0, undo_start, col)

  -- Highlight position indicator
  local pos_start = col
  col = col + #pos_text
  vim.api.nvim_buf_add_highlight(widget_buf, M.namespace, widget_content.pos_indicator.hl, 0, pos_start, col)

  -- Highlight "Keep"
  col = col + 1
  local keep_text = "Keep"
  local keep_start = col
  col = col + #keep_text
  vim.api.nvim_buf_add_highlight(widget_buf, M.namespace, widget_content.keep_btn.hl, 0, keep_start, col)

  -- Highlight next button (▶)
  col = col + 1
  local next_text = widget_content.next_btn.text
  vim.api.nvim_buf_add_highlight(widget_buf, M.namespace, widget_content.next_btn.hl, 0, col, col + #next_text)
end

--- Set up keymaps for the widget window
---@param win number Widget window number
---@param bufnr number Source buffer number
function M._setup_widget_keymaps(win, bufnr)
  -- Left arrow or previous hunk key - navigate to previous hunk
  vim.keymap.set("n", "<Left>", function()
    M._navigate_prev(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })

  vim.keymap.set("n", "h", function()
    M._navigate_prev(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })

  -- Right arrow or next hunk key - navigate to next hunk
  vim.keymap.set("n", "<Right>", function()
    M._navigate_next(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })

  vim.keymap.set("n", "l", function()
    M._navigate_next(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })

  -- u or U - Undo (reject) current hunk
  vim.keymap.set("n", "u", function()
    M._reject_current(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })

  vim.keymap.set("n", "U", function()
    M._reject_current(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })

  -- k or K or Enter - Keep (accept) current hunk
  vim.keymap.set("n", "k", function()
    M._accept_current(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })

  vim.keymap.set("n", "K", function()
    M._accept_current(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })

  vim.keymap.set("n", "<CR>", function()
    M._accept_current(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })

  -- q or Escape - Close widget
  vim.keymap.set("n", "q", function()
    M.hide(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    M.hide(bufnr)
  end, { buffer = vim.api.nvim_win_get_buf(win), nowait = true })
end

--- Set up autocmds for widget behavior
---@param bufnr number Buffer number
function M._setup_autocmds(bufnr)
  if not M.augroup then
    M.augroup = vim.api.nvim_create_augroup("patchview_widget", { clear = true })
  end

  -- Clear existing autocmds for this buffer
  pcall(vim.api.nvim_clear_autocmds, {
    group = M.augroup,
    buffer = bufnr,
  })

  -- Update widget position on cursor move (reposition near current hunk)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = M.augroup,
    buffer = bufnr,
    callback = function()
      if M.state[bufnr] and M.state[bufnr].win and vim.api.nvim_is_valid(M.state[bufnr].win) then
        local actions = require("patchview.actions")
        local patchview = require("patchview")
        local hunks_mod = require("patchview.hunks")

        local buf_state = patchview.state.buffers[bufnr]
        if not buf_state or #buf_state.hunks == 0 then
          M.hide(bufnr)
          return
        end

        -- Update current hunk based on cursor position
        local line = vim.api.nvim_win_get_cursor(0)[1]
        local hunk = hunks_mod.get_at_line(buf_state.hunks, line)

        if hunk then
          -- Find the index of this hunk in pending list
          for i, pending_hunk in ipairs(M.state[bufnr].pending) do
            if pending_hunk.id == hunk.id then
              M.state[bufnr].current_idx = i
              break
            end
          end
          M._position_widget(bufnr)
        end
      end
    end,
    desc = "Patchview: Update widget position on cursor move",
  })

  -- Hide widget on buffer leave
  vim.api.nvim_create_autocmd("BufLeave", {
    group = M.augroup,
    buffer = bufnr,
    callback = function()
      M.hide(bufnr)
    end,
    desc = "Patchview: Hide widget on buffer leave",
  })

  -- Update widget when hunks change
  vim.api.nvim_create_autocmd("User", {
    group = M.augroup,
    pattern = "PatchviewHunksUpdated",
    callback = function(args)
      if args.data and args.data.bufnr == bufnr then
        if M.state[bufnr] then
          M.state[bufnr].pending = vim.tbl_filter(function(h)
            return h.status == "pending"
          end, args.data.hunks or {})

          if #M.state[bufnr].pending == 0 then
            M.hide(bufnr)
          else
            M.state[bufnr].current_idx = math.min(M.state[bufnr].current_idx, #M.state[bufnr].pending)
            M._position_widget(bufnr)
          end
        end
      end
    end,
    desc = "Patchview: Update widget when hunks change",
  })
end

--- Navigate to previous hunk
---@param bufnr number Buffer number
function M._navigate_prev(bufnr)
  local state = M.state[bufnr]
  if not state or #state.pending == 0 then
    return
  end

  state.current_idx = state.current_idx - 1
  if state.current_idx < 1 then
    state.current_idx = #state.pending
  end

  local hunk = state.pending[state.current_idx]
  if hunk then
    local hunks_mod = require("patchview.hunks")
    local start_line, _ = hunks_mod.get_line_range(hunk)
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    M._position_widget(bufnr)
  end
end

--- Navigate to next hunk
---@param bufnr number Buffer number
function M._navigate_next(bufnr)
  local state = M.state[bufnr]
  if not state or #state.pending == 0 then
    return
  end

  state.current_idx = state.current_idx + 1
  if state.current_idx > #state.pending then
    state.current_idx = 1
  end

  local hunk = state.pending[state.current_idx]
  if hunk then
    local hunks_mod = require("patchview.hunks")
    local start_line, _ = hunks_mod.get_line_range(hunk)
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    M._position_widget(bufnr)
  end
end

--- Reject (undo) current hunk
---@param bufnr number Buffer number
function M._reject_current(bufnr)
  local state = M.state[bufnr]
  if not state or #state.pending == 0 then
    return
  end

  local actions = require("patchview.actions")
  actions.reject_hunk()

  -- Widget will be updated via autocmd
end

--- Accept (keep) current hunk
---@param bufnr number Buffer number
function M._accept_current(bufnr)
  local state = M.state[bufnr]
  if not state or #state.pending == 0 then
    return
  end

  local actions = require("patchview.actions")
  actions.accept_hunk()

  -- Widget will be updated via autocmd
end

--- Toggle the widget for the current buffer
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
