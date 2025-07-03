local M = {}

M.setup = function()
  local config = require("reviewthem.config")
  local review = require("reviewthem.commands.review")
  local comments = require("reviewthem.commands.comments")
  local files = require("reviewthem.commands.files")

  local opts = config.get()
  local keymaps = opts.keymaps

  if keymaps.start_review then
    vim.keymap.set("n", keymaps.start_review, review.start, {
      desc = "Start review"
    })
  end

  if keymaps.add_comment then
    -- Normal mode
    vim.keymap.set("n", keymaps.add_comment, comments.add_comment, {
      desc = "Add review comment"
    })

    -- Visual mode - handle selected range
    vim.keymap.set("v", keymaps.add_comment, ":<C-u>lua require('reviewthem.commands.comments').add_comment_with_range(vim.fn.line(\"'<\"), vim.fn.line(\"'>\"))<CR>", {
        desc = "Add review comment to selected range"
      })
  end

  if keymaps.submit_review then
    vim.keymap.set("n", keymaps.submit_review, review.submit, {
      desc = "Submit review comments"
    })
  end

  if keymaps.abort_review then
    vim.keymap.set("n", keymaps.abort_review, review.abort, {
      desc = "Abort review"
    })
  end

  if keymaps.show_comments then
    vim.keymap.set("n", keymaps.show_comments, comments.show_comments, {
      desc = "Show review comments"
    })
  end

  if keymaps.toggle_reviewed then
    vim.keymap.set("n", keymaps.toggle_reviewed, files.toggle_current_file_reviewed, {
      desc = "Toggle file reviewed status"
    })
  end

  if keymaps.show_status then
    vim.keymap.set("n", keymaps.show_status, files.show_review_status, {
      desc = "Show review status"
    })
  end
end

return M

