-- patchview.nvim - Hunk management module
-- Manages groups of changes (hunks) for navigation and actions

local M = {}

---@class Hunk
---@field id number Unique identifier
---@field type string "add"|"delete"|"change"
---@field old_start number Starting line in old content (1-indexed)
---@field old_count number Number of lines in old content
---@field new_start number Starting line in new content (1-indexed)
---@field new_count number Number of lines in new content
---@field old_lines string[] Lines from old content
---@field new_lines string[] Lines from new content
---@field context_before string[] Context lines before hunk
---@field context_after string[] Context lines after hunk
---@field status string "pending"|"accepted"|"rejected"

-- Hunk ID counter
local hunk_id = 0

--- Generate a new hunk ID
---@return number
local function next_id()
  hunk_id = hunk_id + 1
  return hunk_id
end

--- Create hunks from diff changes
---@param changes table[] Diff changes from diff.compute()
---@param context_lines number Number of context lines to include
---@return Hunk[]
function M.create_from_diff(changes, context_lines)
  context_lines = context_lines or 3
  local hunks = {}

  for _, change in ipairs(changes) do
    local hunk = {
      id = next_id(),
      type = change.type,
      old_start = change.old_start,
      old_count = change.old_count,
      new_start = change.new_start,
      new_count = change.new_count,
      old_lines = change.old_lines or {},
      new_lines = change.new_lines or {},
      context_before = {},
      context_after = {},
      status = "pending",
    }
    table.insert(hunks, hunk)
  end

  return hunks
end

--- Get the hunk at a specific line
---@param hunks Hunk[] List of hunks
---@param line number Line number (1-indexed)
---@return Hunk|nil The hunk at the line, or nil
function M.get_at_line(hunks, line)
  for _, hunk in ipairs(hunks) do
    local start_line, end_line = M.get_line_range(hunk)
    if line >= start_line and line <= end_line then
      return hunk
    end
  end
  return nil
end

--- Get the line range for a hunk (in current buffer)
---@param hunk Hunk
---@return number, number start_line, end_line
function M.get_line_range(hunk)
  local start_line = hunk.new_start
  local end_line = start_line + math.max(hunk.new_count - 1, 0)

  -- For deletions, use old_start as reference
  if hunk.type == "delete" then
    start_line = hunk.old_start
    end_line = start_line
  end

  return start_line, end_line
end

--- Get the next hunk after a line
---@param hunks Hunk[] List of hunks
---@param line number Current line (1-indexed)
---@return Hunk|nil The next hunk, or nil
function M.get_next(hunks, line)
  for _, hunk in ipairs(hunks) do
    local start_line, _ = M.get_line_range(hunk)
    if start_line > line then
      return hunk
    end
  end
  -- Wrap around to first hunk
  return hunks[1]
end

--- Get the previous hunk before a line
---@param hunks Hunk[] List of hunks
---@param line number Current line (1-indexed)
---@return Hunk|nil The previous hunk, or nil
function M.get_prev(hunks, line)
  local prev = nil
  for _, hunk in ipairs(hunks) do
    local start_line, _ = M.get_line_range(hunk)
    if start_line >= line then
      break
    end
    prev = hunk
  end
  -- Wrap around to last hunk
  return prev or hunks[#hunks]
end

--- Get all pending hunks
---@param hunks Hunk[]
---@return Hunk[]
function M.get_pending(hunks)
  local pending = {}
  for _, hunk in ipairs(hunks) do
    if hunk.status == "pending" then
      table.insert(pending, hunk)
    end
  end
  return pending
end

--- Mark a hunk as accepted
---@param hunk Hunk
function M.accept(hunk)
  hunk.status = "accepted"
end

--- Mark a hunk as rejected
---@param hunk Hunk
function M.reject(hunk)
  hunk.status = "rejected"
end

--- Sort hunks by line number
---@param hunks Hunk[]
---@return Hunk[] Sorted hunks
function M.sort_by_line(hunks)
  local sorted = vim.deepcopy(hunks)
  table.sort(sorted, function(a, b)
    local a_start, _ = M.get_line_range(a)
    local b_start, _ = M.get_line_range(b)
    return a_start < b_start
  end)
  return sorted
end

--- Get unified diff representation of a hunk
---@param hunk Hunk
---@return string[] Diff lines
function M.to_unified_diff(hunk)
  local lines = {}

  -- Header
  local header = string.format("@@ -%d,%d +%d,%d @@",
    hunk.old_start, hunk.old_count,
    hunk.new_start, hunk.new_count)
  table.insert(lines, header)

  -- Deleted lines
  for _, line in ipairs(hunk.old_lines) do
    table.insert(lines, "-" .. line)
  end

  -- Added lines
  for _, line in ipairs(hunk.new_lines) do
    table.insert(lines, "+" .. line)
  end

  return lines
end

--- Get statistics for hunks
---@param hunks Hunk[]
---@return table Stats { total, pending, accepted, rejected, additions, deletions }
function M.get_stats(hunks)
  local stats = {
    total = #hunks,
    pending = 0,
    accepted = 0,
    rejected = 0,
    additions = 0,
    deletions = 0,
  }

  for _, hunk in ipairs(hunks) do
    if hunk.status == "pending" then
      stats.pending = stats.pending + 1
    elseif hunk.status == "accepted" then
      stats.accepted = stats.accepted + 1
    elseif hunk.status == "rejected" then
      stats.rejected = stats.rejected + 1
    end

    stats.additions = stats.additions + hunk.new_count
    stats.deletions = stats.deletions + hunk.old_count
  end

  return stats
end

--- Find hunk by ID
---@param hunks Hunk[]
---@param id number Hunk ID
---@return Hunk|nil
function M.find_by_id(hunks, id)
  for _, hunk in ipairs(hunks) do
    if hunk.id == id then
      return hunk
    end
  end
  return nil
end

--- Remove a hunk from the list
---@param hunks Hunk[]
---@param id number Hunk ID to remove
---@return Hunk[] Updated hunks list
function M.remove(hunks, id)
  local result = {}
  for _, hunk in ipairs(hunks) do
    if hunk.id ~= id then
      table.insert(result, hunk)
    end
  end
  return result
end

return M
