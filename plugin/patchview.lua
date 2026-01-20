-- patchview.nvim plugin loader
-- Provides real-time diff visualization for external edits

if vim.g.loaded_patchview then
  return
end
vim.g.loaded_patchview = true

-- Minimum Neovim version check
if vim.fn.has("nvim-0.8") ~= 1 then
  vim.notify("patchview.nvim requires Neovim 0.8 or higher", vim.log.levels.ERROR)
  return
end

-- Plugin will be initialized when setup() is called
-- This allows for lazy loading via plugin managers
