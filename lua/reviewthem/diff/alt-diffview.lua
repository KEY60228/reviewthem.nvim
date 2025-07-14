local M = {}

-- Check if alt-diffview is available
M.is_available = function()
  local ok, _ = pcall(require, "alt-diffview")
  return ok
end

-- Start alt-diffview session
M.start = function(base_ref, compare_ref)
  if not M.is_available() then
    vim.notify("reviewthem.nvim: alt-diffview.nvim not found. Please install KEY60228/alt-diffview.nvim", vim.log.levels.ERROR)
    return false
  end

  local cmd
  if compare_ref == nil or compare_ref == "" then
    -- Compare with working directory (all uncommitted changes)
    -- alt-diffview handles untracked files properly when only base ref is specified
    if base_ref == nil or base_ref == "" then
      -- Show all working tree changes including untracked files
      -- alt-diffview shows untracked files when no refs are specified
      cmd = "AltDiffviewOpen"
    else
      -- Use --merge-base option to show changes from merge base
      cmd = string.format("AltDiffviewOpen %s --merge-base", base_ref)
    end
  else
    -- Normal comparison
    cmd = string.format("AltDiffviewOpen %s...%s", base_ref, compare_ref)
  end

  vim.cmd(cmd)
  return true
end

-- Close alt-diffview session
M.close = function()
  pcall(vim.cmd, "AltDiffviewClose")
end

return M