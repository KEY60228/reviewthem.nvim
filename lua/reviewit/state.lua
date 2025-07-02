local M = {}

local state = {
  base_branch = nil,
  compare_branch = nil,
  diff_files = {},
  current_diff_tool = nil,
}

M.set_review_branches = function(base, compare)
  state.base_branch = base
  state.compare_branch = compare
end

M.set_diff_files = function(files)
  state.diff_files = files
end

M.set_current_diff_tool = function(tool)
  state.current_diff_tool = tool
end

return M

