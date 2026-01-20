-- patchview.nvim - Git integration module
-- Provides git-aware change detection and classification

local M = {}

-- Cache for git info
M.cache = {
  repos = {},  -- { [dir] = { root = string, is_git = bool } }
  content = {}, -- { [filename] = { staged = lines, head = lines, timestamp = number } }
}

-- Cache TTL in milliseconds
M.CACHE_TTL = 5000

--- Check if a file is in a git repository
---@param filename string File path
---@return boolean, string|nil is_git, git_root
function M.is_git_repo(filename)
  local dir = vim.fn.fnamemodify(filename, ":h")

  -- Check cache
  if M.cache.repos[dir] then
    local cached = M.cache.repos[dir]
    return cached.is_git, cached.root
  end

  -- Run git rev-parse to find repo root
  local result = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  local is_git = vim.v.shell_error == 0

  local root = nil
  if is_git and result[1] then
    root = result[1]
  end

  -- Cache result
  M.cache.repos[dir] = { is_git = is_git, root = root }

  return is_git, root
end

--- Get the staged content of a file
---@param filename string File path
---@return string[]|nil Lines or nil if not staged/not in git
function M.get_staged_content(filename)
  local is_git, root = M.is_git_repo(filename)
  if not is_git then
    return nil
  end

  -- Get relative path
  local rel_path = M._get_relative_path(filename, root)
  if not rel_path then
    return nil
  end

  -- Check cache
  local cache_key = filename .. ":staged"
  local cached = M.cache.content[cache_key]
  if cached and (vim.loop.now() - cached.timestamp) < M.CACHE_TTL then
    return cached.lines
  end

  -- Get staged content using git show :0:<file>
  local result = vim.fn.systemlist({ "git", "-C", root, "show", ":0:" .. rel_path })
  if vim.v.shell_error ~= 0 then
    return nil
  end

  -- Cache result
  M.cache.content[cache_key] = {
    lines = result,
    timestamp = vim.loop.now(),
  }

  return result
end

--- Get the HEAD content of a file
---@param filename string File path
---@return string[]|nil Lines or nil if not in git
function M.get_head_content(filename)
  local is_git, root = M.is_git_repo(filename)
  if not is_git then
    return nil
  end

  local rel_path = M._get_relative_path(filename, root)
  if not rel_path then
    return nil
  end

  -- Check cache
  local cache_key = filename .. ":head"
  local cached = M.cache.content[cache_key]
  if cached and (vim.loop.now() - cached.timestamp) < M.CACHE_TTL then
    return cached.lines
  end

  -- Get HEAD content
  local result = vim.fn.systemlist({ "git", "-C", root, "show", "HEAD:" .. rel_path })
  if vim.v.shell_error ~= 0 then
    return nil
  end

  -- Cache result
  M.cache.content[cache_key] = {
    lines = result,
    timestamp = vim.loop.now(),
  }

  return result
end

--- Get the working tree content (from file system)
---@param filename string File path
---@return string[]|nil Lines
function M.get_working_tree_content(filename)
  local file = io.open(filename, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return vim.split(content, "\n", { plain = true })
end

--- Get baseline content based on configuration
---@param filename string File path
---@param baseline string "working_tree"|"staged"|"head"
---@return string[]|nil Lines
function M.get_baseline_content(filename, baseline)
  if baseline == "head" then
    return M.get_head_content(filename)
  elseif baseline == "staged" then
    return M.get_staged_content(filename) or M.get_head_content(filename)
  else -- working_tree
    return M.get_working_tree_content(filename)
  end
end

--- Classify a change as external or git-related
---@param filename string File path
---@param old_lines string[] Old content
---@param new_lines string[] New content
---@return string "external"|"git_unstaged"|"git_staged"
function M.classify_change(filename, old_lines, new_lines)
  local is_git, _ = M.is_git_repo(filename)

  if not is_git then
    return "external"
  end

  -- Get git baselines
  local staged = M.get_staged_content(filename)
  local head = M.get_head_content(filename)

  local diff_mod = require("patchview.diff")

  -- Check if change matches staged changes
  if staged then
    if diff_mod.lines_equal(new_lines, staged) then
      return "git_staged"
    end
  end

  -- Check if it's unstaged changes (different from HEAD but matches working tree pattern)
  if head then
    local head_to_new = diff_mod.compute(head, new_lines)
    local head_to_old = diff_mod.compute(head, old_lines)

    -- If old content matched HEAD and new doesn't, it's a new external change
    if #head_to_old == 0 and #head_to_new > 0 then
      return "external"
    end

    -- If both have changes from HEAD, classify based on the delta
    if #head_to_new > 0 then
      return "git_unstaged"
    end
  end

  return "external"
end

--- Get relative path from git root
---@param filename string Absolute file path
---@param git_root string Git repository root
---@return string|nil Relative path
function M._get_relative_path(filename, git_root)
  -- Normalize paths
  filename = vim.fn.fnamemodify(filename, ":p")
  git_root = vim.fn.fnamemodify(git_root, ":p")

  -- Remove trailing slashes
  git_root = git_root:gsub("/$", "")

  -- Check if file is under git root
  if filename:sub(1, #git_root) ~= git_root then
    return nil
  end

  -- Return relative path (without leading slash)
  return filename:sub(#git_root + 2)
end

--- Get git status for a file
---@param filename string File path
---@return table|nil Status { staged = bool, modified = bool, untracked = bool }
function M.get_file_status(filename)
  local is_git, root = M.is_git_repo(filename)
  if not is_git then
    return nil
  end

  local rel_path = M._get_relative_path(filename, root)
  if not rel_path then
    return nil
  end

  local result = vim.fn.systemlist({ "git", "-C", root, "status", "--porcelain", rel_path })
  if vim.v.shell_error ~= 0 or #result == 0 then
    return { staged = false, modified = false, untracked = false }
  end

  local status_line = result[1]
  local index_status = status_line:sub(1, 1)
  local worktree_status = status_line:sub(2, 2)

  return {
    staged = index_status ~= " " and index_status ~= "?",
    modified = worktree_status == "M",
    untracked = index_status == "?",
  }
end

--- Clear the cache
function M.clear_cache()
  M.cache.repos = {}
  M.cache.content = {}
end

--- Invalidate cache for a specific file
---@param filename string File path
function M.invalidate_cache(filename)
  local dir = vim.fn.fnamemodify(filename, ":h")
  M.cache.repos[dir] = nil
  M.cache.content[filename .. ":staged"] = nil
  M.cache.content[filename .. ":head"] = nil
end

return M
