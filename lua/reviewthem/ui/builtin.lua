local M = {}

-- Check if builtin UI is available (always true)
M.is_available = function()
  return true
end

-- Show comments using default Neovim UI
M.show_comments = function()
  local state = require("reviewthem.state")
  local all_comments = state.get_comments()
  local lines = {"Review Comments:", ""}

  for file, file_comments in pairs(all_comments) do
    table.insert(lines, "File: " .. file)
    for _, comment in ipairs(file_comments) do
      if comment.line_start == comment.line_end then
        table.insert(lines, string.format("  Line %d: %s", comment.line_start, comment.text))
      else
        table.insert(lines, string.format("  Lines %d-%d: %s", comment.line_start, comment.line_end, comment.text))
      end
    end
    table.insert(lines, "")
  end

  if #lines == 2 then
    vim.notify("No comments added yet", vim.log.levels.INFO)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  local width = math.min(80, vim.o.columns - 10)
  local height = math.min(#lines + 2, vim.o.lines - 10)

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " Review Comments ",
    title_pos = "center",
  })
end

-- Show review status using default Neovim UI
M.show_status = function()
  local state = require("reviewthem.state")
  local base, compare = state.get_review_branches()

  local lines = {
    "Review Status",
    "",
    string.format("Base: %s", base),
    string.format("Compare: %s", compare or "Working Directory"),
    "",
  }

  local files = state.get_diff_files()
  if #files == 0 then
    vim.notify("No files in the current review session.", vim.log.levels.INFO)
    return
  end
  local reviewed_count = 0

  table.insert(lines, "Files:")
  for _, file in ipairs(files) do
    local reviewed = state.is_file_reviewed(file)
    if reviewed then
      reviewed_count = reviewed_count + 1
    end
    local status = reviewed and "[✓]" or "[ ]"
    table.insert(lines, string.format("  %s %s", status, file))
  end

  table.insert(lines, "")
  table.insert(lines, string.format("Progress: %d/%d files reviewed", reviewed_count, #files))

  local all_comments = state.get_comments()
  local comment_count = 0
  for _, file_comments in pairs(all_comments) do
    comment_count = comment_count + #file_comments
  end
  table.insert(lines, string.format("Total comments: %d", comment_count))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  local width = math.min(60, vim.o.columns - 10)
  local height = math.min(#lines + 2, vim.o.lines - 10)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " Review Status ",
    title_pos = "center",
  })

  -- Set up keymaps for the buffer
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })

  -- Add toggle functionality
  vim.api.nvim_buf_set_keymap(buf, "n", "t", "", {
    noremap = true,
    silent = true,
    callback = function()
      local line = vim.api.nvim_win_get_cursor(win)[1]
      local line_content = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]

      -- Extract file name from the line
      local file = line_content:match("%s*%[.%]%s+(.+)")
      if file then
        -- Toggle the reviewed status
        if state.is_file_reviewed(file) then
          state.unmark_file_reviewed(file)
        else
          state.mark_file_reviewed(file)
        end

        -- Refresh the display
        vim.api.nvim_win_close(win, true)
        M.show_status()
      end
    end
  })

  -- Add help text
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
    "",
    "Press 't' to toggle reviewed status, 'q' or <Esc> to close"
  })
end

return M

