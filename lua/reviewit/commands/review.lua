local M = {}
local git = require("reviewit.git")
local config = require("reviewit.config")
local state = require("reviewit.state")

M.start = function(base_ref, compare_ref)
  -- If no base_ref, use HEAD (current branch)
  -- If no compare_ref, compare with working directory (all uncommitted changes)
  if base_ref == nil or base_ref == "" then
    base_ref = "HEAD"
  end

  local valid, err = git.validate_references(base_ref, compare_ref)
  if not valid then
    vim.notify("reviewit.nvim: " .. err, vim.log.levels.ERROR)
    return
  end

  state.set_review_branches(base_ref, compare_ref)

  local files = git.get_diff_files(base_ref, compare_ref)
  if #files == 0 then
    vim.notify("reviewit.nvim: No differences found", vim.log.levels.INFO)
    return
  end

  state.set_diff_files(files)

  local opts = config.get()
  local diff = require("reviewit.diff")

  state.set_current_diff_tool(opts.diff_tool)

  local success = diff.start(opts.diff_tool, base_ref, compare_ref)
  if not success then
    vim.notify("reviewit.nvim: Failed to start diff tool", vim.log.levels.ERROR)
  end
end

return M

