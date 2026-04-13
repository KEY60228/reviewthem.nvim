local M = {}

M.defaults = {
  comment_sign = "💬",
  file_tree_width = 30,
  auto_save = true,
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
}

M.options = {}

---@param opts table|nil
M.setup = function(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

---@return table
M.get = function()
  return M.options
end

return M
