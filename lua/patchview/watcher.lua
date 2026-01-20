-- patchview.nvim - File system watcher module
-- Monitors files for external changes using vim.loop (libuv)

local M = {}

-- Active watchers: { [bufnr] = { handle = uv_handle, filename = string, callback = fn } }
M.watchers = {}

-- Debounce timers: { [bufnr] = timer_handle }
M.debounce_timers = {}

--- Start watching a file for changes
---@param bufnr number Buffer number
---@param filename string File path to watch
---@param callback function Callback function(event) called on file change
function M.watch(bufnr, filename, callback)
  -- Stop existing watcher if any
  M.unwatch(bufnr)

  -- Get debounce time from config
  local config = require("patchview.config")
  local debounce_ms = config.options.watch.debounce_ms or 100

  -- Create file system event watcher
  local handle = vim.loop.new_fs_event()
  if not handle then
    vim.notify("Patchview: Failed to create file watcher", vim.log.levels.ERROR)
    return false
  end

  -- Store watcher info
  M.watchers[bufnr] = {
    handle = handle,
    filename = filename,
    callback = callback,
  }

  -- Start watching
  local flags = {
    watch_entry = false,  -- Watch the file itself, not directory
    stat = false,         -- Don't need stat info
    recursive = false,    -- Not recursive
  }

  local ok, err = handle:start(filename, flags, function(err, fname, events)
    if err then
      vim.schedule(function()
        vim.notify("Patchview: Watcher error: " .. err, vim.log.levels.WARN)
      end)
      return
    end

    -- Debounce: cancel existing timer and start new one
    M._debounce(bufnr, debounce_ms, function()
      -- Check if file still exists and is readable
      local stat = vim.loop.fs_stat(filename)
      if not stat then
        -- File was deleted
        vim.schedule(function()
          callback({ type = "delete", filename = fname })
        end)
        return
      end

      -- File was modified
      vim.schedule(function()
        callback({ type = "change", filename = fname, events = events })
      end)
    end)
  end)

  if not ok then
    vim.notify("Patchview: Failed to start watcher: " .. (err or "unknown error"), vim.log.levels.ERROR)
    handle:close()
    M.watchers[bufnr] = nil
    return false
  end

  return true
end

--- Stop watching a buffer's file
---@param bufnr number Buffer number
function M.unwatch(bufnr)
  -- Cancel any pending debounce timer
  if M.debounce_timers[bufnr] then
    M.debounce_timers[bufnr]:stop()
    M.debounce_timers[bufnr]:close()
    M.debounce_timers[bufnr] = nil
  end

  -- Stop and close the watcher
  local watcher = M.watchers[bufnr]
  if watcher then
    if watcher.handle then
      watcher.handle:stop()
      watcher.handle:close()
    end
    M.watchers[bufnr] = nil
  end
end

--- Stop all watchers
function M.unwatch_all()
  for bufnr, _ in pairs(M.watchers) do
    M.unwatch(bufnr)
  end
end

--- Debounce a callback
---@param bufnr number Buffer number (used as key)
---@param ms number Debounce time in milliseconds
---@param callback function Function to call after debounce
function M._debounce(bufnr, ms, callback)
  -- Cancel and close existing timer
  if M.debounce_timers[bufnr] then
    local timer = M.debounce_timers[bufnr]
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
    M.debounce_timers[bufnr] = nil
  end

  -- Create and start new timer
  local timer = vim.loop.new_timer()
  M.debounce_timers[bufnr] = timer
  
  timer:start(ms, 0, function()
    -- Clean up timer after firing
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
    M.debounce_timers[bufnr] = nil
    
    callback()
  end)
end

--- Check if a buffer is being watched
---@param bufnr number Buffer number
---@return boolean
function M.is_watching(bufnr)
  return M.watchers[bufnr] ~= nil
end

--- Get all watched buffers
---@return number[] List of buffer numbers
function M.get_watched_buffers()
  local buffers = {}
  for bufnr, _ in pairs(M.watchers) do
    table.insert(buffers, bufnr)
  end
  return buffers
end

--- Pause watching (temporarily stop without removing)
---@param bufnr number Buffer number
function M.pause(bufnr)
  local watcher = M.watchers[bufnr]
  if watcher and watcher.handle then
    watcher.handle:stop()
  end
end

--- Resume watching
---@param bufnr number Buffer number
function M.resume(bufnr)
  local watcher = M.watchers[bufnr]
  if watcher and watcher.handle and watcher.filename then
    local flags = { watch_entry = false, stat = false, recursive = false }
    watcher.handle:start(watcher.filename, flags, function(err, fname, events)
      if not err then
        local config = require("patchview.config")
        local debounce_ms = config.options.watch.debounce_ms or 100
        M._debounce(bufnr, debounce_ms, function()
          vim.schedule(function()
            watcher.callback({ type = "change", filename = fname, events = events })
          end)
        end)
      end
    end)
  end
end

return M
