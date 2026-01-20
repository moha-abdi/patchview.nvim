-- patchview.nvim - Sign column management module
-- Handles sign column indicators for changes

local M = {}

-- Sign names
M.SIGN_ADD = "PatchviewSignAdd"
M.SIGN_DELETE = "PatchviewSignDelete"
M.SIGN_CHANGE = "PatchviewSignChange"

-- Namespace for signs
M.namespace = nil

--- Setup signs
function M.setup()
  -- Create namespace
  M.namespace = vim.api.nvim_create_namespace("patchview_signs")

  -- Define signs - colored vertical bar in sign column (before line numbers)
  vim.fn.sign_define(M.SIGN_ADD, {
    text = "┃",
    texthl = "PatchviewSignAdd",
  })

  vim.fn.sign_define(M.SIGN_DELETE, {
    text = "┃",
    texthl = "PatchviewSignDelete",
  })

  vim.fn.sign_define(M.SIGN_CHANGE, {
    text = "┃",
    texthl = "PatchviewSignChange",
  })
end

--- Place a sign at a line
---@param bufnr number Buffer number
---@param line number Line number (1-indexed)
---@param change_type string "add"|"delete"|"change"
---@return number Sign ID
function M.place(bufnr, line, change_type)
  local sign_name
  if change_type == "add" then
    sign_name = M.SIGN_ADD
  elseif change_type == "delete" then
    sign_name = M.SIGN_DELETE
  else
    sign_name = M.SIGN_CHANGE
  end

  local sign_id = vim.fn.sign_place(0, "patchview", sign_name, bufnr, {
    lnum = line,
    priority = 100,  -- High priority to show above other signs
  })

  return sign_id
end

--- Place signs for a hunk
---@param bufnr number Buffer number
---@param hunk table Hunk object
---@return number[] Sign IDs
function M.place_for_hunk(bufnr, hunk)
  local sign_ids = {}
  local hunks_mod = require("patchview.hunks")
  local start_line, end_line = hunks_mod.get_line_range(hunk)

  -- For "change" hunks, new lines are shown as additions (green)
  local sign_type = hunk.type
  if sign_type == "change" then
    sign_type = "add"
  end

  for line = start_line, end_line do
    local sign_id = M.place(bufnr, line, sign_type)
    table.insert(sign_ids, sign_id)
  end

  return sign_ids
end

--- Remove a sign by ID
---@param bufnr number Buffer number
---@param sign_id number Sign ID
function M.remove(bufnr, sign_id)
  vim.fn.sign_unplace("patchview", { buffer = bufnr, id = sign_id })
end

--- Clear all signs in a buffer
---@param bufnr number Buffer number
function M.clear(bufnr)
  vim.fn.sign_unplace("patchview", { buffer = bufnr })
end

--- Clear all signs in all buffers
function M.clear_all()
  vim.fn.sign_unplace("patchview")
end

--- Get sign name for change type
---@param change_type string
---@return string
function M.get_sign_name(change_type)
  if change_type == "add" then
    return M.SIGN_ADD
  elseif change_type == "delete" then
    return M.SIGN_DELETE
  else
    return M.SIGN_CHANGE
  end
end

return M
