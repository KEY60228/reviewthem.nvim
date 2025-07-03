local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error

M.check = function()
  start("reviewthem.nvim")

  -- Check Neovim version
  if vim.fn.has("nvim-0.7.0") == 1 then
    ok("Neovim version is 0.7.0 or higher")
  else
    error("reviewthem.nvim requires Neovim 0.7.0 or higher")
  end

  -- Check Git
  local git_version = vim.fn.system("git --version")
  if vim.v.shell_error == 0 then
    ok("Git is installed: " .. vim.trim(git_version))
  else
    error("Git is not installed or not in PATH")
  end

  -- Check if in a Git repository
  vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
  if vim.v.shell_error == 0 then
    ok("Current directory is inside a Git repository")
  else
    warn("Not in a Git repository. reviewthem.nvim requires a Git repository to function")
  end

  -- Check required dependencies
  start("Dependencies")

  -- Check plenary.nvim (required for some features)
  local has_plenary = pcall(require, "plenary")
  if has_plenary then
    ok("plenary.nvim is installed")
  else
    warn("plenary.nvim is not installed (optional, but recommended)")
  end

  -- Check diff tools
  start("Diff tools")

  -- Check diffview.nvim
  local has_diffview = pcall(require, "diffview")
  if has_diffview then
    ok("diffview.nvim is installed")
  else
    error("diffview.nvim is not installed (currently required - more diff tools coming soon!)")
  end

  -- Check UI providers
  start("UI providers")

  -- Check telescope.nvim
  local has_telescope = pcall(require, "telescope")
  if has_telescope then
    ok("telescope.nvim is installed (optional UI provider)")
  else
    warn("telescope.nvim is not installed (optional, builtin UI will be used)")
  end

  -- Check configuration
  start("Configuration")

  local config = require("reviewthem.config")
  local opts = config.get()

  if opts then
    ok("Configuration loaded successfully")

    -- Check UI setting
    if opts.ui == "telescope" and not has_telescope then
      warn("UI is set to 'telescope' but telescope.nvim is not installed. Falling back to builtin UI")
    else
      ok(string.format("UI provider: %s", opts.ui))
    end

    -- Check diff tool setting
    if opts.diff_tool == "diffview" and not has_diffview then
      error("Diff tool is set to 'diffview' but diffview.nvim is not installed")
    else
      ok(string.format("Diff tool: %s", opts.diff_tool))
    end
  else
    error("Failed to load configuration")
  end

  -- Check clipboard
  start("Clipboard")
  if vim.fn.has("clipboard") == 1 then
    ok("Clipboard support is available")
  else
    warn("No clipboard support. Submit to clipboard will not work")
  end
end

return M

