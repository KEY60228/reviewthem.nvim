local M = {}

--- Set a window option for one window only.
--- For window-local options `vim.wo[winnr].opt = value` behaves like `:set` when
--- winnr is the current window: it also overwrites the global value. That value
--- is what `:tabnew` / `:tabedit` initialise their window from, so the review UI
--- would leak its own options into tabs opened later (and outlive the session).
---@param winnr number
---@param name string
---@param value any
M.set_win_local = function(winnr, name, value)
  pcall(vim.api.nvim_set_option_value, name, value, { win = winnr, scope = "local" })
end

--- Read the value a window option has in one window.
---@param winnr number
---@param name string
---@return any|nil
M.get_win_local = function(winnr, name)
  local ok, value = pcall(vim.api.nvim_get_option_value, name, { win = winnr })
  if ok then
    return value
  end
  return nil
end

return M
