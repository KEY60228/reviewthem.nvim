local M = {}

M.get_diff_files = function(base_ref, compare_ref)
  local files = {}

  -- Handle different types of references
  if compare_ref == nil or compare_ref == "" then
    -- All uncommitted changes (both staged and unstaged) against base_ref
    local cmd
    if base_ref == nil or base_ref == "" then
      -- No base ref means compare index with working directory
      cmd = "git diff --name-status"
    else
      cmd = string.format("git diff --name-status %s", base_ref)
    end
    local result = vim.fn.systemlist(cmd)

    -- Get tracked file changes
    for _, line in ipairs(result) do
      local status, file = line:match("^(%S+)%s+(.+)$")
      if status and file then
        table.insert(files, {
          status = status,
          file = file,
        })
      end
    end

    -- Get untracked files
    local untracked_cmd = "git ls-files --others --exclude-standard"
    local untracked_result = vim.fn.systemlist(untracked_cmd)
    for _, file in ipairs(untracked_result) do
      if file ~= "" then
        table.insert(files, {
          status = "A", -- Show untracked files as added
          file = file,
        })
      end
    end
  else
    -- Normal branch/commit comparison
    local cmd = string.format("git diff --name-status %s...%s", base_ref, compare_ref)
    local result = vim.fn.systemlist(cmd)

    for _, line in ipairs(result) do
      local status, file = line:match("^(%S+)%s+(.+)$")
      if status and file then
        table.insert(files, {
          status = status,
          file = file,
        })
      end
    end
  end

  return files
end

M.validate_references = function(base_ref, compare_ref)
  -- If both are empty, that's valid (comparing working directory with index)
  if (base_ref == nil or base_ref == "") and (compare_ref == nil or compare_ref == "") then
    return true, nil
  end

  if compare_ref == nil or compare_ref == "" then
    -- Comparing with working directory
    local valid = M.is_valid_ref(base_ref)
    if not valid then
      return false, base_ref .. " is not a valid reference"
    end
    return true, nil
  end

  -- Validate both references
  local base_valid = M.is_valid_ref(base_ref)
  if not base_valid then
    return false, string.format("Base reference '%s' is not valid", base_ref)
  end

  local compare_valid = M.is_valid_ref(compare_ref)
  if not compare_valid then
    return false, string.format("Compare reference '%s' is not valid", compare_ref)
  end

  return true, nil
end

-- Check if a reference (branch, tag, or commit) is valid
M.is_valid_ref = function(ref)
  local cmd = string.format("git rev-parse --verify %s", vim.fn.shellescape(ref))
  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

M.get_git_root = function()
  local result = vim.fn.system("git rev-parse --show-toplevel")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

M.get_relative_path = function(absolute_path)
  -- Handle diffview URIs
  if absolute_path:match("^diffview://") then
    -- Extract the actual file path from diffview URI
    -- Format: diffview:///path/to/repo/.git/commit_hash/relative/path/to/file
    local git_root = M.get_git_root()
    if git_root then
      -- Find the .git directory position and extract the path after it
      local pattern = vim.pesc(git_root) .. "/.git/[^/]+/"
      local relative = absolute_path:gsub("^diffview://", ""):gsub(pattern, "")
      return relative
    end
  end

  local git_root = M.get_git_root()
  if not git_root then
    return absolute_path
  end

  -- Get the relative path from git root
  local cmd = string.format("git -C %s ls-files --full-name %s", git_root, vim.fn.shellescape(absolute_path))
  local result = vim.fn.system(cmd)

  if vim.v.shell_error == 0 and result ~= "" then
    return vim.trim(result)
  end

  -- If the file is not tracked, calculate relative path manually
  local relative = absolute_path:gsub("^" .. vim.pesc(git_root) .. "/", "")
  return relative
end

return M
