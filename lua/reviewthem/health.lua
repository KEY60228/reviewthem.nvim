local M = {}

M.check = function()
  vim.health.start("reviewthem.nvim")

  -- Neovim version
  if vim.fn.has("nvim-0.10.0") == 1 then
    vim.health.ok("Neovim >= 0.10.0")
  else
    vim.health.error("Neovim >= 0.10.0 required")
  end

  -- Git
  local git_version = vim.fn.system("git --version")
  if vim.v.shell_error == 0 then
    vim.health.ok("git: " .. vim.trim(git_version))
  else
    vim.health.error("git not found")
  end

  -- Git repository
  local git = require("reviewthem.git")
  local root = git.get_git_root()
  if root then
    vim.health.ok("Git repository: " .. root)
  else
    vim.health.warn("Not in a git repository")
  end

  -- Session storage
  local store_dir = vim.fn.stdpath("data") .. "/reviewthem/sessions"
  if vim.fn.isdirectory(store_dir) == 1 then
    vim.health.ok("Session storage: " .. store_dir)
  else
    vim.health.info("Session storage will be created at: " .. store_dir)
  end

  -- Clipboard
  if vim.fn.has("clipboard") == 1 then
    vim.health.ok("Clipboard support available")
  else
    vim.health.warn("Clipboard support not detected (review output may not copy correctly)")
  end

  -- Configuration
  local config = require("reviewthem.config").get()
  if config and config.keymaps then
    vim.health.ok("Configuration loaded")
  else
    vim.health.warn("Configuration not loaded (call require('reviewthem').setup())")
  end
end

return M
