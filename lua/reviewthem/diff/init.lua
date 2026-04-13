local renderer = require("reviewthem.diff.renderer")
local split = require("reviewthem.diff.split")

local M = {}

--- Initialize highlights.
M.setup = function()
  renderer.setup_highlights()
end

--- Open the diff view for a session (shows first file).
---@param session ReviewSession
---@param old_winnr number
---@param new_winnr number
M.open = function(session, old_winnr, new_winnr)
  renderer.setup_highlights()
  if #session.diff_files > 0 then
    split.render_file(session, session.diff_files[1], old_winnr, new_winnr)
  end
end

--- Refresh decorations (after comment/review changes).
---@param session ReviewSession
M.refresh = function(session)
  split.refresh_decorations(session)
end

--- Get cursor context.
---@return table|nil
M.get_cursor_context = function()
  return split.get_cursor_context()
end

--- Show a specific file.
---@param session ReviewSession
---@param file DiffFile
---@param old_winnr number
---@param new_winnr number
M.show_file = function(session, file, old_winnr, new_winnr)
  split.render_file(session, file, old_winnr, new_winnr)
end

--- Jump to a specific line in the split view.
---@param side "old"|"new"
---@param lineno number
M.jump_to_line = function(side, lineno)
  split.jump_to_line(side, lineno)
end

--- Get the current file being viewed.
---@return string|nil
M.get_current_file = function()
  return split.get_current_file()
end

--- Close all diff views.
M.close = function()
  split.close()
end

return M
