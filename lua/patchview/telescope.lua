-- patchview.nvim - Telescope integration module
-- Provides telescope pickers for browsing and acting on changes

local M = {}

-- Check if telescope is available
local has_telescope, telescope = pcall(require, "telescope")

--- Open the main patchview telescope picker
function M.open()
  if not has_telescope then
    M._fallback_picker()
    return
  end

  M.changes_picker()
end

--- Telescope picker for all changes
function M.changes_picker()
  if not has_telescope then
    M._fallback_picker()
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")

  -- Collect all hunks from all buffers
  local entries = {}
  for bufnr, buf_state in pairs(patchview.state.buffers) do
    if buf_state.hunks and #buf_state.hunks > 0 then
      local filename = buf_state.filename or vim.api.nvim_buf_get_name(bufnr)
      local short_name = vim.fn.fnamemodify(filename, ":t")

      for _, hunk in ipairs(buf_state.hunks) do
        if hunk.status == "pending" then
          local start_line, _ = hunks_mod.get_line_range(hunk)
          table.insert(entries, {
            bufnr = bufnr,
            hunk = hunk,
            filename = filename,
            short_name = short_name,
            line = start_line,
            type = hunk.type,
            display = string.format("%s:%d [%s] +%d -%d",
              short_name, start_line, hunk.type,
              hunk.new_count, hunk.old_count),
          })
        end
      end
    end
  end

  if #entries == 0 then
    vim.notify("Patchview: No pending changes", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = "Patchview Changes",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.display,
          filename = entry.filename,
          lnum = entry.line,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = "Hunk Preview",
      define_preview = function(self, entry)
        local hunk = entry.value.hunk
        local lines = hunks_mod.to_unified_diff(hunk)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.bo[self.state.bufnr].filetype = "diff"
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      -- Accept hunk on Enter
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          -- Jump to the hunk
          vim.api.nvim_set_current_buf(entry.value.bufnr)
          vim.api.nvim_win_set_cursor(0, { entry.value.line, 0 })
        end
      end)

      -- Accept hunk with <C-a>
      map("i", "<C-a>", function()
        local entry = action_state.get_selected_entry()
        if entry then
          local actions_mod = require("patchview.actions")
          vim.api.nvim_set_current_buf(entry.value.bufnr)
          vim.api.nvim_win_set_cursor(0, { entry.value.line, 0 })
          actions_mod.accept_hunk()
        end
      end)

      -- Reject hunk with <C-r>
      map("i", "<C-r>", function()
        local entry = action_state.get_selected_entry()
        if entry then
          local actions_mod = require("patchview.actions")
          vim.api.nvim_set_current_buf(entry.value.bufnr)
          vim.api.nvim_win_set_cursor(0, { entry.value.line, 0 })
          actions_mod.reject_hunk()
        end
      end)

      return true
    end,
  }):find()
end

--- Telescope picker for files with changes
function M.files_picker()
  if not has_telescope then
    M._fallback_files_picker()
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")

  -- Collect files with changes
  local entries = {}
  for bufnr, buf_state in pairs(patchview.state.buffers) do
    if buf_state.hunks and #buf_state.hunks > 0 then
      local filename = buf_state.filename or vim.api.nvim_buf_get_name(bufnr)
      local stats = hunks_mod.get_stats(buf_state.hunks)

      table.insert(entries, {
        bufnr = bufnr,
        filename = filename,
        short_name = vim.fn.fnamemodify(filename, ":t"),
        hunks = stats.total,
        pending = stats.pending,
        additions = stats.additions,
        deletions = stats.deletions,
        display = string.format("%s [%d hunks, +%d -%d]",
          vim.fn.fnamemodify(filename, ":t"),
          stats.pending, stats.additions, stats.deletions),
      })
    end
  end

  if #entries == 0 then
    vim.notify("Patchview: No files with changes", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = "Patchview Files",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.filename,
          filename = entry.filename,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          vim.api.nvim_set_current_buf(entry.value.bufnr)
        end
      end)
      return true
    end,
  }):find()
end

--- Fallback picker using vim.ui.select when telescope is not available
function M._fallback_picker()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")

  local items = {}
  local item_data = {}

  for bufnr, buf_state in pairs(patchview.state.buffers) do
    if buf_state.hunks and #buf_state.hunks > 0 then
      local filename = buf_state.filename or vim.api.nvim_buf_get_name(bufnr)
      local short_name = vim.fn.fnamemodify(filename, ":t")

      for _, hunk in ipairs(buf_state.hunks) do
        if hunk.status == "pending" then
          local start_line, _ = hunks_mod.get_line_range(hunk)
          local display = string.format("%s:%d [%s] +%d -%d",
            short_name, start_line, hunk.type,
            hunk.new_count, hunk.old_count)
          table.insert(items, display)
          table.insert(item_data, { bufnr = bufnr, line = start_line })
        end
      end
    end
  end

  if #items == 0 then
    vim.notify("Patchview: No pending changes", vim.log.levels.INFO)
    return
  end

  vim.ui.select(items, {
    prompt = "Patchview Changes:",
  }, function(choice, idx)
    if choice and idx then
      local data = item_data[idx]
      vim.api.nvim_set_current_buf(data.bufnr)
      vim.api.nvim_win_set_cursor(0, { data.line, 0 })
    end
  end)
end

--- Fallback files picker
function M._fallback_files_picker()
  local patchview = require("patchview")
  local hunks_mod = require("patchview.hunks")

  local items = {}
  local item_data = {}

  for bufnr, buf_state in pairs(patchview.state.buffers) do
    if buf_state.hunks and #buf_state.hunks > 0 then
      local filename = buf_state.filename or vim.api.nvim_buf_get_name(bufnr)
      local stats = hunks_mod.get_stats(buf_state.hunks)
      local display = string.format("%s [%d hunks, +%d -%d]",
        vim.fn.fnamemodify(filename, ":t"),
        stats.pending, stats.additions, stats.deletions)
      table.insert(items, display)
      table.insert(item_data, { bufnr = bufnr })
    end
  end

  if #items == 0 then
    vim.notify("Patchview: No files with changes", vim.log.levels.INFO)
    return
  end

  vim.ui.select(items, {
    prompt = "Patchview Files:",
  }, function(choice, idx)
    if choice and idx then
      local data = item_data[idx]
      vim.api.nvim_set_current_buf(data.bufnr)
    end
  end)
end

--- Register as telescope extension
function M.register_extension()
  if not has_telescope then
    return
  end

  return telescope.register_extension({
    exports = {
      patchview = M.changes_picker,
      changes = M.changes_picker,
      files = M.files_picker,
    },
  })
end

return M
