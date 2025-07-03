local M = {}

-- Check if diffview is available
M.is_available = function()
  local ok, _ = pcall(require, "diffview")
  return ok
end

-- Start diffview session
M.start = function(base_ref, compare_ref)
  if not M.is_available() then
    vim.notify("reviewthem.nvim: diffview.nvim not found. Please install sindrets/diffview.nvim (currently required - more diff tools coming soon!)", vim.log.levels.ERROR)
    return false
  end

  local cmd
  if compare_ref == nil or compare_ref == "" then
    -- Compare with working directory (all uncommitted changes)
    cmd = string.format("DiffviewOpen %s", base_ref)
  else
    -- Normal comparison
    cmd = string.format("DiffviewOpen %s...%s", base_ref, compare_ref)
  end

  vim.cmd(cmd)
  return true
end

-- Close diffview session
M.close = function()
  pcall(vim.cmd, "DiffviewClose")
end

return M

