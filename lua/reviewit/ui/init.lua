local M = {}

-- Registry for UI implementations
local ui_providers = {}

-- Register a UI provider
M.register = function(name, implementation)
  ui_providers[name] = implementation
end

-- Check if a UI provider is available
M.is_available = function(ui_name)
  local provider = ui_providers[ui_name]
  if provider and provider.is_available then
    return provider.is_available()
  end
  return false
end

-- Show comments with specified UI
M.show_comments = function(ui_name)
  local provider = ui_providers[ui_name]
  if not provider then
    vim.notify(string.format("reviewit.nvim: Unknown UI provider '%s'", ui_name), vim.log.levels.ERROR)
    return false
  end

  if not provider.show_comments then
    vim.notify(string.format("reviewit.nvim: UI provider '%s' does not implement show_comments()", ui_name), vim.log.levels.ERROR)
    return false
  end

  return provider.show_comments()
end

return M