local M = {}

local state = {
  base_branch = nil,
  compare_branch = nil,
  diff_files = {},
  comments = {},
  reviewed_files = {},
  current_diff_tool = nil,
}

M.set_review_branches = function(base, compare)
  state.base_branch = base
  state.compare_branch = compare
end

M.get_review_branches = function()
  return state.base_branch, state.compare_branch
end

M.set_diff_files = function(files)
  state.diff_files = files
end

M.get_diff_files = function()
  return state.diff_files
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

M.clear_comments = function()
  state.comments = {}
end

M.mark_file_reviewed = function(file)
  state.reviewed_files[file] = true
end

M.unmark_file_reviewed = function(file)
  state.reviewed_files[file] = nil
end

M.is_file_reviewed = function(file)
  return state.reviewed_files[file] == true
end

M.clear_reviewed_files = function()
  state.reviewed_files = {}
end

M.set_current_diff_tool = function(tool)
  state.current_diff_tool = tool
end

M.get_current_diff_tool = function()
  return state.current_diff_tool
end

M.get_all_comments_structured = function()
  local structured = {
    review = {
      base_ref = state.base_branch,
      compare_ref = state.compare_branch,
      timestamp = os.date("%Y-%m-%d %H:%M:%S"),
      comments = {},
    },
  }

  for file, file_comments in pairs(state.comments) do
    for _, comment in ipairs(file_comments) do
      table.insert(structured.review.comments, {
        file = file,
        line_start = comment.line_start,
        line_end = comment.line_end,
        comment = comment.text,
      })
    end
  end

  return structured
end

return M

