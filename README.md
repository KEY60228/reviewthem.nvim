![ReviewThem Logo](public/logo.png)

# ReviewThem.nvim

A local code review tool for Neovim. Review diffs, add comments, and export Markdown — all inside your editor with zero plugin dependencies.

This project is inspired by [ReviewIt](https://github.com/yoshiko-pg/reviewit) - a fantastic code review tool. We created this Neovim-specific implementation with deep respect for the original work.

## Features

- **Split diff view** — Side-by-side old/new comparison with syntax highlighting
- **File tree sidebar** — Browse changed files, track review progress
- **Line-level comments** — Floating input window, supports multi-line ranges
- **Session management** — Named sessions persisted as JSON, pause and resume anytime
- **Markdown export** — Copy review output to clipboard, ready for coding agents
- **Context-aware commands** — Only relevant commands are available at each stage
- **Zero dependencies** — Requires only Neovim >= 0.10.0 and Git

## Requirements

- Neovim >= 0.10.0
- Git

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "KEY60228/reviewthem.nvim",
  config = function()
    require("reviewthem").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "KEY60228/reviewthem.nvim",
  config = function()
    require("reviewthem").setup()
  end,
}
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
   This opens a three-pane layout: file tree | old diff | new diff.

2. **Browse and comment**
   - Select files in the file tree sidebar
   - Press `<leader>rc` on a diff line to add a comment
   - Use visual mode for multi-line comments

3. **Track progress**
   - Press `r` in the file tree to mark files as reviewed
   - Progress is shown at the bottom of the file tree

4. **Submit your review**
   ```vim
   :ReviewThemSubmit
   ```
   Copies a Markdown summary to your clipboard.

5. **Pause and resume**
   ```vim
   :ReviewThemPause
   ```
   Later, resume with `:ReviewThemSessions`.

### Commands

Commands are context-aware — session management commands are only available when no review is active, and review commands are only available during an active session.

#### When no review is active

| Command | Description |
|---------|-------------|
| `:ReviewThemStart [base] [compare] [--name=X]` | Start a new review session |
| `:ReviewThemSessions` | List sessions (Enter=resume, d=delete) |

#### During an active review

| Command | Description |
|---------|-------------|
| `:ReviewThemAddComment` | Add comment to current line/selection |
| `:ReviewThemEditComment` | Edit comment at cursor position |
| `:ReviewThemDeleteComment` | Delete comment at cursor position |
| `:ReviewThemShowComments` | List all comments (Enter=jump, d=delete) |
| `:ReviewThemToggleReviewed` | Toggle reviewed status of current file |
| `:ReviewThemSubmit` | Export Markdown to clipboard and close |
| `:ReviewThemPause` | Close UI, keep session saved |
| `:ReviewThemAbort` | Discard session |
| `:ReviewThemTree` | Toggle file tree sidebar |

### Key Mappings

Default mappings in diff buffers (customizable in setup):

| Mapping | Description |
|---------|-------------|
| `<leader>rc` | Add comment (normal and visual mode) |
| `<leader>rs` | Submit review |
| `<leader>rv` | Toggle file reviewed status |
| `<leader>rl` | Show all comments |
| `<leader>re` | Focus file tree |
| `<leader>rq` | Pause / close review |

Comment input window:

| Mapping | Description |
|---------|-------------|
| `<A-CR>` | Confirm comment |
| `<Esc>` | Cancel |

File tree sidebar:

| Mapping | Description |
|---------|-------------|
| `<CR>` | Open file / toggle directory |
| `r` | Toggle reviewed status |
| `q` | Close file tree |

## Configuration

All options are optional — defaults are shown below:

```lua
require("reviewthem").setup({
  comment_sign = "💬",        -- sign shown on commented lines
  file_tree_width = 30,       -- sidebar width in columns
  auto_save = true,           -- auto-save session on changes
  keymaps = {
    add_comment = "<leader>rc",
    confirm_comment = "<A-CR>",
    cancel_comment = "<Esc>",
    submit_review = "<leader>rs",
    toggle_reviewed = "<leader>rv",
    show_comments = "<leader>rl",
    focus_tree = "<leader>re",
    close_review = "<leader>rq",
  },
})
```

## Health Check

```vim
:checkhealth reviewthem
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [ReviewIt](https://github.com/yoshiko-pg/reviewit) - The original ReviewIt tool that inspired this Neovim plugin
- [Oh My Logo](https://github.com/shinshin86/oh-my-logo) - The tool used to create our logo
