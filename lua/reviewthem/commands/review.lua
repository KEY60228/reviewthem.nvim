local M = {}
local git = require("reviewthem.git")
local config = require("reviewthem.config")
local state = require("reviewthem.state")

-- If no base_ref, use HEAD (current branch)
-- If no compare_ref, compare with working directory (all uncommitted changes)
M.start = function(base_ref, compare_ref)
  local valid, err = git.validate_references(base_ref, compare_ref)
  if not valid then
    vim.notify("reviewthem.nvim: " .. err, vim.log.levels.ERROR)
    return
  end

  -- Start the review session
  state.start_review_session()
  state.set_review_branches(base_ref, compare_ref)

  local diff_results = git.get_diff_files(base_ref, compare_ref)
  if #diff_results == 0 then
    vim.notify("reviewthem.nvim: No differences found", vim.log.levels.INFO)
    state.end_review_session()  -- End session if no diffs
    return
  end

  -- Extract just the file names
  local files = {}
  for _, result in ipairs(diff_results) do
    table.insert(files, result.file)
  end

  state.set_diff_files(files)

  local opts = config.get()
  local diff = require("reviewthem.diff")

  state.set_current_diff_tool(opts.diff_tool)

  local success = diff.start(opts.diff_tool, base_ref, compare_ref)
  if not success then
    vim.notify("reviewthem.nvim: Failed to start diff tool", vim.log.levels.ERROR)
    state.end_review_session()  -- End session if diff tool fails
  else
    local msg
    if (base_ref == nil or base_ref == "") and (compare_ref == nil or compare_ref == "") then
      msg = "Review session started: HEAD...Working Directory"
    elseif compare_ref == nil or compare_ref == "" then
      msg = string.format("Review session started: %s...Working Directory", base_ref)
    else
      msg = string.format("Review session started: %s...%s", base_ref, compare_ref)
    end
    vim.notify(msg, vim.log.levels.INFO)
  end
end

M.submit = function()
  if not state.ensure_review_active() then
    return
  end

  local structured = state.get_all_comments_structured()

  if #structured.review.comments == 0 then
    vim.notify("No comments to submit", vim.log.levels.INFO)
    return
  end

  local opts = config.get()
  local output

  if opts.submit_format == "json" then
    output = vim.fn.json_encode(structured)
  else
    output = M.format_as_markdown(structured)
  end

  -- Handle output destination
  if opts.submit_destination == "clipboard" then
    vim.fn.setreg("+", output)
    vim.notify(string.format("Submitted %d comments to clipboard (%s format)",
      #structured.review.comments, opts.submit_format), vim.log.levels.INFO)
  else
    -- Write to file
    local git_root = git.get_git_root()
    if not git_root then
      vim.notify("Could not find git root directory", vim.log.levels.ERROR)
      return
    end

    -- Generate timestamp-based filename
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local ext = opts.submit_format == "json" and "json" or "md"
    local filename = string.format("%s_reviewthem.%s", timestamp, ext)

    -- Determine file path
    local file_path
    if opts.submit_destination:match("/$") then
      -- If submit_destination is a directory path
      file_path = git_root .. "/" .. opts.submit_destination .. filename
    else
      -- If submit_destination is a file path, use its directory
      local dir = vim.fn.fnamemodify(opts.submit_destination, ":h")
      if dir == "." then
        file_path = git_root .. "/" .. filename
      else
        file_path = git_root .. "/" .. dir .. "/" .. filename
      end
    end

    local file_dir = vim.fn.fnamemodify(file_path, ":h")

    -- Create directory if it doesn't exist
    vim.fn.mkdir(file_dir, "p")

    -- Write to file
    local file = io.open(file_path, "w")
    if file then
      file:write(output)
      file:close()
      vim.notify(string.format("Submitted %d comments to %s (%s format)",
        #structured.review.comments, filename, opts.submit_format), vim.log.levels.INFO)
    else
      vim.notify(string.format("Failed to write to file: %s", file_path), vim.log.levels.ERROR)
      return
    end
  end

  state.clear_comments()
  M._clear_signs()

  -- Close current diff tool
  local diff = require("reviewthem.diff")
  local current_tool = state.get_current_diff_tool()
  if current_tool then
    diff.close(current_tool)
  end

  -- End the review session
  state.end_review_session()

  vim.notify("Review completed", vim.log.levels.INFO)
end

M.format_as_markdown = function(structured)
  local lines = {
    "# Code Review",
    "",
    string.format("**Base:** %s", structured.review.base_ref or "N/A"),
    string.format("**Compare:** %s", structured.review.compare_ref or "Working Directory"),
    string.format("**Date:** %s", structured.review.timestamp),
    "",
  }

  table.insert(lines, "## Comments")
  table.insert(lines, "")

  local comments_by_file = {}
  for _, comment in ipairs(structured.review.comments) do
    if not comments_by_file[comment.file] then
      comments_by_file[comment.file] = {}
    end
    table.insert(comments_by_file[comment.file], comment)
  end

  for file, file_comments in pairs(comments_by_file) do
    table.insert(lines, string.format("### %s", file))
    table.insert(lines, "")
    for _, comment in ipairs(file_comments) do
      if comment.line_start == comment.line_end then
        table.insert(lines, string.format("#### Line %d", comment.line_start))
      else
        table.insert(lines, string.format("#### Lines %d-%d", comment.line_start, comment.line_end))
      end
      table.insert(lines, "")
      table.insert(lines, "```")
      table.insert(lines, comment.comment)
      table.insert(lines, "```")
      table.insert(lines, "")
    end
  end

  return table.concat(lines, "\n")
end

M.abort = function()
  if not state.ensure_review_active() then
    return
  end

  -- Confirm if there are unsaved comments
  local all_comments = state.get_comments()
  local comment_count = 0
  for _, file_comments in pairs(all_comments) do
    comment_count = comment_count + #file_comments
  end

  if comment_count > 0 then
    local confirm = vim.fn.confirm(
      string.format("Abort review? This will discard %d unsaved comment(s).", comment_count),
      "&Yes\n&No",
      2
    )
    if confirm ~= 1 then
      return
    end
  end

  -- Clear all state
  state.clear_comments()
  state.clear_reviewed_files()
  state.set_review_branches(nil, nil)
  state.set_diff_files({})

  -- Clear signs
  M._clear_signs()

  -- Close current diff tool
  local diff = require("reviewthem.diff")
  local current_tool = state.get_current_diff_tool()
  if current_tool then
    diff.close(current_tool)
    state.set_current_diff_tool(nil)
  end

  -- End the review session
  state.end_review_session()

  vim.notify("Review session aborted", vim.log.levels.INFO)
end

M._clear_signs = function()
  vim.fn.sign_unplace("reviewthem")
end

return M

