-- patchview.nvim - Highlight definitions module
-- Defines highlight groups for diff visualization

local M = {}

--- Setup highlight groups
function M.setup()
  local config = require("patchview.config")

  -- Default diff highlights - inspired by diffview.nvim
  local highlights = {
    -- Basic diff highlights - link to Neovim's built-in diff highlights
    PatchviewAdd = { link = "DiffAdd" },
    PatchviewDelete = { link = "DiffDelete" },
    PatchviewChange = { link = "DiffChange" },
    PatchviewText = { link = "DiffText" },

    -- Deleted lines shown as virtual text (background only, preserve text color)
    PatchviewDeleteVirtual = { bg = "#4a2d2d" },
    PatchviewDeleteLine = { bg = "#4a2d2d" },
    -- Line numbers for deleted virtual lines (dim + red background)
    PatchviewDeleteLineNr = { fg = "#5c6370", bg = "#4a2d2d" },

    -- Sign column - colored vertical bars (foreground only, no bg)
    PatchviewSignAdd = { fg = "#50fa7b", bold = true },
    PatchviewSignDelete = { fg = "#ff5555", bold = true },
    PatchviewSignChange = { fg = "#f1fa8c", bold = true },

    -- Git-aware mode highlights
    PatchviewExternal = { bg = "#3e4451", bold = true },
    PatchviewGitUnstaged = { bg = "#2c323c" },
    PatchviewGitStaged = { bg = "#282c34" },

    -- Line number highlights - colored text with matching background
    PatchviewLineNrAdd = { fg = "#5c6370", bg = "#2d4a2d" },
    PatchviewLineNrDelete = { fg = "#5c6370", bg = "#4a2d2d" },
    PatchviewLineNrChange = { fg = "#5c6370", bg = "#4a4a2d" },

    -- Preview mode highlights
    PatchviewPreviewAdd = { bg = "#2d4a2d" },
    PatchviewPreviewDelete = { bg = "#4a2d2d" },
    PatchviewPreviewChange = { bg = "#4a4a2d" },

    -- Applied changes (fading)
    PatchviewAppliedAdd = { bg = "#1e3a1e" },
    PatchviewAppliedDelete = { bg = "#3a1e1e" },
    PatchviewAppliedChange = { bg = "#3a3a1e" },

    -- Word-level diff
    PatchviewWordAdd = { fg = "#98c379", bold = true },
    PatchviewWordDelete = { fg = "#e06c75", strikethrough = true },

    -- Status highlights
    PatchviewStatusWatching = { fg = "#98c379" },
    PatchviewStatusPaused = { fg = "#e5c07b" },
    PatchviewStatusError = { fg = "#e06c75" },
  }

  -- Apply custom highlights from config if provided
  local render_config = config.options.render or {}
  if render_config.added_hl and render_config.added_hl ~= "DiffAdd" then
    highlights.PatchviewAdd = { link = render_config.added_hl }
  end
  if render_config.removed_hl and render_config.removed_hl ~= "DiffDelete" then
    highlights.PatchviewDelete = { link = render_config.removed_hl }
  end
  if render_config.changed_hl and render_config.changed_hl ~= "DiffChange" then
    highlights.PatchviewChange = { link = render_config.changed_hl }
  end

  -- Git-aware highlights from config
  local git_config = config.options.git or {}
  if git_config.external_hl and git_config.external_hl ~= "PatchviewExternal" then
    highlights.PatchviewExternal = { link = git_config.external_hl }
  end
  if git_config.unstaged_hl and git_config.unstaged_hl ~= "PatchviewGitUnstaged" then
    highlights.PatchviewGitUnstaged = { link = git_config.unstaged_hl }
  end
  if git_config.staged_hl and git_config.staged_hl ~= "PatchviewGitStaged" then
    highlights.PatchviewGitStaged = { link = git_config.staged_hl }
  end

  -- Set all highlight groups
  for name, opts in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

--- Get highlight group name for a change type
---@param change_type string "add"|"delete"|"change"
---@param mode string|nil "preview"|"applied"|nil
---@return string Highlight group name
function M.get_hl_group(change_type, mode)
  local prefix = "Patchview"

  if mode == "preview" then
    prefix = "PatchviewPreview"
  elseif mode == "applied" then
    prefix = "PatchviewApplied"
  end

  if change_type == "add" then
    return prefix .. "Add"
  elseif change_type == "delete" then
    return prefix .. "Delete"
  elseif change_type == "change" then
    return prefix .. "Change"
  end

  return "PatchviewChange"
end

--- Get sign highlight group for a change type
---@param change_type string "add"|"delete"|"change"
---@return string Highlight group name
function M.get_sign_hl(change_type)
  if change_type == "add" then
    return "PatchviewSignAdd"
  elseif change_type == "delete" then
    return "PatchviewSignDelete"
  else
    return "PatchviewSignChange"
  end
end

--- Get line number highlight group for a change type
---@param change_type string "add"|"delete"|"change"
---@return string Highlight group name
function M.get_linenr_hl(change_type)
  if change_type == "add" then
    return "PatchviewLineNrAdd"
  elseif change_type == "delete" then
    return "PatchviewLineNrDelete"
  else
    return "PatchviewLineNrChange"
  end
end

return M
