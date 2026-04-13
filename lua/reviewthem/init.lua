local M = {}

---@param opts table|nil
M.setup = function(opts)
  local config = require("reviewthem.config")
  config.setup(opts)

  local commands = require("reviewthem.commands")
  commands.register()
end

return M
