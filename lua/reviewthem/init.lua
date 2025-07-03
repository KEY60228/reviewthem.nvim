local M = {}

M.setup = function(opts)
  local config = require("reviewthem.config")
  config.setup(opts)
end

return M
