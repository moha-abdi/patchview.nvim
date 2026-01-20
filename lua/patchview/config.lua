-- patchview.nvim - Configuration module
-- Manages plugin configuration with sensible defaults

local M = {}

-- Default configuration
M.defaults = {
  -- Watching behavior
  watch = {
    enabled = true,           -- Enable file watching by default
    debounce_ms = 200,        -- Debounce time for rapid changes (fs events can fire multiple times)
    ignore_patterns = {},     -- Patterns to ignore (e.g., "*.tmp")
  },

  -- Follow changes (auto-scroll)
  follow = {
    enabled = true,           -- Auto-scroll to changes when detected off-screen
    center = true,            -- Center the change in viewport
    only_if_off_screen = true, -- Only scroll if change is not visible
  },

  -- Diff visualization
  diff = {
    algorithm = "myers",      -- "myers" or "patience"
    context_lines = 3,        -- Context lines around changes
  },

  -- Visual settings
  render = {
    style = "both",           -- "inline", "signs", or "both"
    added_hl = "DiffAdd",     -- Highlight for added lines
    removed_hl = "DiffDelete",-- Highlight for removed lines
    changed_hl = "DiffChange",-- Highlight for changed lines
    show_removed_virtual = true, -- Show removed as virtual text
    animation = {
      enabled = true,         -- Animate highlight changes
      duration_ms = 300,      -- Animation duration
    },
  },

  -- Git-aware mode
  git = {
    enabled = true,           -- Enable git integration
    show_external = true,     -- Show external tool changes (prominent)
    show_unstaged = true,     -- Show git unstaged changes (dimmer)
    show_staged = false,      -- Show git staged changes
    external_hl = "PatchviewExternal",   -- Highlight for external changes
    unstaged_hl = "PatchviewGitUnstaged", -- Highlight for git unstaged
    staged_hl = "PatchviewGitStaged",     -- Highlight for git staged
    baseline = "working_tree", -- "working_tree", "staged", or "head"
  },

  -- Telescope integration
  telescope = {
    enabled = true,           -- Enable telescope extension
    mappings = {
      accept = "<CR>",        -- Accept hunk from picker
      reject = "<C-r>",       -- Reject hunk from picker
      preview = "<C-p>",      -- Toggle preview
    },
  },

  -- Acceptance mode
  mode = "auto",              -- "auto" or "preview"

  -- Keymaps (set to false to disable)
  keymaps = {
    next_hunk = "]c",
    prev_hunk = "[c",
    accept_hunk = "<leader>pa",
    reject_hunk = "<leader>pr",
    accept_all = "<leader>pA",
    reject_all = "<leader>pR",
    toggle_preview = "<leader>pp",
    telescope_changes = "<leader>pf",  -- Open telescope picker
    split_diff = "<leader>pd",         -- Open split diff view
  },

  -- Notifications
  notify = {
    on_change = true,         -- Notify when changes detected
    on_accept = false,        -- Notify on accept
    on_reject = false,        -- Notify on reject
  },

  -- Floating action bar widget (like Cursor IDE)
  widget = {
    enabled = true,           -- Enable floating action bar
    border_style = "rounded", -- "rounded", "single", "double", "shadow", or "none"
    winblend = 0,             -- Transparency (0-100)
    auto_show = true,         -- Automatically show when changes are detected
    position = "bottom",      -- "top" or "bottom" relative to hunk
  },
}

-- Current configuration (will be populated by setup)
M.options = {}

--- Deep merge two tables
---@param t1 table Base table
---@param t2 table Table to merge into t1
---@return table Merged table
local function deep_merge(t1, t2)
  local result = vim.deepcopy(t1)
  for k, v in pairs(t2) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

--- Setup configuration with user options
---@param opts table|nil User configuration options
function M.setup(opts)
  opts = opts or {}
  M.options = deep_merge(M.defaults, opts)
  return M.options
end

--- Get a configuration value by path
---@param path string Dot-separated path (e.g., "watch.debounce_ms")
---@return any The configuration value
function M.get(path)
  local keys = vim.split(path, ".", { plain = true })
  local value = M.options
  for _, key in ipairs(keys) do
    if type(value) ~= "table" then
      return nil
    end
    value = value[key]
  end
  return value
end

--- Check if a feature is enabled
---@param feature string Feature name (e.g., "git", "telescope")
---@return boolean
function M.is_enabled(feature)
  local config = M.options[feature]
  if type(config) == "table" then
    return config.enabled ~= false
  end
  return config ~= false
end

return M
