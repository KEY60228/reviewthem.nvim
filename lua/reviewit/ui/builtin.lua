local M = {}

-- Check if builtin UI is available (always true)
M.is_available = function()
  return true
end

-- Show comments using default Neovim UI
M.show_comments = function()
  local state = require("reviewit.state")
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

return M

