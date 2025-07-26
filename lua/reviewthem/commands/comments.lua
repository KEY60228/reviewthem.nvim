local M = {}
local state = require("reviewthem.state")
local config = require("reviewthem.config")
local git = require("reviewthem.git")
local float_input = require("reviewthem.float_input")

-- Single line comment (Normal mode)
M.add_comment = function()
  if not state.ensure_review_active() then
    return
  end

  local absolute_path = vim.fn.expand("%:p")
  local file = git.get_relative_path(absolute_path)
  local line = vim.fn.line(".")

  -- Get preview lines
  local current_line = vim.fn.getline(line)
  local preview_lines = { string.format("%4d: %s", line, current_line) }

  local title = string.format("Add comment for %s:%d", file, line)

  float_input.open({
    title = title,
    preview_lines = preview_lines,
    on_confirm = function(input)
      state.add_comment(file, line, line, input)
      M._update_signs()

      local msg = string.format("Comment added to %s:%d", file, line)
      vim.defer_fn(function()
        vim.notify(msg, vim.log.levels.INFO)
      end, 100)
    end,
  })
end

-- Range comment (Visual mode or command line range)
M.add_comment_with_range = function(line_start, line_end)
  if not state.ensure_review_active() then
    return
  end

  local absolute_path = vim.fn.expand("%:p")
  local file = git.get_relative_path(absolute_path)

  -- Get preview lines
  local preview_lines = {}
  for i = line_start, line_end do
    local line_content = vim.fn.getline(i)
    table.insert(preview_lines, string.format("%4d: %s", i, line_content))
  end

  local title
  if line_start == line_end then
    title = string.format("Add comment for %s:%d", file, line_start)
  else
    title = string.format("Add comment for %s:%d-%d", file, line_start, line_end)
  end

  float_input.open({
    title = title,
    preview_lines = preview_lines,
    on_confirm = function(input)
      state.add_comment(file, line_start, line_end, input)
      M._update_signs()

      local msg
      if line_start == line_end then
        msg = string.format("Comment added to %s:%d", file, line_start)
      else
        msg = string.format("Comment added to %s:%d-%d", file, line_start, line_end)
      end

      vim.defer_fn(function()
        vim.notify(msg, vim.log.levels.INFO)
      end, 100)
    end,
  })
end

M._update_signs = function()
  local opts = config.get()
  local absolute_path = vim.fn.expand("%:p")
  local file = git.get_relative_path(absolute_path)
  local comments = state.get_comments(file)

  if not comments or #comments == 0 then
    return
  end

  vim.fn.sign_define("ReviewComment", {
    text = opts.comment_sign,
    texthl = "DiagnosticInfo",
  })

  for _, comment in ipairs(comments) do
    vim.fn.sign_place(0, "reviewthem", "ReviewComment", vim.fn.bufnr(), {
      lnum = comment.line_start,
      priority = 10,
    })
  end
end

-- Helper: Create success message
M._create_success_message = function(file, line_start, line_end)
  if line_start == line_end then
    return string.format("Comment added to %s:%d", file, line_start)
  else
    return string.format("Comment added to %s:%d-%d", file, line_start, line_end)
  end
end

M.show_comments = function()
  if not state.ensure_review_active() then
    return
  end

  local opts = config.get()
  local ui = require("reviewthem.ui")
  ui.show_comments(opts.ui)
end

return M

