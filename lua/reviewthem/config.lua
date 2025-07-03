local M = {}

M.defaults = {
  diff_tool = "diffview",  -- Currently only "diffview" is supported. More tools will be added soon!
  comment_sign = "💬",
  submit_format = "markdown",  -- "markdown" or "json"
  submit_destination = "clipboard",  -- "clipboard" or file path relative to project root
  ui = "builtin",  -- "builtin" or "telescope"
  keymaps = {
    start_review = "<leader>rtstart",
    add_comment = "<leader>rtc",
    submit_review = "<leader>rtsubmit",
    abort_review = "<leader>rtabort",
    show_comments = "<leader>rtsc",
    toggle_reviewed = "<leader>rtmr",
    show_status = "<leader>rtss",
  },
  command_aliases = {
    review_start = "rts",  -- Alias for ReviewThemStart
  },
}

M.options = {}

M.setup = function(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Validate diff_tool option
  if type(M.options.diff_tool) ~= "string" then
    vim.notify("reviewthem.nvim: diff_tool option must be a string. Using default 'diffview'.", vim.log.levels.WARN)
    M.options.diff_tool = "diffview"
  end

  -- Register diff tools
  local diff = require("reviewthem.diff")
  diff.register("diffview", require("reviewthem.diff.diffview"))

  -- Check if configured diff tools is available
  if not diff.is_available(M.options.diff_tool) then
    vim.notify(string.format("reviewthem.nvim: Diff tool '%s' not available. Falling back to 'diffview'.", M.options.diff_tool), vim.log.levels.WARN)
    M.options.diff_tool = "diffview"
  end

  -- Validate UI option
  if type(M.options.ui) ~= "string" then
    vim.notify("reviewthem.nvim: ui option must be a string. Using default 'builtin'.", vim.log.levels.WARN)
    M.options.ui = "builtin"
  end

  -- Register UI providers
  local ui = require("reviewthem.ui")
  ui.register("builtin", require("reviewthem.ui.builtin"))
  ui.register("telescope", require("reviewthem.ui.telescope"))

  -- Check if configured UI is available
  if not ui.is_available(M.options.ui) then
    vim.notify(string.format("reviewthem.nvim: UI '%s' not available. Falling back to builtin.", M.options.ui), vim.log.levels.WARN)
    M.options.ui = "builtin"
  end
end

M.get = function()
  return M.options
end

return M

