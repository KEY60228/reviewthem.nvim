local M = {}

---@type ReviewSession|nil
local active_session = nil

---@type number|nil Timer handle for debounced save
local save_timer = nil

---@param session ReviewSession
M.set_active = function(session)
  active_session = session
end

---@return ReviewSession|nil
M.get_active = function()
  return active_session
end

M.clear_active = function()
  if save_timer then
    vim.fn.timer_stop(save_timer)
    save_timer = nil
  end
  active_session = nil
end

---@return boolean
M.is_active = function()
  return active_session ~= nil
end

--- Ensure a session is active, notify error if not.
---@return boolean
M.ensure_active = function()
  if not M.is_active() then
    vim.notify("No review session is active. Use :ReviewThemStart to begin.", vim.log.levels.ERROR)
    return false
  end
  return true
end

--- Schedule a debounced save of the active session.
local function schedule_save()
  local config = require("reviewthem.config").get()
  if not config.auto_save then
    return
  end
  if not active_session then
    return
  end

  if save_timer then
    vim.fn.timer_stop(save_timer)
  end

  save_timer = vim.fn.timer_start(500, function()
    save_timer = nil
    if active_session then
      local store = require("reviewthem.session.store")
      store.save(active_session)
    end
  end)
end

--- Add a comment to the active session.
---@param comment Comment
M.add_comment = function(comment)
  if not active_session then
    return
  end
  table.insert(active_session.comments, comment)
  schedule_save()
end

--- Remove a comment by id.
---@param comment_id string
---@return boolean
M.remove_comment = function(comment_id)
  if not active_session then
    return false
  end
  for i, c in ipairs(active_session.comments) do
    if c.id == comment_id then
      table.remove(active_session.comments, i)
      schedule_save()
      return true
    end
  end
  return false
end

--- Update a comment's text by id.
---@param comment_id string
---@param new_text string
---@return boolean
M.update_comment = function(comment_id, new_text)
  if not active_session then
    return false
  end
  for _, c in ipairs(active_session.comments) do
    if c.id == comment_id then
      c.text = new_text
      c.updated_at = os.time()
      schedule_save()
      return true
    end
  end
  return false
end

--- Get all comments for a specific file.
---@param file_path string
---@return Comment[]
M.get_file_comments = function(file_path)
  if not active_session then
    return {}
  end
  local result = {}
  for _, c in ipairs(active_session.comments) do
    if c.file == file_path then
      table.insert(result, c)
    end
  end
  return result
end

--- Toggle reviewed status for a file.
---@param file_path string
---@return boolean new status
M.toggle_reviewed = function(file_path)
  if not active_session then
    return false
  end
  local current = active_session.reviewed_files[file_path] or false
  active_session.reviewed_files[file_path] = not current
  schedule_save()
  return not current
end

--- Mark a file as reviewed.
---@param file_path string
M.mark_reviewed = function(file_path)
  if not active_session then
    return
  end
  active_session.reviewed_files[file_path] = true
  schedule_save()
end

--- Check if a file is reviewed.
---@param file_path string
---@return boolean
M.is_reviewed = function(file_path)
  if not active_session then
    return false
  end
  return active_session.reviewed_files[file_path] == true
end

--- Get review progress.
---@return number reviewed, number total
M.get_progress = function()
  if not active_session then
    return 0, 0
  end
  local total = #active_session.diff_files
  local reviewed = 0
  for _, file in ipairs(active_session.diff_files) do
    if active_session.reviewed_files[file.path] then
      reviewed = reviewed + 1
    end
  end
  return reviewed, total
end

--- Force save the active session immediately.
M.force_save = function()
  if save_timer then
    vim.fn.timer_stop(save_timer)
    save_timer = nil
  end
  if active_session then
    local store = require("reviewthem.session.store")
    store.save(active_session)
  end
end

return M
