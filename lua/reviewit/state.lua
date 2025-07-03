local M = {}

local state = {
  base_branch = nil,
  compare_branch = nil,
  diff_files = {},
  comments = {},
  current_diff_tool = nil,
}

M.set_review_branches = function(base, compare)
  state.base_branch = base
  state.compare_branch = compare
end

M.set_diff_files = function(files)
  state.diff_files = files
end

M.add_comment = function(file, line_start, line_end, comment_text)
  if not state.comments[file] then
    state.comments[file] = {}
  end

  table.insert(state.comments[file], {
    line_start = line_start,
    line_end = line_end,
    text = comment_text,
    timestamp = os.time(),
  })
end

M.get_comments = function(file)
  if file then
    return state.comments[file] or {}
  end
  return state.comments
end

M.set_current_diff_tool = function(tool)
  state.current_diff_tool = tool
end

return M

