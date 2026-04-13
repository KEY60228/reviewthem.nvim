local M = {}

--- Parse --name=X from command args.
---@param args string[]
---@return string|nil name, string[] remaining_args
local function extract_name_flag(args)
  local name = nil
  local remaining = {}
  for _, arg in ipairs(args) do
    local n = arg:match("^%-%-name=(.+)$")
    if n then
      name = n
    else
      table.insert(remaining, arg)
    end
  end
  return name, remaining
end

--- Generate a comment ID.
---@return string
local function gen_comment_id()
  local bytes = {}
  for _ = 1, 6 do
    table.insert(bytes, string.format("%02x", math.random(0, 255)))
  end
  return table.concat(bytes)
end

--- Command names by group for bulk delete.
local idle_command_names = {
  "ReviewThemStart", "ReviewThemSessions",
}
local session_command_names = {
  "ReviewThemPause", "ReviewThemSubmit", "ReviewThemAbort",
  "ReviewThemAddComment", "ReviewThemEditComment", "ReviewThemDeleteComment",
  "ReviewThemShowComments", "ReviewThemToggleReviewed", "ReviewThemTree",
}

--- Delete a list of user commands (ignoring errors for missing ones).
---@param names string[]
local function delete_commands(names)
  for _, name in ipairs(names) do
    pcall(vim.api.nvim_del_user_command, name)
  end
end

-- Forward declarations
local register_idle_commands, register_session_commands

--- Transition to session mode: remove idle commands, add session commands.
M.on_session_start = function()
  delete_commands(idle_command_names)
  register_session_commands()
end

--- Transition to idle mode: remove session commands, add idle commands.
M.on_session_end = function()
  delete_commands(session_command_names)
  register_idle_commands()
end

--- Register commands available when no review session is active.
register_idle_commands = function()
  local git = require("reviewthem.git")

  -- :ReviewThemStart [base] [compare] [--name=X]
  vim.api.nvim_create_user_command("ReviewThemStart", function(cmd)
    local args = vim.split(cmd.args, "%s+", { trimempty = true })
    local name, remaining = extract_name_flag(args)

    local base_ref = remaining[1]
    local compare_ref = remaining[2]

    local session_mod = require("reviewthem.session")
    local session, err = session_mod.create(base_ref, compare_ref, { name = name })
    if not session then
      vim.notify("reviewthem.nvim: " .. (err or "Failed to create session"), vim.log.levels.ERROR)
      return
    end

    local ui = require("reviewthem.ui")
    ui.open(session)
    require("reviewthem.keymaps").setup_diff_keymaps()
    M.on_session_start()

    vim.notify(string.format("Review session '%s' started (%d files)", session.name, #session.diff_files), vim.log.levels.INFO)
  end, {
    nargs = "*",
    complete = function(_, cmdline)
      local args = vim.split(cmdline, "%s+", { trimempty = true })
      local n = #args
      if cmdline:match("%s$") then
        n = n + 1
      end
      if n <= 3 then
        return git.get_refs()
      end
      return {}
    end,
    desc = "Start a new review session",
  })

  -- :ReviewThemSessions — Enter=resume, d=delete
  vim.api.nvim_create_user_command("ReviewThemSessions", function()
    local session_mod = require("reviewthem.session")
    local sessions = session_mod.list()

    if #sessions == 0 then
      vim.notify("No saved sessions for this project.", vim.log.levels.INFO)
      return
    end

    local function format_session(s)
      local reviewed = 0
      for _, f in ipairs(s.diff_files) do
        if s.reviewed_files[f.path] then reviewed = reviewed + 1 end
      end
      return string.format("%s (%d comments, %d/%d reviewed, %s)",
        s.name, #s.comments, reviewed, #s.diff_files,
        os.date("%m-%d %H:%M", s.updated_at))
    end

    local function highlight_session(s)
      local reviewed = 0
      for _, f in ipairs(s.diff_files) do
        if s.reviewed_files[f.path] then reviewed = reviewed + 1 end
      end
      local name_end = #s.name
      local comments_str = string.format("%d comments", #s.comments)
      local reviewed_str = string.format("%d/%d reviewed", reviewed, #s.diff_files)
      local date_str = os.date("%m-%d %H:%M", s.updated_at)
      -- "name (N comments, M/T reviewed, MM-DD HH:MM)"
      local comments_start = name_end + 2 -- " ("
      local reviewed_start = comments_start + #comments_str + 2 -- ", "
      local date_start = reviewed_start + #reviewed_str + 2 -- ", "
      return {
        { "Title", 0, name_end },
        { "ReviewThemTreeComment", comments_start, comments_start + #comments_str },
        { "ReviewThemTreeProgress", reviewed_start, reviewed_start + #reviewed_str },
        { "Comment", date_start, date_start + #date_str },
      }
    end

    local picker = require("reviewthem.ui.picker")
    picker.open(sessions, {
      prompt = "Sessions (Enter=resume, d=delete)",
      format_item = format_session,
      highlight_item = highlight_session,
      on_delete = function(s)
        session_mod.delete_session(s.id)
        vim.notify(string.format("Deleted session '%s'", s.name), vim.log.levels.INFO)
      end,
    }, function(selected)
      if not selected then
        return
      end
      local session, err = session_mod.resume(selected.id)
      if not session then
        vim.notify("reviewthem.nvim: " .. (err or "Failed to resume"), vim.log.levels.ERROR)
        return
      end
      local ui = require("reviewthem.ui")
      ui.open(session)
      require("reviewthem.keymaps").setup_diff_keymaps()
      M.on_session_start()
      vim.notify(string.format("Resumed session '%s'", session.name), vim.log.levels.INFO)
    end)
  end, {
    desc = "List sessions (Enter=resume, d=delete)",
  })
end

--- Register commands available only during an active review session.
register_session_commands = function()
  -- :ReviewThemPause
  vim.api.nvim_create_user_command("ReviewThemPause", function()
    local ui = require("reviewthem.ui")
    ui.close()
    local session_mod = require("reviewthem.session")
    session_mod.pause()
    M.on_session_end()
    vim.notify("Review session paused.", vim.log.levels.INFO)
  end, {
    desc = "Pause the current review session",
  })

  -- :ReviewThemSubmit
  vim.api.nvim_create_user_command("ReviewThemSubmit", function()
    local session_mod = require("reviewthem.session")
    local output, err = session_mod.submit()
    if not output then
      vim.notify("reviewthem.nvim: " .. (err or "Failed to submit"), vim.log.levels.ERROR)
      return
    end

    local ui = require("reviewthem.ui")
    ui.close()
    local state = require("reviewthem.session.state")
    state.clear_active()
    M.on_session_end()

    vim.notify("Review copied to clipboard! Ready to paste to your coding agent.", vim.log.levels.INFO)
  end, {
    desc = "Submit review and copy to clipboard",
  })

  -- :ReviewThemAbort
  vim.api.nvim_create_user_command("ReviewThemAbort", function()
    local state = require("reviewthem.session.state")
    local session = state.get_active()
    if not session then
      return
    end

    local function do_abort()
      local ui = require("reviewthem.ui")
      ui.close()
      require("reviewthem.session").abort()
      M.on_session_end()
      vim.notify("Review session aborted.", vim.log.levels.INFO)
    end

    if #session.comments > 0 then
      local picker = require("reviewthem.ui.picker")
      picker.open({ "Yes", "No" }, {
        prompt = string.format("Discard session '%s' with %d comments?", session.name, #session.comments),
      }, function(choice)
        if choice == "Yes" then
          do_abort()
        end
      end)
    else
      do_abort()
    end
  end, {
    desc = "Abort and discard the current review session",
  })

  -- :ReviewThemAddComment
  vim.api.nvim_create_user_command("ReviewThemAddComment", function(cmd)
    local state = require("reviewthem.session.state")
    local session = state.get_active()
    local ui_mod = require("reviewthem.ui")
    local context = ui_mod.get_cursor_context()

    if not context then
      vim.notify("Place cursor on a diff line to add a comment.", vim.log.levels.WARN)
      return
    end

    local start_line = context.lineno
    local end_line = context.lineno
    if cmd.range == 2 then
      end_line = start_line + (cmd.line2 - cmd.line1)
    end

    local prefix = context.hunk_line.type == "add" and "+" or
                   context.hunk_line.type == "remove" and "-" or " "
    local preview = {
      string.format("%s %d: %s", prefix, context.lineno, context.hunk_line.content),
    }

    local diff_parser = require("reviewthem.git.diff_parser")
    local diff_hunk
    for _, file in ipairs(session.diff_files) do
      if file.path == context.file then
        diff_hunk = diff_parser.get_hunk_context(file.hunks, context.side, context.lineno)
        break
      end
    end

    local comment_input = require("reviewthem.ui.comment_input")
    comment_input.open({
      title = string.format("Comment: %s:%d (%s)", context.file, context.lineno, context.side),
      preview_lines = preview,
      on_confirm = function(text)
        ---@type Comment
        local comment = {
          id = gen_comment_id(),
          file = context.file,
          side = context.side,
          start_line = start_line,
          end_line = end_line,
          text = text,
          diff_hunk = diff_hunk,
          created_at = os.time(),
          updated_at = os.time(),
        }
        state.add_comment(comment)
        ui_mod.refresh()
        vim.notify(string.format("Comment added to %s:%d", context.file, context.lineno), vim.log.levels.INFO)
      end,
    })
  end, {
    range = true,
    desc = "Add a comment at the current diff line",
  })

  -- :ReviewThemEditComment
  vim.api.nvim_create_user_command("ReviewThemEditComment", function()
    local state = require("reviewthem.session.state")
    local ui_mod = require("reviewthem.ui")
    local context = ui_mod.get_cursor_context()
    if not context then
      vim.notify("Place cursor on a diff line with a comment.", vim.log.levels.WARN)
      return
    end

    local comments = state.get_file_comments(context.file)
    local target = nil
    for _, c in ipairs(comments) do
      if c.side == context.side and c.start_line <= context.lineno and c.end_line >= context.lineno then
        target = c
        break
      end
    end

    if not target then
      vim.notify("No comment at this position.", vim.log.levels.WARN)
      return
    end

    local comment_input = require("reviewthem.ui.comment_input")
    comment_input.open({
      title = string.format("Edit Comment: %s:%d", target.file, target.start_line),
      initial_text = target.text,
      on_confirm = function(text)
        state.update_comment(target.id, text)
        ui_mod.refresh()
        vim.notify("Comment updated.", vim.log.levels.INFO)
      end,
    })
  end, {
    desc = "Edit the comment at the current position",
  })

  -- :ReviewThemDeleteComment
  vim.api.nvim_create_user_command("ReviewThemDeleteComment", function()
    local state = require("reviewthem.session.state")
    local ui_mod = require("reviewthem.ui")
    local context = ui_mod.get_cursor_context()
    if not context then
      vim.notify("Place cursor on a diff line with a comment.", vim.log.levels.WARN)
      return
    end

    local comments = state.get_file_comments(context.file)
    local target = nil
    for _, c in ipairs(comments) do
      if c.side == context.side and c.start_line <= context.lineno and c.end_line >= context.lineno then
        target = c
        break
      end
    end

    if not target then
      vim.notify("No comment at this position.", vim.log.levels.WARN)
      return
    end

    state.remove_comment(target.id)
    ui_mod.refresh()
    vim.notify("Comment deleted.", vim.log.levels.INFO)
  end, {
    desc = "Delete the comment at the current position",
  })

  -- :ReviewThemShowComments
  vim.api.nvim_create_user_command("ReviewThemShowComments", function()
    local state = require("reviewthem.session.state")
    local session = state.get_active()
    local ui_mod = require("reviewthem.ui")

    local comments = session.comments
    if #comments == 0 then
      vim.notify("No comments in this review session.", vim.log.levels.INFO)
      return
    end

    -- Sort by file, then line
    local sorted = vim.deepcopy(comments)
    table.sort(sorted, function(a, b)
      if a.file ~= b.file then
        return a.file < b.file
      end
      return a.start_line < b.start_line
    end)

    local picker = require("reviewthem.ui.picker")
    picker.open(sorted, {
      prompt = string.format("Comments (%d) — Enter=jump, d=delete", #sorted),
      format_item = function(c)
        local line_info = c.start_line == c.end_line
          and string.format("L%d", c.start_line)
          or string.format("L%d-%d", c.start_line, c.end_line)
        local first_line = c.text:match("^([^\n]*)") or ""
        return string.format("%s:%s (%s): %s", c.file, line_info, c.side, first_line)
      end,
      highlight_item = function(c)
        local line_info = c.start_line == c.end_line
          and string.format("L%d", c.start_line)
          or string.format("L%d-%d", c.start_line, c.end_line)
        local file_end = #c.file
        local line_end = file_end + 1 + #line_info -- ":"  + line_info
        local side_start = line_end + 2 -- " ("
        local side_end = side_start + #c.side
        return {
          { "Directory", 0, file_end },
          { "Number", file_end + 1, line_end },
          { c.side == "new" and "ReviewThemTreeAdded" or "ReviewThemTreeDeleted", side_start, side_end },
        }
      end,
      on_delete = function(c)
        state.remove_comment(c.id)
        ui_mod.refresh()
        vim.notify("Comment deleted.", vim.log.levels.INFO)
      end,
    }, function(selected)
      if not selected then
        return
      end
      ui_mod.jump_to_file(selected.file, { side = selected.side, lineno = selected.start_line })
    end)
  end, {
    desc = "Show all review comments",
  })

  -- :ReviewThemToggleReviewed
  vim.api.nvim_create_user_command("ReviewThemToggleReviewed", function()
    local state = require("reviewthem.session.state")
    local ui_mod = require("reviewthem.ui")
    local context = ui_mod.get_cursor_context()
    if not context then
      vim.notify("Place cursor on a diff line to toggle reviewed.", vim.log.levels.WARN)
      return
    end

    local new_status = state.toggle_reviewed(context.file)
    ui_mod.refresh()
    vim.notify(
      string.format("%s: %s", context.file, new_status and "reviewed" or "not reviewed"),
      vim.log.levels.INFO
    )
  end, {
    desc = "Toggle reviewed status for the current file",
  })

  -- :ReviewThemTree
  vim.api.nvim_create_user_command("ReviewThemTree", function()
    local file_tree = require("reviewthem.ui.file_tree")
    if file_tree.is_open() then
      file_tree.close()
    else
      local state = require("reviewthem.session.state")
      local session = state.get_active()
      local ui_mod = require("reviewthem.ui")
      file_tree.open(session, function(file_path)
        ui_mod.jump_to_file(file_path)
      end, function(file_path)
        state.toggle_reviewed(file_path)
        file_tree.refresh(session)
      end)
    end
  end, {
    desc = "Toggle file tree sidebar",
  })

end

--- Initial command registration (idle mode).
M.register = function()
  register_idle_commands()
end

return M
