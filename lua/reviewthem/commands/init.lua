local M = {}

M.setup = function()
  local config = require("reviewthem.config")
  local review = require("reviewthem.commands.review")
  local comments = require("reviewthem.commands.comments")
  local files = require("reviewthem.commands.files")

  vim.api.nvim_create_user_command("ReviewThemStart", function(args)
    local base_branch = args.fargs[1]
    local compare_branch = args.fargs[2]
    review.start(base_branch, compare_branch)
  end, {
      nargs = "*",
      desc = "Start a code review between two branches",
      complete = function(ArgLead)
        local refs = {}

        -- Get branches
        local branches = vim.fn.systemlist("git branch -a --format='%(refname:short)'")
        for _, branch in ipairs(branches) do
          if branch:match("^" .. vim.pesc(ArgLead)) then
            table.insert(refs, branch)
          end
        end

        -- Get tags
        local tags = vim.fn.systemlist("git tag")
        for _, tag in ipairs(tags) do
          if tag:match("^" .. vim.pesc(ArgLead)) then
            table.insert(refs, tag)
          end
        end

        return refs
      end,
    })

  -- Create command abbreviation from config
  local opts = config.get()
  if opts.command_aliases and opts.command_aliases.review_start then
    vim.cmd(string.format("cnoreabbrev %s ReviewThemStart", opts.command_aliases.review_start))
  end

  vim.api.nvim_create_user_command("ReviewThemAddComment", function(args)
    if args.range == 2 then
      -- Range specified (Visual mode or :<range>ReviewThemAddComment)
      comments.add_comment_with_range(args.line1, args.line2)
    else
      -- No range (Normal mode)
      comments.add_comment()
    end
  end, {
      desc = "Add a comment to the current line or selection",
      range = true,
    })

  vim.api.nvim_create_user_command("ReviewThemSubmit", function()
    review.submit()
  end, {
      desc = "Submit review comments",
    })

  vim.api.nvim_create_user_command("ReviewThemAbort", function()
    review.abort()
  end, {
      desc = "Abort the current review session",
    })

  vim.api.nvim_create_user_command("ReviewThemShowComments", function()
    comments.show_comments()
  end, {
      desc = "Show all review comments",
    })

  vim.api.nvim_create_user_command("ReviewThemMarkAsReviewed", function()
    files.mark_current_file_reviewed()
  end, {
      desc = "Mark current file as reviewed",
    })

  vim.api.nvim_create_user_command("ReviewThemUnmarkAsReviewed", function()
    files.unmark_current_file_reviewed()
  end, {
      desc = "Unmark current file as reviewed",
    })

  vim.api.nvim_create_user_command("ReviewThemToggleReviewed", function()
    files.toggle_current_file_reviewed()
  end, {
      desc = "Toggle reviewed status of current file",
    })

  vim.api.nvim_create_user_command("ReviewThemStatus", function()
    files.show_review_status()
  end, {
      desc = "Show review status of all files",
    })
end

return M

