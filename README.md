# patchview.nvim

Real-time diff visualization for Neovim when external tools edit your files.

Similar to how GUI editors like Cursor show streaming diffs, patchview.nvim lets you see changes as they happen when tools like Claude Code, OpenCode, or other AI assistants modify your files.

## Features

- **Real-time file watching** - Detects external file changes instantly using `vim.loop` (libuv)
- **Inline diff visualization** - Shows added/removed/changed lines with highlights
- **Configurable acceptance modes**:
  - **Auto mode**: Changes apply automatically, you can undo
  - **Preview mode**: Review and accept/reject each change
- **Git-aware mode** - Distinguishes between external tool changes and git changes
- **Telescope integration** - Browse and act on changes with Telescope pickers
- **Hunk navigation** - Jump between changes with `]c` and `[c`

## Requirements

- Neovim 0.8+
- Optional: [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for enhanced change browsing
- Optional: Git (for git-aware mode)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yourusername/patchview.nvim",
  config = function()
    require("patchview").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "yourusername/patchview.nvim",
  config = function()
    require("patchview").setup()
  end,
}
```

## Quick Start

```lua
require("patchview").setup()
```

That's it! Patchview will automatically watch files you open and show diffs when external tools modify them.

## Configuration

```lua
require("patchview").setup({
  -- Watching behavior
  watch = {
    enabled = true,           -- Enable file watching by default
    debounce_ms = 100,        -- Debounce time for rapid changes
    ignore_patterns = {},     -- Patterns to ignore (e.g., "*.tmp")
  },

  -- Diff visualization
  diff = {
    algorithm = "myers",      -- "myers" or "patience"
    context_lines = 3,        -- Context lines around changes
  },

  -- Visual settings
  render = {
    style = "inline",         -- "inline", "signs", or "both"
    added_hl = "DiffAdd",     -- Highlight for added lines
    removed_hl = "DiffDelete",-- Highlight for removed lines
    changed_hl = "DiffChange",-- Highlight for changed lines
    show_removed_virtual = true, -- Show removed lines as virtual text
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
    baseline = "working_tree", -- "working_tree", "staged", or "head"
  },

  -- Telescope integration
  telescope = {
    enabled = true,           -- Enable telescope extension
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
    telescope_changes = "<leader>pf",
  },

  -- Notifications
  notify = {
    on_change = true,         -- Notify when changes detected
    on_accept = false,        -- Notify on accept
    on_reject = false,        -- Notify on reject
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:PatchviewEnable` | Enable watching for current buffer |
| `:PatchviewDisable` | Disable watching for current buffer |
| `:PatchviewToggle` | Toggle watching for current buffer |
| `:PatchviewStatus` | Show current watching status |
| `:PatchviewAcceptAll` | Accept all pending changes |
| `:PatchviewRejectAll` | Reject all pending changes |
| `:PatchviewMode [auto\|preview]` | Switch acceptance mode |
| `:PatchviewGit [on\|off]` | Toggle git-aware mode |
| `:PatchviewTelescope` | Open Telescope picker for changes |
| `:PatchviewSnapshot` | Take baseline snapshot |

## Keymaps

Default keymaps (can be customized or disabled):

| Key | Action |
|-----|--------|
| `]c` | Jump to next hunk |
| `[c` | Jump to previous hunk |
| `<leader>pa` | Accept current hunk |
| `<leader>pr` | Reject current hunk |
| `<leader>pA` | Accept all hunks |
| `<leader>pR` | Reject all hunks |
| `<leader>pp` | Toggle preview mode |
| `<leader>pf` | Open Telescope picker |

## Telescope Integration

If you have telescope.nvim installed, you can browse changes:

```vim
:Telescope patchview changes    " Browse all pending changes
:Telescope patchview files      " Browse files with changes
```

Or use `:PatchviewTelescope` / `<leader>pf`.

## Statusline Integration

Add patchview status to your statusline:

```lua
-- For lualine
require("lualine").setup({
  sections = {
    lualine_x = {
      { require("patchview").statusline },
    },
  },
})

-- Or get the raw component
local status = require("patchview.status").statusline_component()
```

## How It Works

1. **File Watching**: Patchview uses `vim.loop.new_fs_event()` to monitor files for external changes
2. **Diff Computation**: When a change is detected, it computes a diff between the baseline and new content using the Myers algorithm
3. **Visualization**: Changes are displayed using Neovim's extmarks for inline highlights and virtual text for removed lines
4. **Acceptance**: In auto mode, changes apply immediately (you can undo). In preview mode, you review each change before accepting

## Git-Aware Mode

When enabled, patchview can distinguish between:
- **External changes** (from AI tools) - highlighted prominently
- **Git unstaged changes** - shown with dimmer highlights
- **Git staged changes** - optionally shown

This helps you see what the AI tool changed vs what you changed manually.

## License

MIT

## Contributing

Contributions are welcome! Please open an issue or PR.
