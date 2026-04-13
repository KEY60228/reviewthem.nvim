local M = {}

local ns = vim.api.nvim_create_namespace("reviewthem_file_tree")

---@class FileTreeState
---@field bufnr number|nil
---@field winnr number|nil
---@field entries FileTreeEntry[]
---@field collapsed table<string, boolean>  dir_path -> collapsed

---@class FileTreeEntry
---@field type "dir"|"file"
---@field path string
---@field display_name string
---@field depth number
---@field status string|nil
---@field file_path string|nil  Full relative path for files

---@type FileTreeState
local tree_state = {
  bufnr = nil,
  winnr = nil,
  entries = {},
  collapsed = {},
}

--- Build directory tree from flat file list.
---@param diff_files DiffFile[]
---@return table tree  Nested directory structure
local function build_dir_tree(diff_files)
  local root = { children = {}, files = {} }

  for _, file in ipairs(diff_files) do
    local parts = {}
    for part in file.path:gmatch("[^/]+") do
      table.insert(parts, part)
    end

    local current = root
    for i = 1, #parts - 1 do
      local dir_name = parts[i]
      if not current.children[dir_name] then
        current.children[dir_name] = { children = {}, files = {} }
      end
      current = current.children[dir_name]
    end

    table.insert(current.files, {
      name = parts[#parts],
      path = file.path,
      status = file.status,
    })
  end

  return root
end

--- Flatten tree into display entries.
---@param tree table
---@param depth number
---@param prefix string
---@param entries FileTreeEntry[]
---@param collapsed table<string, boolean>
local function flatten_tree(tree, depth, prefix, entries, collapsed)
  -- Sort directories
  local dir_names = {}
  for name in pairs(tree.children) do
    table.insert(dir_names, name)
  end
  table.sort(dir_names)

  -- Sort files
  local files = tree.files or {}
  table.sort(files, function(a, b)
    return a.name < b.name
  end)

  for _, dir_name in ipairs(dir_names) do
    local dir_path = prefix .. dir_name .. "/"
    local is_collapsed = collapsed[dir_path] or false

    table.insert(entries, {
      type = "dir",
      path = dir_path,
      display_name = dir_name,
      depth = depth,
    })

    if not is_collapsed then
      flatten_tree(tree.children[dir_name], depth + 1, dir_path, entries, collapsed)
    end
  end

  for _, file in ipairs(files) do
    table.insert(entries, {
      type = "file",
      path = file.path,
      display_name = file.name,
      depth = depth,
      status = file.status,
      file_path = file.path,
    })
  end
end

--- Setup highlight groups for file tree.
local function setup_highlights()
  local groups = {
    ReviewThemTreeDir = { default = true, fg = "#7aa2f7", bold = true },
    ReviewThemTreeFile = { default = true, fg = "#c0caf5" },
    ReviewThemTreeReviewed = { default = true, fg = "#9ece6a" },
    ReviewThemTreeUnreviewed = { default = true, fg = "#565f89" },
    ReviewThemTreeAdded = { default = true, fg = "#9ece6a" },
    ReviewThemTreeModified = { default = true, fg = "#e0af68" },
    ReviewThemTreeDeleted = { default = true, fg = "#f7768e" },
    ReviewThemTreeProgress = { default = true, fg = "#bb9af7", italic = true },
    ReviewThemTreeComment = { default = true, fg = "#e0af68" },
  }
  for name, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

--- Render the file tree buffer.
---@param session ReviewSession
local function render(session)
  if not tree_state.bufnr or not vim.api.nvim_buf_is_valid(tree_state.bufnr) then
    return
  end

  local tree = build_dir_tree(session.diff_files)
  local entries = {}
  flatten_tree(tree, 0, "", entries, tree_state.collapsed)
  tree_state.entries = entries

  -- Count comments per file
  local comment_counts = {}
  for _, c in ipairs(session.comments) do
    comment_counts[c.file] = (comment_counts[c.file] or 0) + 1
  end

  -- Build display lines
  local lines = {}
  local highlights = {} -- {line_idx, hl_group, col_start, col_end}

  for _, entry in ipairs(entries) do
    local indent = string.rep("  ", entry.depth)
    local line

    if entry.type == "dir" then
      local is_collapsed = tree_state.collapsed[entry.path]
      local icon = is_collapsed and "▸ " or "▾ "
      line = indent .. icon .. entry.display_name .. "/"
      table.insert(highlights, { #lines, "ReviewThemTreeDir", #indent, #line })
    else
      local reviewed = session.reviewed_files[entry.path] or false
      local status_icon = ({
        A = "+",
        M = "~",
        D = "-",
        R = "→",
      })[entry.status] or "?"

      local check = reviewed and "✓" or "□"
      local check_hl = reviewed and "ReviewThemTreeReviewed" or "ReviewThemTreeUnreviewed"
      local status_hl = ({
        A = "ReviewThemTreeAdded",
        M = "ReviewThemTreeModified",
        D = "ReviewThemTreeDeleted",
      })[entry.status] or "ReviewThemTreeFile"

      local comment_suffix = ""
      local count = comment_counts[entry.path]
      if count and count > 0 then
        comment_suffix = string.format(" 💬%d", count)
      end

      line = indent .. check .. " " .. status_icon .. " " .. entry.display_name .. comment_suffix

      local col = #indent
      table.insert(highlights, { #lines, check_hl, col, col + #check })
      col = col + #check + 1
      table.insert(highlights, { #lines, status_hl, col, col + #status_icon })
      col = col + #status_icon + 1
      table.insert(highlights, { #lines, "ReviewThemTreeFile", col, col + #entry.display_name })
      if comment_suffix ~= "" then
        table.insert(highlights, { #lines, "ReviewThemTreeComment", col + #entry.display_name, #line })
      end
    end

    table.insert(lines, line)
  end

  -- Progress line
  local reviewed_count = 0
  local total = #session.diff_files
  for _, file in ipairs(session.diff_files) do
    if session.reviewed_files[file.path] then
      reviewed_count = reviewed_count + 1
    end
  end
  table.insert(lines, "")
  table.insert(lines, string.format("── Progress: %d/%d ──", reviewed_count, total))
  table.insert(highlights, { #lines - 1, "ReviewThemTreeProgress", 0, -1 })
  table.insert(lines, string.format("── Comments: %d ──", #session.comments))
  table.insert(highlights, { #lines - 1, "ReviewThemTreeProgress", 0, -1 })

  -- Set buffer content
  vim.bo[tree_state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(tree_state.bufnr, 0, -1, false, lines)
  vim.bo[tree_state.bufnr].modifiable = false

  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(tree_state.bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, tree_state.bufnr, ns, hl[2], hl[1], hl[3], hl[4])
  end
end

--- Open the file tree sidebar.
---@param session ReviewSession
---@param on_select fun(file_path: string)  Callback when file is selected
---@param on_toggle_reviewed fun(file_path: string)  Callback when review status is toggled
---@return number winnr
M.open = function(session, on_select, on_toggle_reviewed)
  setup_highlights()

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "reviewthem://tree")
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "reviewthem-tree"

  -- Create sidebar window
  vim.cmd("topleft vsplit")
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)

  local config = require("reviewthem.config").get()
  vim.api.nvim_win_set_width(winnr, config.file_tree_width)

  vim.wo[winnr].number = false
  vim.wo[winnr].relativenumber = false
  vim.wo[winnr].signcolumn = "no"
  vim.wo[winnr].winfixwidth = true
  vim.wo[winnr].wrap = false
  vim.wo[winnr].cursorline = true
  vim.wo[winnr].foldcolumn = "0"
  vim.wo[winnr].spell = false

  -- Only show cursorline in focused window
  vim.api.nvim_create_autocmd("WinEnter", {
    buffer = bufnr,
    callback = function()
      if vim.api.nvim_win_is_valid(winnr) then
        vim.wo[winnr].cursorline = true
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = bufnr,
    callback = function()
      if vim.api.nvim_win_is_valid(winnr) then
        vim.wo[winnr].cursorline = false
      end
    end,
  })

  tree_state.bufnr = bufnr
  tree_state.winnr = winnr

  -- Render
  render(session)

  -- Keymaps
  local function keymap(key, callback)
    vim.keymap.set("n", key, callback, { buffer = bufnr, nowait = true, silent = true })
  end

  -- Enter: open file or toggle directory
  keymap("<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(winnr)
    local idx = cursor[1]
    local entry = tree_state.entries[idx]
    if not entry then
      vim.notify("[reviewthem] No entry at line " .. idx, vim.log.levels.DEBUG)
      return
    end

    if entry.type == "dir" then
      tree_state.collapsed[entry.path] = not tree_state.collapsed[entry.path]
      render(session)
    elseif entry.type == "file" and entry.file_path then
      vim.schedule(function()
        on_select(entry.file_path)
      end)
    end
  end)

  -- r: toggle reviewed
  keymap("r", function()
    local cursor = vim.api.nvim_win_get_cursor(winnr)
    local idx = cursor[1]
    local entry = tree_state.entries[idx]
    if entry and entry.type == "file" and entry.file_path then
      on_toggle_reviewed(entry.file_path)
      render(session)
    end
  end)

  -- q: close tree
  keymap("q", function()
    M.close()
  end)

  return winnr
end

--- Refresh the tree display.
---@param session ReviewSession
M.refresh = function(session)
  render(session)
end

--- Close the file tree.
M.close = function()
  if tree_state.winnr and vim.api.nvim_win_is_valid(tree_state.winnr) then
    vim.api.nvim_win_close(tree_state.winnr, true)
  end
  if tree_state.bufnr and vim.api.nvim_buf_is_valid(tree_state.bufnr) then
    vim.api.nvim_buf_delete(tree_state.bufnr, { force = true })
  end
  tree_state.bufnr = nil
  tree_state.winnr = nil
  tree_state.entries = {}
end

--- Check if tree is open.
---@return boolean
M.is_open = function()
  return tree_state.winnr ~= nil and vim.api.nvim_win_is_valid(tree_state.winnr)
end

--- Get the window number.
---@return number|nil
M.get_winnr = function()
  return tree_state.winnr
end

--- Get the buffer number.
---@return number|nil
M.get_bufnr = function()
  return tree_state.bufnr
end

return M
