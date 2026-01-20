-- patchview.nvim - Density indicator module
-- Shows a mini-map/ruler of change locations in the sign column

local M = {}

-- Namespace for density marks
M.namespace = nil

-- Track density state per buffer: { [bufnr] = { extmarks = {} } }
M.state = {}

-- Number of density marks to show (mini-map resolution)
local DENSITY_MARKS_COUNT = 20

--- Setup density indicator module
function M.setup()
  M.namespace = vim.api.nvim_create_namespace("patchview_density")
end

--- Get or create namespace
---@return number Namespace ID
local function get_namespace()
  if not M.namespace then
    M.namespace = vim.api.nvim_create_namespace("patchview_density")
  end
  return M.namespace
end

--- Calculate density marks from hunks
--- Returns a table where index is position (1 to DENSITY_MARKS_COUNT)
--- and value is the intensity (number of changes at that position)
---@param hunks table[] Hunk objects
---@param total_lines number Total lines in the file
---@return table Density marks { [position] = intensity }
local function calculate_density(hunks, total_lines)
  if total_lines == 0 or #hunks == 0 then
    return {}
  end

  -- Initialize density map
  local density = {}
  for i = 1, DENSITY_MARKS_COUNT do
    density[i] = 0
  end

  -- Calculate density for each hunk
  for _, hunk in ipairs(hunks) do
    local hunks_mod = require("patchview.hunks")
    local start_line, end_line = hunks_mod.get_line_range(hunk)

    -- Map line range to density mark positions
    local start_pos = math.floor((start_line - 1) / total_lines * DENSITY_MARKS_COUNT) + 1
    local end_pos = math.floor((end_line - 1) / total_lines * DENSITY_MARKS_COUNT) + 1

    -- Clamp to valid range
    start_pos = math.max(1, math.min(start_pos, DENSITY_MARKS_COUNT))
    end_pos = math.max(1, math.min(end_pos, DENSITY_MARKS_COUNT))

    -- Increment density for affected positions
    for pos = start_pos, end_pos do
      density[pos] = density[pos] + 1
    end
  end

  return density
end

--- Get the appropriate symbol for a density level
---@param intensity number Number of changes at this position
---@return string Symbol to display
local function get_density_symbol(intensity)
  if intensity == 1 then
    return "╸"
  elseif intensity == 2 then
    return "┃"
  elseif intensity == 3 then
    return "█"
  else
    return "█"  -- Highest density
  end
end

--- Get the appropriate highlight for a density level
---@param intensity number Number of changes at this position
---@return string Highlight group
local function get_density_highlight(intensity)
  if intensity == 1 then
    return "PatchviewDensityLow"
  elseif intensity == 2 then
    return "PatchviewDensityMedium"
  elseif intensity == 3 then
    return "PatchviewDensityHigh"
  else
    return "PatchviewDensityExtreme"
  end
end

--- Update density indicators for a buffer
---@param bufnr number Buffer number
---@param hunks table[] Hunk objects
function M.update(bufnr, hunks)
  local config = require("patchview.config")

  -- Skip if disabled or no hunks
  if not config.options.density.enabled then
    return
  end

  if not vim.api.nvim_buf_is_valid(bufnr) or #hunks == 0 then
    return
  end

  local ns = get_namespace()

  -- Clear existing density marks for this buffer
  M.clear(bufnr)

  -- Get total lines in buffer
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  if total_lines == 0 then
    return
  end

  -- Calculate density
  local density = calculate_density(hunks, total_lines)

  -- Find window displaying this buffer
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins == 0 then
    return
  end
  local winnr = wins[1]

  -- Store state
  M.state[bufnr] = {
    winnr = winnr,
    extmarks = {},
  }

  -- Get window height for positioning
  local win_height = vim.api.nvim_win_get_height(winnr)
  local win_info = vim.fn.getwininfo(winnr)[1]
  local topline = win_info.topline or 1
  local botline = win_info.botline or topline + win_height

  -- Calculate visible range in file (0-1)
  local visible_start = (topline - 1) / total_lines
  local visible_end = math.min(botline / total_lines, 1.0)

  -- Place density marks at regular intervals across the visible viewport
  local mark_count = math.min(DENSITY_MARKS_COUNT, math.ceil(win_height / 2))

  for i = 1, mark_count do
    -- Calculate relative position in visible viewport
    local relative_pos = (i - 1) / (mark_count - 1 + 1e-9)

    -- Map to file position
    local file_pos = visible_start + relative_pos * (visible_end - visible_start)
    local density_idx = math.floor(file_pos * DENSITY_MARKS_COUNT) + 1
    density_idx = math.max(1, math.min(density_idx, DENSITY_MARKS_COUNT))

    local intensity = density[density_idx] or 0

    if intensity > 0 then
      -- Calculate screen line for this mark
      local screen_line = math.floor(relative_pos * win_height)
      screen_line = math.max(0, screen_line)

      -- Get actual buffer line at this screen position
      local buffer_line = topline + screen_line - 1
      buffer_line = math.max(1, math.min(buffer_line, total_lines))

      local symbol = get_density_symbol(intensity)
      local hl_group = get_density_highlight(intensity)

      -- Place mark with sign_text to show in sign column
      local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, buffer_line - 1, 0, {
        sign_text = symbol,
        sign_hl_group = hl_group,
        priority = 80,  -- Lower than hunk signs (100) so hunks are primary
      })

      table.insert(M.state[bufnr].extmarks, extmark_id)
    end
  end
end

--- Clear density indicators for a buffer
---@param bufnr number Buffer number
function M.clear(bufnr)
  local ns = get_namespace()

  -- Clear extmarks
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end

  -- Clear state
  M.state[bufnr] = nil
end

--- Clear all density indicators
function M.clear_all()
  local ns = get_namespace()
  for bufnr, _ in pairs(M.state) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end
  M.state = {}
end

return M
