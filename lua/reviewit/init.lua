local M = {}

M.setup = function(opts)
  local config = require("reviewit.config")
  config.setup(opts)
end

return M
