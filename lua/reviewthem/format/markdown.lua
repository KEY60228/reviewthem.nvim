local M = {}

--- Format a session as agent-friendly Markdown.
---@param session ReviewSession
---@return string
M.format = function(session)
  local parts = {}

  -- Header
  table.insert(parts, "# Code Review: " .. session.name)
  table.insert(parts, "")
  table.insert(parts, string.format("- Base: `%s`", session.base_ref or "HEAD"))
  table.insert(parts, string.format("- Compare: `%s`", session.compare_ref or "working tree"))
  table.insert(parts, string.format("- Date: %s", os.date("%Y-%m-%d %H:%M:%S")))

  local reviewed_count = 0
  for _, file in ipairs(session.diff_files) do
    if session.reviewed_files[file.path] then
      reviewed_count = reviewed_count + 1
    end
  end
  table.insert(parts, string.format("- Files reviewed: %d/%d", reviewed_count, #session.diff_files))
  table.insert(parts, "")

  -- Group comments by file
  local comments_by_file = {}
  for _, c in ipairs(session.comments) do
    if not comments_by_file[c.file] then
      comments_by_file[c.file] = {}
    end
    table.insert(comments_by_file[c.file], c)
  end

  -- Sort files
  local file_order = {}
  for _, file in ipairs(session.diff_files) do
    table.insert(file_order, file)
  end

  for _, file in ipairs(file_order) do
    local file_comments = comments_by_file[file.path]
    if not file_comments or #file_comments == 0 then
      goto continue
    end

    -- Sort comments by line
    table.sort(file_comments, function(a, b)
      return a.start_line < b.start_line
    end)

    local status_label = ({
      A = "Added",
      M = "Modified",
      D = "Deleted",
      R = "Renamed",
    })[file.status] or file.status

    table.insert(parts, string.format("## %s (%s)", file.path, status_label))
    table.insert(parts, "")

    for _, c in ipairs(file_comments) do
      -- Line info
      local line_info
      if c.start_line == c.end_line then
        line_info = string.format("Line %d", c.start_line)
      else
        line_info = string.format("Lines %d-%d", c.start_line, c.end_line)
      end
      table.insert(parts, string.format("### %s (%s)", line_info, c.side))
      table.insert(parts, "")

      -- Diff hunk context
      if c.diff_hunk and c.diff_hunk ~= "" then
        table.insert(parts, "```diff")
        table.insert(parts, c.diff_hunk)
        table.insert(parts, "```")
        table.insert(parts, "")
      end

      -- Comment text
      table.insert(parts, "**Comment:** " .. c.text)
      table.insert(parts, "")
      table.insert(parts, "---")
      table.insert(parts, "")
    end

    ::continue::
  end

  -- Summary
  table.insert(parts, "## Summary")
  table.insert(parts, "")
  table.insert(parts, string.format("- Total comments: %d", #session.comments))

  local files_with_comments = 0
  for _ in pairs(comments_by_file) do
    files_with_comments = files_with_comments + 1
  end
  table.insert(parts, string.format("- Files with comments: %d/%d", files_with_comments, #session.diff_files))

  -- Reviewed/not reviewed lists
  local reviewed_list = {}
  local not_reviewed_list = {}
  for _, file in ipairs(session.diff_files) do
    if session.reviewed_files[file.path] then
      table.insert(reviewed_list, file.path)
    else
      table.insert(not_reviewed_list, file.path)
    end
  end

  if #reviewed_list > 0 then
    table.insert(parts, "- Reviewed: " .. table.concat(reviewed_list, ", "))
  end
  if #not_reviewed_list > 0 then
    table.insert(parts, "- Not reviewed: " .. table.concat(not_reviewed_list, ", "))
  end
  table.insert(parts, "")

  return table.concat(parts, "\n")
end

return M
