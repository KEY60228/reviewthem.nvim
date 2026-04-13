local M = {}

local SESSION_VERSION = 2

---@return string
local function get_base_dir()
  return vim.fn.stdpath("data") .. "/reviewthem/sessions"
end

---@param project_root string
---@return string
local function project_hash(project_root)
  return vim.fn.sha256(project_root):sub(1, 16)
end

---@param project_root string
---@return string
local function get_project_dir(project_root)
  return get_base_dir() .. "/" .. project_hash(project_root)
end

---@param project_root string
---@param session_id string
---@return string
local function get_session_path(project_root, session_id)
  return get_project_dir(project_root) .. "/" .. session_id .. ".json"
end

--- Save a session to disk.
---@param session ReviewSession
---@return boolean
M.save = function(session)
  local dir = get_project_dir(session.project_root)
  vim.fn.mkdir(dir, "p")

  session.version = SESSION_VERSION
  session.updated_at = os.time()

  local json = vim.json.encode(session)
  local path = get_session_path(session.project_root, session.id)

  local f = io.open(path, "w")
  if not f then
    vim.notify("reviewthem.nvim: Failed to save session to " .. path, vim.log.levels.ERROR)
    return false
  end
  f:write(json)
  f:close()
  return true
end

--- Load a session from disk.
---@param project_root string
---@param session_id string
---@return ReviewSession|nil
M.load = function(project_root, session_id)
  local path = get_session_path(project_root, session_id)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()

  local ok, session = pcall(vim.json.decode, content)
  if not ok or not session then
    vim.notify("reviewthem.nvim: Failed to parse session file: " .. path, vim.log.levels.ERROR)
    return nil
  end

  if session.version ~= SESSION_VERSION then
    vim.notify("reviewthem.nvim: Incompatible session version in " .. path, vim.log.levels.WARN)
    return nil
  end

  return session
end

--- Delete a session from disk.
---@param project_root string
---@param session_id string
---@return boolean
M.delete = function(project_root, session_id)
  local path = get_session_path(project_root, session_id)
  local ok = os.remove(path)
  return ok ~= nil
end

--- List all sessions for a project.
---@param project_root string
---@return ReviewSession[]
M.list = function(project_root)
  local dir = get_project_dir(project_root)
  local sessions = {}

  local handle = vim.loop.fs_scandir(dir)
  if not handle then
    return sessions
  end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end
    if type == "file" and name:match("%.json$") then
      local session_id = name:gsub("%.json$", "")
      local session = M.load(project_root, session_id)
      if session then
        table.insert(sessions, session)
      end
    end
  end

  -- Sort by updated_at descending
  table.sort(sessions, function(a, b)
    return (a.updated_at or 0) > (b.updated_at or 0)
  end)

  return sessions
end

return M
