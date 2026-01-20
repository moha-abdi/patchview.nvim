-- patchview.nvim - Diff computation module
-- Implements line-based diff algorithm (Myers diff)

local M = {}

--- Compute the diff between two arrays of lines
--- Uses Myers diff algorithm for optimal results
---@param old_lines string[] Original lines
---@param new_lines string[] New lines
---@return table[] Array of change objects { type = "add"|"delete"|"change", old_start, old_count, new_start, new_count, old_lines, new_lines }
function M.compute(old_lines, new_lines)
  -- Handle edge cases
  if #old_lines == 0 and #new_lines == 0 then
    return {}
  end

  if #old_lines == 0 then
    return {{
      type = "add",
      old_start = 0,
      old_count = 0,
      new_start = 1,
      new_count = #new_lines,
      old_lines = {},
      new_lines = new_lines,
    }}
  end

  if #new_lines == 0 then
    return {{
      type = "delete",
      old_start = 1,
      old_count = #old_lines,
      new_start = 0,
      new_count = 0,
      old_lines = old_lines,
      new_lines = {},
    }}
  end

  -- Compute LCS-based diff
  local changes = M._myers_diff(old_lines, new_lines)
  return M._group_changes(changes, old_lines, new_lines)
end

--- Myers diff algorithm implementation
--- Returns a sequence of edit operations
---@param old_lines string[]
---@param new_lines string[]
---@return table[] Edit script
function M._myers_diff(old_lines, new_lines)
  local n = #old_lines
  local m = #new_lines
  local max = n + m

  -- V array to store endpoints of furthest reaching D-paths
  local v = { [1] = 0 }
  local trace = {}

  -- Find shortest edit script
  for d = 0, max do
    trace[d] = vim.deepcopy(v)

    for k = -d, d, 2 do
      local x
      if k == -d or (k ~= d and v[k - 1] < v[k + 1]) then
        x = v[k + 1]
      else
        x = v[k - 1] + 1
      end

      local y = x - k

      -- Follow diagonal (matching lines)
      while x < n and y < m and old_lines[x + 1] == new_lines[y + 1] do
        x = x + 1
        y = y + 1
      end

      v[k] = x

      -- Check if we've reached the end
      if x >= n and y >= m then
        return M._backtrack(trace, old_lines, new_lines, d)
      end
    end
  end

  return {}
end

--- Backtrack through the trace to reconstruct the edit script
---@param trace table[] Trace of V arrays
---@param old_lines string[]
---@param new_lines string[]
---@param d number Final d value
---@return table[] Edit operations
function M._backtrack(trace, old_lines, new_lines, d)
  local edits = {}
  local x = #old_lines
  local y = #new_lines

  for i = d, 0, -1 do
    local v = trace[i]
    local k = x - y

    local prev_k
    if k == -i or (k ~= i and v[k - 1] < v[k + 1]) then
      prev_k = k + 1
    else
      prev_k = k - 1
    end

    local prev_x = v[prev_k]
    local prev_y = prev_x - prev_k

    -- Add diagonal moves (equal lines)
    while x > prev_x and y > prev_y do
      x = x - 1
      y = y - 1
      table.insert(edits, 1, { type = "equal", old_line = x + 1, new_line = y + 1 })
    end

    if i > 0 then
      if x == prev_x then
        -- Insertion
        y = y - 1
        table.insert(edits, 1, { type = "insert", new_line = y + 1 })
      else
        -- Deletion
        x = x - 1
        table.insert(edits, 1, { type = "delete", old_line = x + 1 })
      end
    end
  end

  return edits
end

--- Group individual edits into change hunks
---@param edits table[] Individual edit operations
---@param old_lines string[]
---@param new_lines string[]
---@return table[] Grouped changes
function M._group_changes(edits, old_lines, new_lines)
  local changes = {}
  local current = nil

  for _, edit in ipairs(edits) do
    if edit.type == "equal" then
      -- Finalize current change if any
      if current then
        -- Determine final type based on what we collected
        if current.old_count > 0 and current.new_count > 0 then
          current.type = "change"
        elseif current.old_count > 0 then
          current.type = "delete"
        else
          current.type = "add"
        end
        table.insert(changes, current)
        current = nil
      end
    elseif edit.type == "delete" then
      if not current then
        current = {
          type = "delete",
          old_start = edit.old_line,
          old_count = 0,
          new_start = 0,
          new_count = 0,
          old_lines = {},
          new_lines = {},
        }
      end
      if current.old_start == 0 then
        current.old_start = edit.old_line
      end
      current.old_count = current.old_count + 1
      table.insert(current.old_lines, old_lines[edit.old_line])
    elseif edit.type == "insert" then
      if not current then
        current = {
          type = "add",
          old_start = 0,
          old_count = 0,
          new_start = edit.new_line,
          new_count = 0,
          old_lines = {},
          new_lines = {},
        }
      end
      if current.new_start == 0 then
        current.new_start = edit.new_line
      end
      current.new_count = current.new_count + 1
      table.insert(current.new_lines, new_lines[edit.new_line])
    end
  end

  -- Finalize last change
  if current then
    -- Determine final type based on what we collected
    if current.old_count > 0 and current.new_count > 0 then
      current.type = "change"
    elseif current.old_count > 0 then
      current.type = "delete"
    else
      current.type = "add"
    end
    table.insert(changes, current)
  end

  return changes
end

--- Detect changes (combined delete + add) and merge them
---@param changes table[] Raw changes
---@return table[] Processed changes
function M._detect_changes(changes)
  local result = {}
  local i = 1

  while i <= #changes do
    local change = changes[i]
    local next_change = changes[i + 1]

    -- Check if this delete is followed by an add at the same location
    if change.type == "delete" and next_change and next_change.type == "add" then
      -- Merge into a "change"
      table.insert(result, {
        type = "change",
        old_start = change.old_start,
        old_count = change.old_count,
        new_start = next_change.new_start,
        new_count = next_change.new_count,
        old_lines = change.old_lines,
        new_lines = next_change.new_lines,
      })
      i = i + 2
    else
      table.insert(result, change)
      i = i + 1
    end
  end

  return result
end

--- Compute word-level diff within a line (for inline highlighting)
---@param old_line string Original line
---@param new_line string New line
---@return table[] Word-level changes
function M.compute_inline(old_line, new_line)
  -- Simple word-based diff
  local old_words = vim.split(old_line, "%s+")
  local new_words = vim.split(new_line, "%s+")

  -- Use same algorithm on words
  local changes = M._myers_diff(old_words, new_words)
  return changes
end

--- Check if two sets of lines are equal
---@param lines1 string[]
---@param lines2 string[]
---@return boolean
function M.lines_equal(lines1, lines2)
  if #lines1 ~= #lines2 then
    return false
  end
  for i, line in ipairs(lines1) do
    if line ~= lines2[i] then
      return false
    end
  end
  return true
end

return M
