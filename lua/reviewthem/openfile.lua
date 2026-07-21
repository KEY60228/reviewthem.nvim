local M = {}

--- Clamp a line number to the buffer's line count and move the cursor there.
---@param winnr number
---@param lineno number
local function set_cursor_clamped(winnr, lineno)
  local bufnr = vim.api.nvim_win_get_buf(winnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local target = math.max(1, math.min(lineno or 1, line_count))
  vim.api.nvim_win_set_cursor(winnr, { target, 0 })
end

--- Open the working-tree version of a file in a new tab.
---@param file_path string  Path relative to the git root
---@param lineno number
---@return boolean ok
local function open_working_tree_file(file_path, lineno)
  local git = require("reviewthem.git")
  local git_root = git.get_git_root()
  if not git_root then
    vim.notify("reviewthem.nvim: Not in a git repository.", vim.log.levels.ERROR)
    return false
  end

  local full_path = git_root .. "/" .. file_path
  if vim.fn.filereadable(full_path) == 0 then
    vim.notify(
      string.format("reviewthem.nvim: '%s' does not exist in the working tree.", file_path),
      vim.log.levels.WARN
    )
    return false
  end

  vim.cmd("tabedit " .. vim.fn.fnameescape(full_path))
  set_cursor_clamped(0, lineno)
  return true
end

--- Open the version of a file at a git ref in a readonly scratch buffer in a new tab.
---@param ref string
---@param file_path string  Path relative to the git root
---@param lineno number
---@return boolean ok
local function open_ref_file(ref, file_path, lineno)
  local git = require("reviewthem.git")
  local lines = git.get_file_content(ref, file_path)
  if not lines then
    vim.notify(
      string.format("reviewthem.nvim: '%s' does not exist at '%s'.", file_path, ref),
      vim.log.levels.WARN
    )
    return false
  end

  local bufname = string.format("reviewthem://%s:%s", ref, file_path)
  local bufnr = vim.fn.bufnr(bufname)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, bufname)
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false

  local filetype = vim.filetype.match({ filename = file_path })
  if filetype then
    vim.bo[bufnr].filetype = filetype
  end

  -- Open in a new tab so the review layout stays untouched
  vim.cmd("tabnew")
  local placeholder = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_buf(0, bufnr)
  if placeholder ~= bufnr and vim.api.nvim_buf_is_valid(placeholder)
    and vim.api.nvim_buf_get_name(placeholder) == "" and not vim.bo[placeholder].modified then
    pcall(vim.api.nvim_buf_delete, placeholder, { force = true })
  end

  set_cursor_clamped(0, lineno)

  -- q closes the tab and returns to the review tab
  vim.keymap.set("n", "q", function()
    if #vim.api.nvim_list_tabpages() > 1 then
      vim.cmd("tabclose")
    end
  end, { buffer = bufnr, nowait = true, silent = true, desc = "Close file view" })

  return true
end

--- Open the real file for the diff line under the cursor in a new tab.
--- Working-tree reviews open the actual file; ref-based sides open a
--- readonly scratch buffer with the content at the relevant ref.
M.open_at_cursor = function()
  local ui = require("reviewthem.ui")
  local context = ui.get_cursor_context()
  if not context then
    vim.notify("Place cursor on a diff line to open the file.", vim.log.levels.WARN)
    return
  end

  local state = require("reviewthem.session.state")
  local session = state.get_active()
  if not session then
    vim.notify("reviewthem.nvim: No active review session.", vim.log.levels.WARN)
    return
  end

  if context.side == "new" and (session.compare_ref == nil or session.compare_ref == "") then
    -- Working-tree review: open the actual file
    open_working_tree_file(context.file, context.lineno)
  else
    local ref
    if context.side == "new" then
      ref = session.compare_ref
    else
      ref = session.base_ref or "HEAD"
    end
    open_ref_file(ref, context.file, context.lineno)
  end
end

return M
