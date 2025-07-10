local M = {}

-- Registry for diff tool implementations
local diff_tools = {}

-- Registry for URI handlers
local uri_handlers = {}

-- Flag to track if URI handlers are initialized
local uri_handlers_initialized = false

-- Initialize URI handlers (called lazily)
local function ensure_uri_handlers_initialized()
  if uri_handlers_initialized then
    return
  end
  uri_handlers_initialized = true

  -- Register known diff tool URI handlers
  -- This is done lazily to avoid circular dependencies
  local known_handlers = {
    ["^diffview://"] = "diffview",
    ["^alt%-diffview://"] = "alt-diffview"
  }

  for pattern, scheme in pairs(known_handlers) do
    table.insert(uri_handlers, {
      pattern = pattern,
      handler = M.create_git_uri_handler(scheme)
    })
  end
end

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
    vim.notify(string.format("reviewthem.nvim: Unknown diff tool '%s'", tool_name), vim.log.levels.ERROR)
    return false
  end

  if not tool.start then
    vim.notify(string.format("reviewthem.nvim: Diff tool '%s' does not implement start()", tool_name), vim.log.levels.ERROR)
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

-- Extract relative path from a URI
M.extract_relative_path = function(uri)
  ensure_uri_handlers_initialized()
  for _, entry in ipairs(uri_handlers) do
    if uri:match(entry.pattern) then
      return entry.handler(uri)
    end
  end
  -- If no handler matches, return nil
  return nil
end

-- Common handler for diffview-style URIs
-- Format: scheme:///path/to/repo/.git/commit_hash/relative/path/to/file
M.create_git_uri_handler = function(scheme)
  return function(uri)
    -- Extract path after the scheme
    local path = uri:gsub("^" .. scheme .. "://", "")

    -- Find .git directory and extract relative path after commit hash
    local git_pattern = "/.git/[^/]+/"
    local _, end_pos = path:find(git_pattern)

    if end_pos then
      -- Return the path after the commit hash
      return path:sub(end_pos + 1)
    end

    -- Fallback: try to get relative path using git module
    local git = require("reviewthem.git")
    local git_root = git.get_git_root()
    if git_root then
      local pattern = vim.pesc(git_root) .. "/.git/[^/]+/"
      local relative = path:gsub(pattern, "")
      return relative
    end

    return nil
  end
end

return M

