-- patchview.nvim - Real-time diff visualization for external edits
-- Main entry point and setup

local M = {}

-- Lazy-loaded modules
local modules = {
  config = nil,
  watcher = nil,
  diff = nil,
  hunks = nil,
  render = nil,
  highlights = nil,
  signs = nil,
  actions = nil,
  preview = nil,
  status = nil,
  notify = nil,
  git = nil,
  telescope = nil,
  widget = nil,
}

--- Lazy load a module
---@param name string Module name
---@return table The loaded module
local function require_module(name)
  if not modules[name] then
    modules[name] = require("patchview." .. name)
  end
  return modules[name]
end

-- Public API to access modules
M.config = setmetatable({}, {
  __index = function(_, key)
    return require_module("config")[key]
  end,
})

M.watcher = setmetatable({}, {
  __index = function(_, key)
    return require_module("watcher")[key]
  end,
})

M.diff = setmetatable({}, {
  __index = function(_, key)
    return require_module("diff")[key]
  end,
})

M.hunks = setmetatable({}, {
  __index = function(_, key)
    return require_module("hunks")[key]
  end,
})

M.render = setmetatable({}, {
  __index = function(_, key)
    return require_module("render")[key]
  end,
})

M.actions = setmetatable({}, {
  __index = function(_, key)
    return require_module("actions")[key]
  end,
})

M.status = setmetatable({}, {
  __index = function(_, key)
    return require_module("status")[key]
  end,
})

M.git = setmetatable({}, {
  __index = function(_, key)
    return require_module("git")[key]
  end,
})

M.widget = setmetatable({}, {
  __index = function(_, key)
    return require_module("widget")[key]
  end,
})

-- State management
M.state = {
  enabled = false,
  buffers = {},  -- Tracked buffers: { [bufnr] = { watching = bool, hunks = {}, ... } }
  snapshots = {}, -- Baseline snapshots for each buffer
  last_processed_hash = {}, -- Hash of last processed file content (for deduplication)
}

--- Setup patchview with user configuration
---@param opts table|nil User configuration options
function M.setup(opts)
  -- Load and setup configuration
  local config = require_module("config")
  config.setup(opts)

  -- Setup highlights
  local highlights = require_module("highlights")
  highlights.setup()

  -- Setup signs
  local signs = require_module("signs")
  signs.setup()

  -- Setup widget
  local widget = require_module("widget")
  widget.setup()

  -- Create user commands
  M._create_commands()

  -- Setup keymaps if enabled
  M._setup_keymaps()

  -- Setup autocommands
  M._setup_autocmds()

  -- Mark as enabled
  M.state.enabled = true

  -- Auto-enable watching if configured
  if config.options.watch.enabled then
    -- Will start watching when buffers are opened
  end
end

--- Create user commands
function M._create_commands()
  local cmd = vim.api.nvim_create_user_command

  cmd("PatchviewEnable", function()
    M.enable()
  end, { desc = "Enable patchview for current buffer" })

  cmd("PatchviewDisable", function()
    M.disable()
  end, { desc = "Disable patchview for current buffer" })

  cmd("PatchviewToggle", function()
    M.toggle()
  end, { desc = "Toggle patchview for current buffer" })

  cmd("PatchviewStatus", function()
    M.show_status()
  end, { desc = "Show patchview status" })

  cmd("PatchviewAcceptAll", function()
    M.accept_all()
  end, { desc = "Accept all pending changes" })

  cmd("PatchviewRejectAll", function()
    M.reject_all()
  end, { desc = "Reject all pending changes" })

  cmd("PatchviewMode", function(args)
    M.set_mode(args.args)
  end, {
    desc = "Set patchview mode (auto|preview)",
    nargs = "?",
    complete = function()
      return { "auto", "preview" }
    end,
  })

  cmd("PatchviewGit", function(args)
    M.toggle_git(args.args)
  end, {
    desc = "Toggle git-aware mode",
    nargs = "?",
    complete = function()
      return { "on", "off" }
    end,
  })

  cmd("PatchviewTelescope", function()
    M.open_telescope()
  end, { desc = "Open Telescope picker for changes" })

  cmd("PatchviewSnapshot", function()
    M.take_snapshot()
  end, { desc = "Take baseline snapshot" })

  cmd("PatchviewDiff", function()
    M.split_diff()
  end, { desc = "Open split diff view" })

  cmd("PatchviewDiffClose", function()
    M.close_split_diff()
  end, { desc = "Close split diff view" })

  cmd("PatchviewWidget", function()
    M.toggle_widget()
  end, { desc = "Toggle floating action bar widget" })
end

--- Setup keymaps
function M._setup_keymaps()
  local config = require_module("config")
  local keymaps = config.options.keymaps

  if not keymaps then return end

  local function map(key, fn, desc)
    if key and key ~= false then
      vim.keymap.set("n", key, fn, { desc = desc, silent = true })
    end
  end

  map(keymaps.next_hunk, function() M.next_hunk() end, "Next patchview hunk")
  map(keymaps.prev_hunk, function() M.prev_hunk() end, "Previous patchview hunk")
  map(keymaps.accept_hunk, function() M.accept_hunk() end, "Accept current hunk")
  map(keymaps.reject_hunk, function() M.reject_hunk() end, "Reject current hunk")
  map(keymaps.accept_all, function() M.accept_all() end, "Accept all hunks")
  map(keymaps.reject_all, function() M.reject_all() end, "Reject all hunks")
  map(keymaps.toggle_preview, function() M.toggle_preview() end, "Toggle preview mode")
  map(keymaps.telescope_changes, function() M.open_telescope() end, "Open patchview telescope")
  map(keymaps.split_diff, function() M.split_diff() end, "Toggle split diff view")
end

--- Setup autocommands
function M._setup_autocmds()
  local group = vim.api.nvim_create_augroup("Patchview", { clear = true })

  -- Auto-enable for new buffers if watching is enabled
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      local config = require_module("config")
      if config.options.watch.enabled and M.state.enabled then
        M._maybe_watch_buffer(args.buf)
      end
    end,
  })

  -- Cleanup on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(args)
      M._cleanup_buffer(args.buf)
    end,
  })

  -- Handle buffer write (update snapshot)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      M._on_buffer_write(args.buf)
    end,
  })

  -- Handle focus gained - check for file changes that happened while unfocused
  -- This is a backup in case the file watcher missed changes while nvim was in background
  -- Content-based deduplication in _on_file_change prevents duplicate processing
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      -- Check all watched buffers for changes
      for bufnr, buf_state in pairs(M.state.buffers) do
        if buf_state.watching and vim.api.nvim_buf_is_valid(bufnr) then
          local filename = vim.api.nvim_buf_get_name(bufnr)
          if filename ~= "" then
            M._on_file_change(bufnr, { type = "change", filename = filename })
          end
        end
      end
    end,
  })
end

--- Check if a buffer should be watched and start watching if needed
---@param bufnr number Buffer number
function M._maybe_watch_buffer(bufnr)
  -- Skip if already watching
  if M.state.buffers[bufnr] and M.state.buffers[bufnr].watching then
    return
  end

  -- Skip non-file buffers
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return
  end

  -- Skip unnamed buffers
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename == "" then
    return
  end

  -- Check ignore patterns
  local config = require_module("config")
  for _, pattern in ipairs(config.options.watch.ignore_patterns) do
    if filename:match(pattern) then
      return
    end
  end

  -- Start watching
  M._start_watching(bufnr)
end

--- Start watching a buffer for external changes
---@param bufnr number Buffer number
function M._start_watching(bufnr)
  local watcher = require_module("watcher")
  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- Initialize buffer state
  M.state.buffers[bufnr] = {
    watching = true,
    filename = filename,
    hunks = {},
    baseline = nil,
  }

  -- Take initial snapshot
  M._take_buffer_snapshot(bufnr)

  -- Start file watcher
  watcher.watch(bufnr, filename, function(event)
    M._on_file_change(bufnr, event)
  end)
end

--- Stop watching a buffer
---@param bufnr number Buffer number
function M._stop_watching(bufnr)
  local watcher = require_module("watcher")
  local render = require_module("render")

  if M.state.buffers[bufnr] then
    watcher.unwatch(bufnr)
    render.clear(bufnr)
    M.state.buffers[bufnr].watching = false
  end
end

--- Cleanup buffer state
---@param bufnr number Buffer number
function M._cleanup_buffer(bufnr)
  M._stop_watching(bufnr)
  M.state.buffers[bufnr] = nil
  M.state.snapshots[bufnr] = nil
  M.state.last_processed_hash[bufnr] = nil
end

--- Take a snapshot of buffer content
---@param bufnr number Buffer number
function M._take_buffer_snapshot(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  M.state.snapshots[bufnr] = {
    lines = lines,
    timestamp = vim.loop.now(),
  }
  if M.state.buffers[bufnr] then
    M.state.buffers[bufnr].baseline = lines
  end
end

--- Simple hash function for content deduplication
---@param lines string[] Lines to hash
---@return string Hash string
local function hash_content(lines)
  -- Simple hash: concatenate first line, last line, line count, and total length
  -- This is fast and sufficient for deduplication
  local first = lines[1] or ""
  local last = lines[#lines] or ""
  local count = #lines
  local total_len = 0
  for _, line in ipairs(lines) do
    total_len = total_len + #line
  end
  return string.format("%s|%s|%d|%d", first, last, count, total_len)
end

--- Handle file change event
---@param bufnr number Buffer number
---@param event table Event data
function M._on_file_change(bufnr, event)
  -- Schedule to run in main loop
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local config = require_module("config")
    local diff_mod = require_module("diff")
    local hunks_mod = require_module("hunks")
    local render = require_module("render")
    local notify_mod = require_module("notify")

    -- Read new content from file
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local new_lines = M._read_file_lines(filename)
    if not new_lines then
      return
    end

    -- Content-based deduplication: skip if we already processed this exact content
    local content_hash = hash_content(new_lines)
    if M.state.last_processed_hash[bufnr] == content_hash then
      return -- Already processed this content, skip duplicate
    end
    M.state.last_processed_hash[bufnr] = content_hash

    -- Get old content (baseline)
    local old_lines = M.state.buffers[bufnr] and M.state.buffers[bufnr].baseline or {}

    -- Compute diff
    local changes = diff_mod.compute(old_lines, new_lines)
    
    if #changes == 0 then
      -- No changes - clear any existing visualization and reload buffer
      render.clear(bufnr)
      M.state.buffers[bufnr].hunks = {}
      vim.api.nvim_buf_call(bufnr, function()
        local cursor = vim.api.nvim_win_get_cursor(0)
        vim.cmd("silent! edit")
        pcall(vim.api.nvim_win_set_cursor, 0, cursor)
      end)
      return
    end

    -- Create hunks
    local hunks = hunks_mod.create_from_diff(changes, config.options.diff.context_lines)
    M.state.buffers[bufnr].hunks = hunks

    -- Notify about changes
    if config.options.notify.on_change then
      notify_mod.change_detected(bufnr, #hunks)
    end

    -- Reload buffer to get new content
    -- Use :edit to force reload (more reliable than checktime for external changes)
    vim.api.nvim_buf_call(bufnr, function()
      -- Save cursor position
      local cursor = vim.api.nvim_win_get_cursor(0)
      -- Force reload without prompting
      vim.cmd("silent! edit")
      -- Restore cursor position
      pcall(vim.api.nvim_win_set_cursor, 0, cursor)
    end)
    
    -- Handle based on mode after buffer reload
    -- Use slightly longer delay to ensure buffer is fully loaded
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      if config.options.mode == "auto" then
        -- Auto mode: update baseline and show applied highlights temporarily
        M._take_buffer_snapshot(bufnr)
        render.show_hunks(bufnr, hunks, "applied")
        -- Fade out after animation
        if config.options.render.animation.enabled then
          vim.defer_fn(function()
            render.fade_out(bufnr)
          end, config.options.render.animation.duration_ms)
        end
      else
        -- Preview mode: show diff visualization (buffer reloaded but baseline not updated)
        render.show_hunks(bufnr, hunks, "pending")

        -- Show floating widget if enabled
        if config.options.widget.enabled and config.options.widget.auto_show then
          local widget_mod = require_module("widget")
          widget_mod.show(bufnr, hunks)
        end
      end

      -- Force redraw to ensure off-screen extmarks are registered
      vim.cmd("redraw")
    end, 100)
  end)
end

--- Read file lines
---@param filename string File path
---@return string[]|nil Lines or nil on error
function M._read_file_lines(filename)
  local file = io.open(filename, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  
  -- Split by newline
  local lines = vim.split(content, "\n", { plain = true })
  
  -- Remove trailing empty line if file ends with newline
  -- This matches how nvim_buf_get_lines works
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end
  
  return lines
end

--- Handle buffer write
---@param bufnr number Buffer number
function M._on_buffer_write(bufnr)
  if M.state.buffers[bufnr] then
    M._take_buffer_snapshot(bufnr)
    -- Clear any pending hunks on write
    local render = require_module("render")
    render.clear(bufnr)
    M.state.buffers[bufnr].hunks = {}
  end
end

-- Public API functions

--- Enable patchview for current buffer
function M.enable()
  local bufnr = vim.api.nvim_get_current_buf()
  M._start_watching(bufnr)
end

--- Disable patchview for current buffer
function M.disable()
  local bufnr = vim.api.nvim_get_current_buf()
  M._stop_watching(bufnr)
end

--- Toggle patchview for current buffer
function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  if M.state.buffers[bufnr] and M.state.buffers[bufnr].watching then
    M.disable()
  else
    M.enable()
  end
end

--- Show status
function M.show_status()
  local status_mod = require_module("status")
  status_mod.show()
end

--- Navigate to next hunk
function M.next_hunk()
  local actions = require_module("actions")
  actions.next_hunk()
end

--- Navigate to previous hunk
function M.prev_hunk()
  local actions = require_module("actions")
  actions.prev_hunk()
end

--- Accept current hunk
function M.accept_hunk()
  local actions = require_module("actions")
  actions.accept_hunk()
end

--- Reject current hunk
function M.reject_hunk()
  local actions = require_module("actions")
  actions.reject_hunk()
end

--- Accept all hunks
function M.accept_all()
  local actions = require_module("actions")
  actions.accept_all()
end

--- Reject all hunks
function M.reject_all()
  local actions = require_module("actions")
  actions.reject_all()
end

--- Toggle preview mode
function M.toggle_preview()
  local config = require_module("config")
  if config.options.mode == "auto" then
    config.options.mode = "preview"
  else
    config.options.mode = "auto"
  end
end

--- Set mode
---@param mode string|nil Mode name ("auto" or "preview")
function M.set_mode(mode)
  local config = require_module("config")
  if mode == "auto" or mode == "preview" then
    config.options.mode = mode
  else
    -- Toggle if no argument
    M.toggle_preview()
  end
end

--- Toggle git-aware mode
---@param state string|nil "on", "off", or nil to toggle
function M.toggle_git(state)
  local config = require_module("config")
  if state == "on" then
    config.options.git.enabled = true
  elseif state == "off" then
    config.options.git.enabled = false
  else
    config.options.git.enabled = not config.options.git.enabled
  end
end

--- Open telescope picker
function M.open_telescope()
  local config = require_module("config")
  if config.options.telescope.enabled then
    local ok, telescope = pcall(require_module, "telescope")
    if ok then
      telescope.open()
    else
      vim.notify("Telescope integration not available", vim.log.levels.WARN)
    end
  end
end

--- Take baseline snapshot
function M.take_snapshot()
  local bufnr = vim.api.nvim_get_current_buf()
  M._take_buffer_snapshot(bufnr)
  vim.notify("Patchview: Snapshot taken", vim.log.levels.INFO)
end

--- Get statusline component
---@return string Statusline string
function M.statusline()
  local status_mod = require_module("status")
  return status_mod.statusline()
end

--- Open split diff view showing baseline vs current content
function M.split_diff()
  local preview = require_module("preview")
  local bufnr = vim.api.nvim_get_current_buf()
  preview.toggle_split_diff(bufnr)
end

--- Close split diff view
function M.close_split_diff()
  local preview = require_module("preview")
  preview.close_split_diff()
end

--- Toggle floating action bar widget
function M.toggle_widget()
  local widget_mod = require_module("widget")
  widget_mod.toggle()
end

return M
