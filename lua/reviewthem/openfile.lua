local M = {}

--- Short, human-readable label for a resolved git ref.
---@param ref string
---@return string
local function ref_label(ref)
  if ref == ":0" then
    return "index"
  end
  if #ref == 40 and ref:match("^%x+$") then
    return ref:sub(1, 8)
  end
  return ref
end

--- Find a buffer by exact name (vim.fn.bufnr() would treat the name as a pattern).
---@param name string
---@return number|nil bufnr
local function find_buf_by_name(name)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(bufnr) == name then
      return bufnr
    end
  end
  return nil
end

--- The root the diff paths are relative to.
---@param session ReviewSession
---@return string|nil
local function repo_root(session)
  if session.project_root and session.project_root ~= "" then
    return session.project_root
  end
  return require("reviewthem.git").get_git_root()
end

--- Move the cursor to a line, clamped to the buffer, opening folds and centering.
---@param winnr number
---@param lineno number|nil
---@param file_path string
local function set_cursor_clamped(winnr, lineno, file_path)
  local bufnr = vim.api.nvim_win_get_buf(winnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local wanted = lineno or 1
  local target = math.max(1, math.min(wanted, line_count))
  vim.api.nvim_win_set_cursor(winnr, { target, 0 })
  vim.api.nvim_win_call(winnr, function()
    vim.cmd("normal! zvzz")
  end)
  if target ~= wanted then
    vim.notify(
      string.format(
        "reviewthem.nvim: '%s' has %d lines — showing line %d instead of %d.",
        file_path, line_count, target, wanted
      ),
      vim.log.levels.WARN
    )
  end
end

--- Open the working-tree version of a file in a new tab.
---@param session ReviewSession
---@param file_path string  Path relative to the git root
---@param lineno number
---@return boolean ok
local function open_working_tree_file(session, file_path, lineno)
  local root = repo_root(session)
  if not root then
    vim.notify("reviewthem.nvim: Not in a git repository.", vim.log.levels.ERROR)
    return false
  end

  local full_path = root .. "/" .. file_path
  if vim.fn.filereadable(full_path) == 0 then
    vim.notify(
      string.format("reviewthem.nvim: '%s' does not exist in the working tree.", file_path),
      vim.log.levels.WARN
    )
    return false
  end

  vim.cmd("tabedit " .. vim.fn.fnameescape(full_path))
  set_cursor_clamped(0, lineno, file_path)
  return true
end

--- Open the version of a file at a git ref in a readonly scratch buffer in a new tab.
---@param ref string
---@param file_path string  Path relative to the git root
---@param lineno number
---@return boolean ok
local function open_ref_file(ref, file_path, lineno)
  local git = require("reviewthem.git")
  local label = ref_label(ref)
  local lines = git.get_file_content(ref, file_path)
  if not lines then
    vim.notify(
      string.format("reviewthem.nvim: '%s' does not exist at '%s'.", file_path, label),
      vim.log.levels.WARN
    )
    return false
  end

  local bufname = string.format("reviewthem://%s:%s", label, file_path)
  local bufnr = find_buf_by_name(bufname)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, bufname)
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false

  -- Pass the buffer too, so content-based detection (shebangs) works
  local filetype = vim.filetype.match({ buf = bufnr, filename = file_path })
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

  set_cursor_clamped(0, lineno, file_path)

  -- q closes the tab and returns to the review tab
  vim.keymap.set("n", "q", function()
    if #vim.api.nvim_list_tabpages() > 1 then
      vim.cmd("tabclose")
    else
      vim.notify(
        "reviewthem.nvim: This is the only tab page — use :bdelete to close this view.",
        vim.log.levels.WARN
      )
    end
  end, { buffer = bufnr, nowait = true, silent = true, desc = "Close file view" })

  return true
end

--- Open the real file for the diff line under the cursor in a new tab.
--- Sides showing the working tree open the actual file; the others open a
--- readonly scratch buffer with the content the diff was generated from.
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

  local git = require("reviewthem.git")
  local ref = git.resolve_side_ref(session.base_ref, session.compare_ref, context.side)
  if ref == nil then
    open_working_tree_file(session, context.file, context.lineno)
  else
    open_ref_file(ref, context.file, context.lineno)
  end
end

return M
