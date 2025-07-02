local M = {}

M.setup = function()
  local review = require("reviewit.commands.review")

  vim.api.nvim_create_user_command("ReviewitStart", function(args)
    local base_branch = args.fargs[1]
    local compare_branch = args.fargs[2]
    review.start(base_branch, compare_branch)
  end, {
      nargs = "*",
      desc = "Start a code review between two branches",
    })
end

return M

