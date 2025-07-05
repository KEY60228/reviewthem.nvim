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
    -- When no compare_ref is given, show all changes including untracked files
    -- by not specifying any refs (this shows working tree changes)
    if base_ref == "HEAD" then
      -- Show all working tree changes including untracked files
      cmd = "DiffviewOpen"
    else
      -- Compare against a specific ref
      cmd = string.format("DiffviewOpen %s", base_ref)
    end
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

