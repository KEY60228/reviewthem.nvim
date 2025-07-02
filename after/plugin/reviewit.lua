-- Setup commands and keymaps after plugin has loaded
if vim.g.loaded_reviewit then
  local commands = require("reviewit.commands")
  local keymaps = require("reviewit.keymaps")

  commands.setup()
  keymaps.setup()
end

