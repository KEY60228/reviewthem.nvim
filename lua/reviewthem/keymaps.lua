local M = {}

local DIFF_BUF_NAMES = { "reviewthem://old", "reviewthem://new" }

--- Apply review keymaps to a single diff buffer (idempotent).
---@param bufnr number
local function apply_diff_keymaps(bufnr)
  if vim.b[bufnr].reviewthem_keymaps_set then
    return
  end
  vim.b[bufnr].reviewthem_keymaps_set = true

  local config = require("reviewthem.config").get()
  local km = config.keymaps

  local function map(mode, key, cmd, desc)
    if key and key ~= "" then
      vim.keymap.set(mode, key, cmd, { buffer = bufnr, silent = true, desc = desc })
    end
  end

  -- Comment
  map("n", km.add_comment, "<cmd>ReviewThemAddComment<CR>", "Add comment")
  map("v", km.add_comment, ":'<,'>ReviewThemAddComment<CR>", "Add comment (range)")

  -- Review
  map("n", km.toggle_reviewed, "<cmd>ReviewThemToggleReviewed<CR>", "Toggle reviewed")
  map("n", km.submit_review, "<cmd>ReviewThemSubmit<CR>", "Submit review")
  map("n", km.show_comments, "<cmd>ReviewThemShowComments<CR>", "Show comments")

  -- Tree / session
  map("n", km.focus_tree, function()
    local file_tree = require("reviewthem.ui.file_tree")
    if file_tree.is_open() then
      local winnr = file_tree.get_winnr()
      if winnr and vim.api.nvim_win_is_valid(winnr) then
        vim.api.nvim_set_current_win(winnr)
      end
    else
      vim.cmd("ReviewThemTree")
    end
  end, "Focus file tree")
  map("n", km.close_review, "<cmd>ReviewThemPause<CR>", "Close/pause review")
end

--- Set up keymaps for diff buffers.
M.setup_diff_keymaps = function()
  local group = vim.api.nvim_create_augroup("ReviewThemKeymaps", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = DIFF_BUF_NAMES,
    callback = function(ev)
      apply_diff_keymaps(ev.buf)
    end,
  })

  -- Diff buffers may already be open and focused (ui.open runs before this),
  -- and their BufEnter fired before the autocmd existed — apply directly.
  for _, name in ipairs(DIFF_BUF_NAMES) do
    local bufnr = vim.fn.bufnr(name)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      apply_diff_keymaps(bufnr)
    end
  end
end

return M
