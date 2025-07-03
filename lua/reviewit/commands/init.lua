local M = {}

M.setup = function()
  local config = require("reviewit.config")
  local review = require("reviewit.commands.review")
  local comments = require("reviewit.commands.comments")
  local files = require("reviewit.commands.files")

  vim.api.nvim_create_user_command("ReviewitStart", function(args)
    local base_branch = args.fargs[1]
    local compare_branch = args.fargs[2]
    review.start(base_branch, compare_branch)
  end, {
      nargs = "*",
      desc = "Start a code review between two branches",
    })

  -- Create command abbreviation from config
  local opts = config.get()
  if opts.command_aliases and opts.command_aliases.review_start then
    vim.cmd(string.format("cnoreabbrev %s ReviewitStart", opts.command_aliases.review_start))
  end

  vim.api.nvim_create_user_command("ReviewitAddComment", function(args)
    if args.range == 2 then
      -- Range specified (Visual mode or :<range>ReviewitAddComment)
      comments.add_comment_with_range(args.line1, args.line2)
    else
      -- No range (Normal mode)
      comments.add_comment()
    end
  end, {
      desc = "Add a comment to the current line or selection",
      range = true,
    })

  vim.api.nvim_create_user_command("ReviewitSubmit", function()
    review.submit()
  end, {
      desc = "Submit review comments",
    })

  vim.api.nvim_create_user_command("ReviewitAbort", function()
    review.abort()
  end, {
      desc = "Abort the current review session",
    })

  vim.api.nvim_create_user_command("ReviewitShowComments", function()
    comments.show_comments()
  end, {
      desc = "Show all review comments",
    })

  vim.api.nvim_create_user_command("ReviewitMarkAsReviewed", function()
    files.mark_current_file_reviewed()
  end, {
      desc = "Mark current file as reviewed",
    })

  vim.api.nvim_create_user_command("ReviewitUnmarkAsReviewed", function()
    files.unmark_current_file_reviewed()
  end, {
      desc = "Unmark current file as reviewed",
    })

  vim.api.nvim_create_user_command("ReviewitToggleReviewed", function()
    files.toggle_current_file_reviewed()
  end, {
      desc = "Toggle reviewed status of current file",
    })

  vim.api.nvim_create_user_command("ReviewitStatus", function()
    files.show_review_status()
  end, {
      desc = "Show review status of all files",
    })
end

return M

