![ReviewThem Logo](public/logo.png)

# ReviewThem.nvim

A Neovim plugin for streamlining code reviews directly in your editor.

This project is inspired by [ReviewIt](https://github.com/yoshiko-pg/reviewit) - a fantastic code review tool. We created this Neovim-specific implementation with deep respect for the original work.

## Features

- 🔍 **Review Diffs**: Start review sessions between branches, commits, or uncommitted changes
- 💬 **Add Comments**: Comment on single lines or ranges with context
- ✅ **Track Progress**: Mark files as reviewed and monitor review status
- 📋 **Export Reviews**: Submit reviews in Markdown or JSON format
- 🎨 **Flexible UI**: Choose between builtin UI or Telescope integration

## Requirements

- Neovim >= 0.7.0
- Git
- [diffview.nvim](https://github.com/sindrets/diffview.nvim) (required for now - more diff tools coming soon!)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for enhanced UI)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "KEY60228/reviewthem.nvim",
  dependencies = {
    "sindrets/diffview.nvim",
    "nvim-telescope/telescope.nvim", -- optional
  },
  config = function()
    require("reviewthem").setup({
      -- your configuration here
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "KEY60228/reviewthem.nvim",
  requires = {
    "sindrets/diffview.nvim",
    "nvim-telescope/telescope.nvim", -- optional
  },
  config = function()
    require("reviewthem").setup({
      -- your configuration here
    })
  end,
}
```

## Configuration

```lua
require("reviewthem").setup({
  diff_tool = "diffview",              -- Currently only "diffview" is supported
  comment_sign = "💬",                 -- Sign shown in gutter for comments
  submit_format = "markdown",          -- "markdown" or "json"
  submit_destination = "clipboard",    -- "clipboard" or file path
  ui = "builtin",                      -- "builtin" or "telescope"
  keymaps = {
    start_review = "<leader>rstart",
    add_comment = "<leader>rtc",
    submit_review = "<leader>rtsubmit",
    abort_review = "<leader>rtabort",
    show_comments = "<leader>rtsc",
    toggle_reviewed = "<leader>rtmr",
    show_status = "<leader>rtrs",
  },
  command_aliases = {
    review_start = "rts",              -- :rts expands to :ReviewThemStart
  },
})
```

## Usage

### Basic Workflow

1. **Start a review session**
   ```vim
   :ReviewThemStart main feature-branch
   ```
   Or review uncommitted changes:
   ```vim
   :ReviewThemStart
   ```

2. **Navigate and add comments**
   - Use diffview to navigate through changes
   - Press `<leader>rtc` to add a comment on the current line
   - Select multiple lines in visual mode and press `<leader>rtc` for range comments

3. **Track your progress**
   - Press `<leader>rtmr` to mark the current file as reviewed
   - Press `<leader>rtrs` to see overall review status

4. **Submit your review**
   ```vim
   :ReviewThemSubmit
   ```

### Commands

| Command | Description |
|---------|-------------|
| `:ReviewThemStart [base] [compare]` | Start a review session |
| `:ReviewThemAddComment` | Add comment to current line/selection |
| `:ReviewThemSubmit` | Submit all review comments |
| `:ReviewThemAbort` | Abort current review session |
| `:ReviewThemShowComments` | Show all comments |
| `:ReviewThemMarkAsReviewed` | Mark current file as reviewed |
| `:ReviewThemUnmarkAsReviewed` | Unmark current file as reviewed |
| `:ReviewThemToggleReviewed` | Toggle reviewed status |
| `:ReviewThemStatus` | Show review status of all files |

### Key Mappings

Default mappings (customizable in setup):

| Mapping | Mode | Description |
|---------|------|-------------|
| `<leader>rstart` | n | Start review |
| `<leader>rtc` | n, v | Add comment |
| `<leader>rtsubmit` | n | Submit review |
| `<leader>rtabort` | n | Abort review |
| `<leader>rtsc` | n | Show comments |
| `<leader>rtmr` | n | Toggle reviewed |
| `<leader>rtrs` | n | Show status |

In the review status window:
- `t` - Toggle reviewed status (builtin UI)
- `<C-t>` - Toggle reviewed status (telescope UI)
- `q` or `<Esc>` - Close window

## Health Check

Run `:checkhealth reviewthem` to diagnose any issues with your setup.

## Example Review Output

### Markdown Format
```markdown
# Code Review

**Base:** main
**Compare:** feature/new-feature
**Date:** 2024-01-15 10:30:00

## Comments

### src/main.lua

- **Line 42:** Consider extracting this logic into a separate function
- **Lines 55-60:** This could be simplified using a table lookup

### tests/main_spec.lua

- **Line 23:** Add test case for edge condition
```

### JSON Format
```json
{
  "review": {
    "base_ref": "main",
    "compare_ref": "feature/new-feature",
    "timestamp": "2024-01-15 10:30:00",
    "comments": [
      {
        "file": "src/main.lua",
        "line_start": 42,
        "line_end": 42,
        "comment": "Consider extracting this logic into a separate function"
      }
    ]
  }
}
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Roadmap

### Planned Features

- **AddComment UX Improvements**
  - [ ] Float window input for better writing experience
  
- **Mark as Reviewed UX Improvements**
  - [ ] Display reviewed marks in file pane
  
- **ShowComments/ShowStatus UX Improvements**
  - [ ] Press Enter to jump to diff view from comment/status list
  
- **Extended Diff Tool Support**
  - [ ] Built-in diff mode support
  - [ ] Other popular diff tools
  
- **Extended UI Support**
  - [ ] FZF integration
  - [ ] Other popular UI frameworks

## Acknowledgments

- [ReviewIt](https://github.com/yoshiko-pg/reviewit) - The original ReviewIt tool that inspired this Neovim plugin. Thank you for the wonderful idea and implementation!
- [diffview.nvim](https://github.com/sindrets/diffview.nvim) for the excellent diff viewing functionality
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for the fuzzy finder integration
- [Oh My Logo](https://github.com/shinshin86/oh-my-logo) - The amazing tool used to create our logo. Thank you for making logo creation so simple and fun!

