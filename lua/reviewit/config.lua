local M = {}

M.defaults = {
  diff_tool = "diffview",  -- Currently only "diffview" is supported. More tools will be added in the future.
  comment_sign = "💬",
  submit_format = "markdown",  -- "markdown" or "json"
  submit_destination = "clipboard",  -- "clipboard" or file path relative to project root
  ui = "builtin",  -- "builtin" or "telescope"
}

M.options = {}

M.setup = function(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Validate diff_tool option
  if type(M.options.diff_tool) ~= "string" then
    vim.notify("reviewit.nvim: diff_tool option must be a string. Using default 'diffview'.", vim.log.levels.WARN)
    M.options.diff_tool = "diffview"
  end

  -- Register diff tools
  local diff = require("reviewit.diff")
  diff.register("diffview", require("reviewit.diff.diffview"))

  -- Check if configured diff tools is available
  if not diff.is_available(M.options.diff_tool) then
    vim.notify(string.format("reviewit.nvim: Diff tool '%s' not available. Falling back to 'diffview'.", M.options.diff_tool), vim.log.levels.WARN)
    M.options.diff_tool = "diffview"
  end

  -- Validate UI option
  if type(M.options.ui) ~= "string" then
    vim.notify("reviewit.nvim: ui option must be a string. Using default 'builtin'.", vim.log.levels.WARN)
    M.options.ui = "builtin"
  end

  -- Register UI providers
  local ui = require("reviewit.ui")
  ui.register("builtin", require("reviewit.ui.builtin"))
  ui.register("telescope", require("reviewit.ui.telescope"))

  -- Check if configured UI is available
  if not ui.is_available(M.options.ui) then
    vim.notify(string.format("reviewit.nvim: UI '%s' not available. Falling back to builtin.", M.options.ui), vim.log.levels.WARN)
    M.options.ui = "builtin"
  end
end

M.get = function()
  return M.options
end

return M

