-- Setup commands and keymaps after plugin has loaded
if vim.g.loaded_reviewthem then
  local commands = require("reviewthem.commands")
  local keymaps = require("reviewthem.keymaps")

  commands.setup()
  keymaps.setup()
end

