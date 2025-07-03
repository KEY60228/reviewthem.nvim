local M = {}
local state = require("reviewit.state")
local config = require("reviewit.config")
local git = require("reviewit.git")

-- Single line comment (Normal mode)
M.add_comment = function()
  local absolute_path = vim.fn.expand("%:p")
  local file = git.get_relative_path(absolute_path)
  local line = vim.fn.line(".")

  local prompt = string.format("Add comment for %s:%d: ", file, line)

  vim.ui.input({ prompt = prompt }, function(input)
    if input and input ~= "" then
      state.add_comment(file, line, line, input)
      M._update_signs()

      local msg = string.format("Comment added to %s:%d", file, line)
      vim.defer_fn(function()
        vim.notify(msg, vim.log.levels.INFO)
      end, 100)
    end
  end)
end

-- Range comment (Visual mode or command line range)
M.add_comment_with_range = function(line_start, line_end)
  local absolute_path = vim.fn.expand("%:p")
  local file = git.get_relative_path(absolute_path)

  local prompt
  if line_start == line_end then
    prompt = string.format("Add comment for %s:%d: ", file, line_start)
  else
    prompt = string.format("Add comment for %s:%d-%d: ", file, line_start, line_end)
  end

  vim.ui.input({ prompt = prompt }, function(input)
    if input and input ~= "" then
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
    end
  end)
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
    vim.fn.sign_place(0, "reviewit", "ReviewComment", vim.fn.bufnr(), {
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

return M

