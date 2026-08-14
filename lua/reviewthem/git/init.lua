local M = {}

--- Run a git command (argv list) and return the completed result.
--- Runs inside the project root when one is known, so results do not
--- depend on Neovim's current working directory.
---@param args string[] git subcommand and arguments
---@param root string|nil project root to run in
---@return vim.SystemCompleted
local function run_git(args, root)
  local cmd = { "git" }
  if root then
    table.insert(cmd, "-C")
    table.insert(cmd, root)
  end
  vim.list_extend(cmd, args)
  return vim.system(cmd, { text = false }):wait()
end

---@return string|nil
M.get_git_root = function()
  local result = run_git({ "rev-parse", "--show-toplevel" })
  if result.code ~= 0 then
    return nil
  end
  return vim.trim(result.stdout or "")
end

---@param ref string
---@return boolean
M.is_valid_ref = function(ref)
  local result = run_git({ "rev-parse", "--verify", "--quiet", ref }, M.get_git_root())
  return result.code == 0
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
---@param other string|nil  The other side of the comparison (defaults to "HEAD")
---@param root string|nil
---@return string|nil
M.get_merge_base = function(ref, other, root)
  local result = run_git({ "merge-base", other or "HEAD", ref }, root or M.get_git_root())
  if result.code == 0 and result.stdout and result.stdout ~= "" then
    return vim.trim(result.stdout)
  end
  return nil
end

--- Resolve the git ref whose content matches one side of the rendered diff.
--- Must stay in sync with `get_diff_files` / `get_file_diff`, which decide what
--- the diff actually compares:
---   * no refs         old = HEAD (the index in an unborn repo), new = the working tree
---   * base_ref only   old = merge-base(HEAD, base_ref), new = the working tree
---   * base...compare  old = merge-base(base_ref, compare_ref), new = compare_ref
---@param base_ref string|nil
---@param compare_ref string|nil
---@param side "old"|"new"
---@return string|nil ref  nil when the side shows the working tree
M.resolve_side_ref = function(base_ref, compare_ref, side)
  local has_base = base_ref ~= nil and base_ref ~= ""
  local has_compare = compare_ref ~= nil and compare_ref ~= ""

  if side == "new" then
    if has_compare then
      return compare_ref
    end
    return nil
  end

  if not has_compare then
    if not has_base then
      -- `git diff HEAD` compares HEAD with the working tree; repositories
      -- without any commit fall back to the index diff
      if M.is_valid_ref("HEAD") then
        return "HEAD"
      end
      return ":0"
    end
    return M.get_merge_base(base_ref) or base_ref
  end
  return M.get_merge_base(compare_ref, base_ref) or base_ref
end

--- Parse NUL-separated `git diff --name-status -z` output.
--- Regular entries are `STATUS NUL PATH NUL`; renames/copies are
--- `Rnnn NUL SRC NUL DST NUL`. Paths are raw bytes (no quoting), so
--- non-ASCII file names survive regardless of core.quotepath.
---@param output string
---@return DiffFile[]
local function parse_name_status_z(output)
  local files = {}
  local parts = vim.split(output or "", "\0", { plain = true })
  local i = 1
  while i <= #parts do
    local status = parts[i]
    if status == nil or status == "" then
      break
    end
    local kind = status:sub(1, 1)
    if kind == "R" or kind == "C" then
      local src = parts[i + 1]
      local dst = parts[i + 2]
      if src and dst and dst ~= "" then
        table.insert(files, { path = dst, status = kind, old_path = src, hunks = {} })
      end
      i = i + 3
    else
      local path = parts[i + 1]
      if path and path ~= "" then
        table.insert(files, { path = path, status = kind, hunks = {} })
      end
      i = i + 2
    end
  end
  return files
end

--- Get list of changed files between two refs.
--- With no refs: HEAD vs working tree (staged + unstaged) plus untracked files.
--- With base only: merge-base(HEAD, base) vs working tree plus untracked files.
--- With both: base...compare (merge-base three-dot diff).
---@param base_ref string|nil
---@param compare_ref string|nil
---@return DiffFile[]
M.get_diff_files = function(base_ref, compare_ref)
  local root = M.get_git_root()
  if not root then
    return {}
  end

  local files = {}

  if compare_ref == nil or compare_ref == "" then
    local result
    if base_ref == nil or base_ref == "" then
      result = run_git({ "diff", "--name-status", "-z", "HEAD" }, root)
      if result.code ~= 0 then
        -- Repository without any commit yet: fall back to index diff
        result = run_git({ "diff", "--name-status", "-z" }, root)
      end
    else
      local merge_base = M.get_merge_base(base_ref, nil, root)
      result = run_git({ "diff", "--name-status", "-z", merge_base or base_ref }, root)
    end
    if result.code == 0 then
      files = parse_name_status_z(result.stdout)
    end
    -- Untracked files
    local untracked = run_git({ "ls-files", "--others", "--exclude-standard", "-z" }, root)
    if untracked.code == 0 then
      for _, file in ipairs(vim.split(untracked.stdout or "", "\0", { plain = true })) do
        if file ~= "" then
          table.insert(files, { path = file, status = "A", untracked = true, hunks = {} })
        end
      end
    end
  else
    local result = run_git(
      { "diff", "--name-status", "-z", base_ref .. "..." .. compare_ref },
      root
    )
    if result.code == 0 then
      files = parse_name_status_z(result.stdout)
    end
  end

  return files
end

---@param output string
---@return string[]
local function to_lines(output)
  local lines = vim.split(output or "", "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

--- Get unified diff output for a specific file.
---@param base_ref string|nil
---@param compare_ref string|nil
---@param file DiffFile|string  DiffFile entry (or bare path for compatibility)
---@param context_lines number|nil
---@return string[]
M.get_file_diff = function(base_ref, compare_ref, file, context_lines)
  context_lines = context_lines or 3
  if type(file) == "string" then
    file = { path = file }
  end

  local root = M.get_git_root()
  if not root then
    return {}
  end

  -- Untracked files never appear in `git diff`; show them as a full addition.
  -- --no-index exits 1 when the file has content, so ignore the exit code.
  if file.untracked then
    local result = run_git(
      { "diff", "--no-index", "-U" .. context_lines, "/dev/null", root .. "/" .. file.path },
      root
    )
    return to_lines(result.stdout)
  end

  -- For renames/copies include both paths so git can pair them up.
  local pathspec = { file.path }
  if file.old_path then
    table.insert(pathspec, file.old_path)
  end

  local args = { "diff", "-U" .. context_lines }
  if compare_ref == nil or compare_ref == "" then
    if not (base_ref == nil or base_ref == "") then
      local merge_base = M.get_merge_base(base_ref, nil, root)
      table.insert(args, merge_base or base_ref)
    else
      local head_ok = run_git({ "rev-parse", "--verify", "--quiet", "HEAD" }, root)
      if head_ok.code == 0 then
        table.insert(args, "HEAD")
      end
    end
  else
    table.insert(args, base_ref .. "..." .. compare_ref)
  end
  table.insert(args, "--")
  vim.list_extend(args, pathspec)

  local result = run_git(args, root)
  if result.code ~= 0 then
    return {}
  end
  return to_lines(result.stdout)
end

--- Get full file content at a specific ref.
---@param ref string|nil
---@param file_path string
---@return string[]|nil
M.get_file_content = function(ref, file_path)
  local root = M.get_git_root()
  if not root then
    return nil
  end

  if ref == nil or ref == "" then
    -- Working tree version
    local f = io.open(root .. "/" .. file_path, "r")
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

  local result = run_git({ "show", ref .. ":" .. file_path }, root)
  if result.code ~= 0 then
    return nil
  end
  return to_lines(result.stdout)
end

--- Get git refs for completion.
---@return string[]
M.get_refs = function()
  local root = M.get_git_root()
  local refs = {}
  -- Branches (including remote-tracking)
  local branches = run_git({ "branch", "-a", "--format=%(refname:short)" }, root)
  if branches.code == 0 then
    for _, b in ipairs(to_lines(branches.stdout)) do
      if b ~= "" then
        table.insert(refs, b)
      end
    end
  end
  -- Tags
  local tags = run_git({ "tag" }, root)
  if tags.code == 0 then
    for _, t in ipairs(to_lines(tags.stdout)) do
      if t ~= "" then
        table.insert(refs, t)
      end
    end
  end
  return refs
end

return M
