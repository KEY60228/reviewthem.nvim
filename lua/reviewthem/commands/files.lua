local M = {}
local state = require("reviewthem.state")
local git = require("reviewthem.git")
local config = require("reviewthem.config")

M.mark_current_file_reviewed = function()
  if not state.ensure_review_active() then
    return
  end

  local absolute_path = vim.fn.expand("%:p")
  local file = git.get_relative_path(absolute_path)

  state.mark_file_reviewed(file)
  vim.notify(string.format("Marked %s as reviewed", file), vim.log.levels.INFO)
  M._update_signs()

  -- Update statusline for builtin diff
  vim.api.nvim_exec_autocmds("User", { pattern = "ReviewThemStatusChanged" })
end

M.unmark_current_file_reviewed = function()
  if not state.ensure_review_active() then
    return
  end

  local absolute_path = vim.fn.expand("%:p")
  local file = git.get_relative_path(absolute_path)

  state.unmark_file_reviewed(file)
  vim.notify(string.format("Unmarked %s as reviewed", file), vim.log.levels.INFO)
  M._update_signs()

  -- Update statusline for builtin diff
  vim.api.nvim_exec_autocmds("User", { pattern = "ReviewThemStatusChanged" })
end

M.toggle_current_file_reviewed = function()
  if not state.ensure_review_active() then
    return
  end

  local absolute_path = vim.fn.expand("%:p")
  local file = git.get_relative_path(absolute_path)

  if state.is_file_reviewed(file) then
    M.unmark_current_file_reviewed()
  else
    M.mark_current_file_reviewed()
  end
end

-- Helper function to update signs in the current buffer
M._update_signs = function()
  local absolute_path = vim.fn.expand("%:p")
  local file = git.get_relative_path(absolute_path)

  if state.is_file_reviewed(file) then
    vim.fn.sign_define("ReviewedFile", {
      text = "✓",
      texthl = "DiagnosticOk",
    })

    vim.fn.sign_place(0, "reviewthem_reviewed", "ReviewedFile", vim.fn.bufnr(), {
      lnum = 1,
      priority = 5,
    })
  else
    vim.fn.sign_unplace("reviewthem_reviewed")
  end
end

M.show_review_status = function()
  if not state.ensure_review_active() then
    return
  end

  local opts = config.get()
  local ui = require("reviewthem.ui")
  ui.show_status(opts.ui)
end

return M
