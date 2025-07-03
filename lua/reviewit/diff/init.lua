local M = {}

-- Registry for diff tool implementations
local diff_tools = {}

-- Register a diff tool implementation
M.register = function(name, implementation)
  diff_tools[name] = implementation
end

-- Check if a tool is available
M.is_available = function(tool_name)
  local tool = diff_tools[tool_name]
  if tool and tool.is_available then
    return tool.is_available()
  end
  return false
end

-- Start diff with specified tool
M.start = function(tool_name, base_branch, compare_branch)
  local tool = diff_tools[tool_name]
  if not tool then
    vim.notify(string.format("reviewit.nvim: Unknown diff tool '%s'", tool_name), vim.log.levels.ERROR)
    return false
  end

  if not tool.start then
    vim.notify(string.format("reviewit.nvim: Diff tool '%s' does not implement start()", tool_name), vim.log.levels.ERROR)
    return false
  end

  return tool.start(base_branch, compare_branch)
end

-- Close current diff session
M.close = function(tool_name)
  local tool = diff_tools[tool_name]
  if tool and tool.close then
    tool.close()
  end
end

return M

