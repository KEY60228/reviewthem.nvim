local store = require("reviewthem.session.store")
local state = require("reviewthem.session.state")
local git = require("reviewthem.git")
local diff_parser = require("reviewthem.git.diff_parser")

local M = {}

--- Generate a unique session ID.
---@return string
local function generate_id()
  local random_bytes = {}
  for _ = 1, 8 do
    table.insert(random_bytes, string.format("%02x", math.random(0, 255)))
  end
  return table.concat(random_bytes)
end

--- Generate a default session name from refs.
---@param base_ref string|nil
---@param compare_ref string|nil
---@return string
local function default_name(base_ref, compare_ref)
  local base = base_ref or "HEAD"
  local compare = compare_ref or "working-tree"
  return base .. "..." .. compare
end

--- Parse hunks for all diff files in a session.
---@param session ReviewSession
local function parse_all_hunks(session)
  for _, file in ipairs(session.diff_files) do
    local diff_lines = git.get_file_diff(session.base_ref, session.compare_ref, file.path)
    file.hunks = diff_parser.parse(diff_lines)
  end
end

--- Create a new review session.
---@param base_ref string|nil
---@param compare_ref string|nil
---@param opts {name: string|nil}|nil
---@return ReviewSession|nil, string|nil error
M.create = function(base_ref, compare_ref, opts)
  opts = opts or {}

  -- Normalize empty strings to nil
  if base_ref == "" then
    base_ref = nil
  end
  if compare_ref == "" then
    compare_ref = nil
  end

  -- Validate refs
  local valid, err = git.validate_refs(base_ref, compare_ref)
  if not valid then
    return nil, err
  end

  local project_root = git.get_git_root()
  if not project_root then
    return nil, "Not in a git repository"
  end

  -- Get changed files
  local diff_files = git.get_diff_files(base_ref, compare_ref)
  if #diff_files == 0 then
    return nil, "No differences found"
  end

  ---@type ReviewSession
  local session = {
    version = 2,
    id = generate_id(),
    name = opts.name or default_name(base_ref, compare_ref),
    project_root = project_root,
    base_ref = base_ref,
    compare_ref = compare_ref,
    created_at = os.time(),
    updated_at = os.time(),
    diff_files = diff_files,
    comments = {},
    reviewed_files = {},
  }

  -- Parse hunks for all files
  parse_all_hunks(session)

  -- Save and activate
  store.save(session)
  state.set_active(session)

  return session, nil
end

--- Resume an existing session.
---@param session_id string|nil  If nil, the project_root is used to find sessions
---@return ReviewSession|nil, string|nil error
M.resume = function(session_id)
  local project_root = git.get_git_root()
  if not project_root then
    return nil, "Not in a git repository"
  end

  if session_id then
    local session = store.load(project_root, session_id)
    if not session then
      return nil, "Session not found: " .. session_id
    end
    -- Re-parse hunks (files may have changed)
    parse_all_hunks(session)
    store.save(session)
    state.set_active(session)
    return session, nil
  end

  -- No session_id, return nil to signal that caller should show picker
  return nil, nil
end

--- Pause the active session (close UI, keep data).
---@return boolean
M.pause = function()
  if not state.is_active() then
    return false
  end
  state.force_save()
  state.clear_active()
  return true
end

--- Submit the active session (generate output, optionally delete).
---@return string|nil output, string|nil error
M.submit = function()
  local session = state.get_active()
  if not session then
    return nil, "No active session"
  end

  local format = require("reviewthem.format")
  local output = format.to_markdown(session)

  -- Copy to clipboard
  vim.fn.setreg("+", output)
  vim.fn.setreg('"', output)

  -- Delete session after export
  store.delete(session.project_root, session.id)
  state.clear_active()

  return output, nil
end

--- Abort (delete) the active session.
---@return boolean
M.abort = function()
  local session = state.get_active()
  if not session then
    return false
  end
  store.delete(session.project_root, session.id)
  state.clear_active()
  return true
end

--- Delete a session by id (not necessarily the active one).
---@param session_id string
---@return boolean
M.delete_session = function(session_id)
  local project_root = git.get_git_root()
  if not project_root then
    return false
  end
  -- If it's the active session, deactivate first
  local active = state.get_active()
  if active and active.id == session_id then
    state.clear_active()
  end
  return store.delete(project_root, session_id)
end

--- List all sessions for the current project.
---@return ReviewSession[]
M.list = function()
  local project_root = git.get_git_root()
  if not project_root then
    return {}
  end
  return store.list(project_root)
end

--- Get the active session.
---@return ReviewSession|nil
M.get_active = function()
  return state.get_active()
end

return M
