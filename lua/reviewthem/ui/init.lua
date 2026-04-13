local file_tree = require("reviewthem.ui.file_tree")
local diff_view = require("reviewthem.diff")

local M = {}

---@type ReviewSession|nil
local active_session = nil

---@type boolean Whether nvim-tree was open before review started
local nvimtree_was_open = false

--- Close nvim-tree if open, remember state for later restore.
local function suspend_nvimtree()
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok then
    return
  end
  nvimtree_was_open = api.tree.is_visible()
  if nvimtree_was_open then
    api.tree.close()
  end
end

--- Restore nvim-tree if it was open before review.
local function restore_nvimtree()
  if not nvimtree_was_open then
    return
  end
  nvimtree_was_open = false
  local ok, api = pcall(require, "nvim-tree.api")
  if ok then
    api.tree.open()
  end
end

--- Find the window displaying a buffer matching the given name pattern.
---@param pattern string
---@return number|nil winnr
local function find_win_by_buf_name(pattern)
  for _, winnr in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(winnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name:match(pattern) then
      return winnr
    end
  end
  return nil
end

--- Open the full review UI layout.
--- Layout: [file tree] [old (base)] [new (compare)]
---@param session ReviewSession
M.open = function(session)
  active_session = session

  suspend_nvimtree()

  -- Save the current window — this will become the "old" diff pane
  local orig_winnr = vim.api.nvim_get_current_win()

  -- 1. Open file tree sidebar (creates vsplit to the left)
  file_tree.open(session, function(file_path)
    vim.schedule(function()
      M.jump_to_file(file_path)
    end)
  end, function(file_path)
    local state = require("reviewthem.session.state")
    state.toggle_reviewed(file_path)
    file_tree.refresh(session)
  end)

  -- 2. orig_winnr is still valid — split it for old/new panes
  vim.api.nvim_set_current_win(orig_winnr)
  vim.cmd("vsplit")
  local new_winnr = vim.api.nvim_get_current_win()
  local old_winnr = orig_winnr

  -- 3. Render first file
  diff_view.open(session, old_winnr, new_winnr)

  -- 4. Focus the new (compare) pane
  vim.api.nvim_set_current_win(new_winnr)
end

--- Close the full review UI.
M.close = function()
  -- Mark as intentional so BufWinLeave protection doesn't auto-pause
  local split = require("reviewthem.diff.split")
  split.set_closing_intentionally()

  -- Ensure a surviving window by switching one diff pane to a blank buffer
  -- before deleting scratch buffers (which force-close their windows).
  local survivor = find_win_by_buf_name("reviewthem://new")
    or find_win_by_buf_name("reviewthem://old")
  if survivor and vim.api.nvim_win_is_valid(survivor) then
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(survivor, buf)
  end

  file_tree.close()
  diff_view.close()

  -- Close leftover empty windows from deleted buffers
  for _, winnr in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winnr) and #vim.api.nvim_list_wins() > 1 then
      local buf = vim.api.nvim_win_get_buf(winnr)
      local name = vim.api.nvim_buf_get_name(buf)
      if name == "" and vim.api.nvim_buf_line_count(buf) <= 1 then
        pcall(vim.api.nvim_win_close, winnr, true)
      end
    end
  end

  active_session = nil
  restore_nvimtree()
end

--- Refresh all UI components.
M.refresh = function()
  if not active_session then
    return
  end
  diff_view.refresh(active_session)
  if file_tree.is_open() then
    file_tree.refresh(active_session)
  end
end

--- Jump to a specific file in the diff.
---@param file_path string
---@param opts {side: string|nil, lineno: number|nil}|nil
M.jump_to_file = function(file_path, opts)
  if not active_session then
    return
  end

  for _, file in ipairs(active_session.diff_files) do
    if file.path == file_path then
      local old_winnr = find_win_by_buf_name("reviewthem://old")
      local new_winnr = find_win_by_buf_name("reviewthem://new")
      if old_winnr and new_winnr then
        diff_view.show_file(active_session, file, old_winnr, new_winnr)
        if opts and opts.side and opts.lineno then
          diff_view.jump_to_line(opts.side, opts.lineno)
        else
          vim.api.nvim_set_current_win(new_winnr)
        end
      end
      break
    end
  end
end

--- Get cursor context from the active diff view.
---@return table|nil
M.get_cursor_context = function()
  return diff_view.get_cursor_context()
end

--- Check if the UI is open.
---@return boolean
M.is_open = function()
  return active_session ~= nil
end

--- Get the active session from the UI.
---@return ReviewSession|nil
M.get_session = function()
  return active_session
end

return M
