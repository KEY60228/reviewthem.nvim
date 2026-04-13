local M = {}

---@return string|nil
M.get_git_root = function()
  local result = vim.fn.system("git rev-parse --show-toplevel")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

---@param ref string
---@return boolean
M.is_valid_ref = function(ref)
  local cmd = string.format("git rev-parse --verify %s", vim.fn.shellescape(ref))
  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

---@param base_ref string|nil
---@param compare_ref string|nil
---@return boolean, string|nil
M.validate_refs = function(base_ref, compare_ref)
  if (base_ref == nil or base_ref == "") and (compare_ref == nil or compare_ref == "") then
    return true, nil
  end

  if compare_ref == nil or compare_ref == "" then
    if not M.is_valid_ref(base_ref) then
      return false, string.format("'%s' is not a valid reference", base_ref)
    end
    return true, nil
  end

  if base_ref == nil or base_ref == "" then
    return false, "Base reference is required when compare reference is specified"
  end
  if not M.is_valid_ref(base_ref) then
    return false, string.format("Base reference '%s' is not valid", base_ref)
  end
  if not M.is_valid_ref(compare_ref) then
    return false, string.format("Compare reference '%s' is not valid", compare_ref)
  end
  return true, nil
end

---@param ref string
---@return string|nil
M.get_merge_base = function(ref)
  local cmd = string.format("git merge-base HEAD %s", vim.fn.shellescape(ref))
  local result = vim.fn.system(cmd)
  if vim.v.shell_error == 0 and result ~= "" then
    return vim.trim(result)
  end
  return nil
end

--- Get list of changed files between two refs.
---@param base_ref string|nil
---@param compare_ref string|nil
---@return DiffFile[]
M.get_diff_files = function(base_ref, compare_ref)
  local files = {}

  if compare_ref == nil or compare_ref == "" then
    local cmd
    if base_ref == nil or base_ref == "" then
      cmd = "git diff --name-status"
    else
      local merge_base = M.get_merge_base(base_ref)
      cmd = string.format("git diff --name-status %s", vim.fn.shellescape(merge_base or base_ref))
    end
    local result = vim.fn.systemlist(cmd)
    for _, line in ipairs(result) do
      local status, file = line:match("^(%S+)%s+(.+)$")
      if status and file then
        table.insert(files, { path = file, status = status, hunks = {} })
      end
    end
    -- Untracked files
    local untracked = vim.fn.systemlist("git ls-files --others --exclude-standard")
    for _, file in ipairs(untracked) do
      if file ~= "" then
        table.insert(files, { path = file, status = "A", hunks = {} })
      end
    end
  else
    local cmd = string.format("git diff --name-status %s...%s", vim.fn.shellescape(base_ref), vim.fn.shellescape(compare_ref))
    local result = vim.fn.systemlist(cmd)
    for _, line in ipairs(result) do
      local status, file = line:match("^(%S+)%s+(.+)$")
      if status and file then
        table.insert(files, { path = file, status = status, hunks = {} })
      end
    end
  end

  return files
end

--- Get unified diff output for a specific file.
---@param base_ref string|nil
---@param compare_ref string|nil
---@param file_path string
---@param context_lines number|nil
---@return string[]
M.get_file_diff = function(base_ref, compare_ref, file_path, context_lines)
  context_lines = context_lines or 3
  local cmd

  if compare_ref == nil or compare_ref == "" then
    if base_ref == nil or base_ref == "" then
      cmd = string.format("git diff -U%d -- %s", context_lines, vim.fn.shellescape(file_path))
    else
      local merge_base = M.get_merge_base(base_ref)
      cmd = string.format("git diff -U%d %s -- %s", context_lines, vim.fn.shellescape(merge_base or base_ref), vim.fn.shellescape(file_path))
    end
  else
    cmd = string.format("git diff -U%d %s...%s -- %s", context_lines, vim.fn.shellescape(base_ref), vim.fn.shellescape(compare_ref), vim.fn.shellescape(file_path))
  end

  return vim.fn.systemlist(cmd)
end

--- Get full file content at a specific ref.
---@param ref string|nil
---@param file_path string
---@return string[]|nil
M.get_file_content = function(ref, file_path)
  if ref == nil or ref == "" then
    -- Working tree version
    local git_root = M.get_git_root()
    if not git_root then
      return nil
    end
    local full_path = git_root .. "/" .. file_path
    local f = io.open(full_path, "r")
    if not f then
      return nil
    end
    local content = f:read("*a")
    f:close()
    local lines = {}
    for line in (content .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(lines, line)
    end
    -- Remove trailing empty line if the file doesn't end with newline
    if #lines > 0 and lines[#lines] == "" then
      table.remove(lines)
    end
    return lines
  end

  local cmd = string.format("git show %s:%s", vim.fn.shellescape(ref), vim.fn.shellescape(file_path))
  local result = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return result
end

--- Get git refs for completion.
---@return string[]
M.get_refs = function()
  local refs = {}
  -- Branches
  local branches = vim.fn.systemlist("git branch --format='%(refname:short)'")
  for _, b in ipairs(branches) do
    if b ~= "" then
      table.insert(refs, b)
    end
  end
  -- Tags
  local tags = vim.fn.systemlist("git tag")
  for _, t in ipairs(tags) do
    if t ~= "" then
      table.insert(refs, t)
    end
  end
  return refs
end

return M
