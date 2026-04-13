local M = {}

--- Format a session as Markdown.
---@param session ReviewSession
---@return string
M.to_markdown = function(session)
  return require("reviewthem.format.markdown").format(session)
end

return M
