local renderer = require("reviewthem.diff.renderer")

local M = {}

--- Flag to distinguish intentional close (Pause/Submit/Abort) from accidental :q.
local closing_intentionally = false

---@class SplitViewState
---@field old_bufnr number|nil
---@field new_bufnr number|nil
---@field old_winnr number|nil
---@field new_winnr number|nil
---@field line_map_old table[]
---@field line_map_new table[]
---@field current_file string|nil
---@field session ReviewSession|nil

---@type SplitViewState
local view_state = {
  old_bufnr = nil,
  new_bufnr = nil,
  old_winnr = nil,
  new_winnr = nil,
  line_map_old = {},
  line_map_new = {},
  current_file = nil,
  session = nil,
}

--- Build aligned old/new content for a single file.
---@param file DiffFile
---@return string[] old_lines, string[] new_lines, table[] old_map, table[] new_map
local function build_split_content(file)
  local old_lines = {}
  local new_lines = {}
  local old_map = {}
  local new_map = {}

  -- File header
  table.insert(old_lines, string.format("═══ %s (base) ═══", file.path))
  table.insert(new_lines, string.format("═══ %s (compare) ═══", file.path))
  table.insert(old_map, { type = "file_header", file = file.path })
  table.insert(new_map, { type = "file_header", file = file.path })

  for _, hunk in ipairs(file.hunks) do
    -- Hunk header
    table.insert(old_lines, hunk.header)
    table.insert(new_lines, hunk.header)
    table.insert(old_map, { type = "hunk_header", file = file.path })
    table.insert(new_map, { type = "hunk_header", file = file.path })

    -- Process hunk lines: group consecutive add/remove pairs for alignment
    local i = 1
    local hunk_lines = hunk.lines
    while i <= #hunk_lines do
      local hline = hunk_lines[i]

      if hline.type == "context" then
        table.insert(old_lines, " " .. hline.content)
        table.insert(new_lines, " " .. hline.content)
        table.insert(old_map, {
          type = "diff_line",
          file = file.path,
          side = "old",
          lineno = hline.old_lineno,
          hunk_line = hline,
        })
        table.insert(new_map, {
          type = "diff_line",
          file = file.path,
          side = "new",
          lineno = hline.new_lineno,
          hunk_line = hline,
        })
        i = i + 1
      else
        -- Collect consecutive removes and adds
        local removes = {}
        local adds = {}
        while i <= #hunk_lines and hunk_lines[i].type == "remove" do
          table.insert(removes, hunk_lines[i])
          i = i + 1
        end
        while i <= #hunk_lines and hunk_lines[i].type == "add" do
          table.insert(adds, hunk_lines[i])
          i = i + 1
        end

        -- Align removes and adds
        local max_len = math.max(#removes, #adds)
        for j = 1, max_len do
          if j <= #removes then
            table.insert(old_lines, "-" .. removes[j].content)
            table.insert(old_map, {
              type = "diff_line",
              file = file.path,
              side = "old",
              lineno = removes[j].old_lineno,
              hunk_line = removes[j],
            })
          else
            table.insert(old_lines, "")
            table.insert(old_map, { type = "padding", file = file.path })
          end

          if j <= #adds then
            table.insert(new_lines, "+" .. adds[j].content)
            table.insert(new_map, {
              type = "diff_line",
              file = file.path,
              side = "new",
              lineno = adds[j].new_lineno,
              hunk_line = adds[j],
            })
          else
            table.insert(new_lines, "")
            table.insert(new_map, { type = "padding", file = file.path })
          end
        end
      end
    end
  end

  return old_lines, new_lines, old_map, new_map
end

--- Apply decorations to a split buffer.
---@param bufnr number
---@param line_map table[]
---@param session ReviewSession
local function apply_split_decorations(bufnr, line_map, session)
  renderer.clear(bufnr)

  local comment_lookup = {}
  for _, c in ipairs(session.comments) do
    for l = c.start_line, c.end_line do
      comment_lookup[c.file .. ":" .. c.side .. ":" .. l] = true
    end
  end

  local config = require("reviewthem.config").get()

  for i, entry in ipairs(line_map) do
    local line_idx = i - 1
    if entry.type == "file_header" then
      renderer.decorate_file_header(bufnr, line_idx)
    elseif entry.type == "hunk_header" then
      renderer.decorate_hunk_header(bufnr, line_idx)
    elseif entry.type == "diff_line" then
      renderer.decorate_line(bufnr, line_idx, entry.hunk_line)
      local key = entry.file .. ":" .. entry.side .. ":" .. entry.lineno
      if comment_lookup[key] then
        renderer.add_comment_sign(bufnr, line_idx, config.comment_sign)
      end
    elseif entry.type == "padding" then
      vim.api.nvim_buf_set_extmark(bufnr, renderer.get_namespace(), line_idx, 0, {
        line_hl_group = "ReviewThemPadding",
      })
    end
  end
end

--- Prevent accidental close of diff buffer windows.
---@param bufnr number
local function protect_diff_buffer(bufnr)
  if vim.b[bufnr].reviewthem_protected then
    return
  end
  vim.b[bufnr].reviewthem_protected = true

  local function warn_close()
    vim.notify("Use :ReviewThemPause to close the review", vim.log.levels.WARN)
  end

  -- Block keyboard shortcuts that close windows
  for _, key in ipairs({ "ZZ", "ZQ", "<C-w>c", "<C-w>q" }) do
    vim.keymap.set("n", key, warn_close, { buffer = bufnr, nowait = true, silent = true })
  end

  -- Auto-pause if :q / :close etc. manages to close the window
  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = bufnr,
    callback = function()
      if closing_intentionally then
        return
      end
      vim.schedule(function()
        -- Double-check: if the buffer is gone, the close was intentional (session ended)
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        vim.notify("Diff view closed — pausing review session.", vim.log.levels.INFO)
        vim.cmd("ReviewThemPause")
      end)
    end,
  })
end

--- Mark close as intentional (called before Pause/Submit/Abort).
M.set_closing_intentionally = function()
  closing_intentionally = true
end

--- Create or get a buffer for split view.
---@param name string
---@return number bufnr
local function get_or_create_buf(name)
  local bufnr = vim.fn.bufnr(name)
  if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, name)
  end
  return bufnr
end

--- Render split view for a single file.
---@param session ReviewSession
---@param file DiffFile
---@param old_winnr number
---@param new_winnr number
M.render_file = function(session, file, old_winnr, new_winnr)
  local old_lines, new_lines, old_map, new_map = build_split_content(file)

  local old_bufnr = get_or_create_buf("reviewthem://old")
  local new_bufnr = get_or_create_buf("reviewthem://new")

  -- Fill old buffer
  vim.bo[old_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(old_bufnr, 0, -1, false, old_lines)
  vim.bo[old_bufnr].modifiable = false
  vim.bo[old_bufnr].buftype = "nofile"
  vim.bo[old_bufnr].swapfile = false
  vim.bo[old_bufnr].filetype = "reviewthem-diff"

  -- Fill new buffer
  vim.bo[new_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(new_bufnr, 0, -1, false, new_lines)
  vim.bo[new_bufnr].modifiable = false
  vim.bo[new_bufnr].buftype = "nofile"
  vim.bo[new_bufnr].swapfile = false
  vim.bo[new_bufnr].filetype = "reviewthem-diff"

  -- Protect from accidental close
  protect_diff_buffer(old_bufnr)
  protect_diff_buffer(new_bufnr)

  -- Show in windows
  vim.api.nvim_win_set_buf(old_winnr, old_bufnr)
  vim.api.nvim_win_set_buf(new_winnr, new_bufnr)

  -- Set window options
  for _, winnr in ipairs({ old_winnr, new_winnr }) do
    vim.wo[winnr].number = false
    vim.wo[winnr].relativenumber = false
    vim.wo[winnr].signcolumn = "no"
    vim.wo[winnr].wrap = false
    vim.wo[winnr].cursorline = true
    vim.wo[winnr].scrollbind = true
    vim.wo[winnr].cursorbind = true

    -- Only show cursorline in focused window
    local bufnr = vim.api.nvim_win_get_buf(winnr)
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
  end

  -- Apply decorations
  apply_split_decorations(old_bufnr, old_map, session)
  apply_split_decorations(new_bufnr, new_map, session)

  -- Update state
  view_state.old_bufnr = old_bufnr
  view_state.new_bufnr = new_bufnr
  view_state.old_winnr = old_winnr
  view_state.new_winnr = new_winnr
  view_state.line_map_old = old_map
  view_state.line_map_new = new_map
  view_state.current_file = file.path
  view_state.session = session
end

--- Refresh decorations for the current split view.
---@param session ReviewSession
M.refresh_decorations = function(session)
  if view_state.old_bufnr and vim.api.nvim_buf_is_valid(view_state.old_bufnr) then
    apply_split_decorations(view_state.old_bufnr, view_state.line_map_old, session)
  end
  if view_state.new_bufnr and vim.api.nvim_buf_is_valid(view_state.new_bufnr) then
    apply_split_decorations(view_state.new_bufnr, view_state.line_map_new, session)
  end
end

--- Get context info for cursor position in either split buffer.
---@return table|nil
M.get_cursor_context = function()
  local current_buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  local line_map
  if current_buf == view_state.old_bufnr then
    line_map = view_state.line_map_old
  elseif current_buf == view_state.new_bufnr then
    line_map = view_state.line_map_new
  else
    return nil
  end

  local entry = line_map[row]
  if not entry or entry.type ~= "diff_line" then
    return nil
  end

  return {
    file = entry.file,
    side = entry.side,
    lineno = entry.lineno,
    hunk_line = entry.hunk_line,
  }
end

--- Get the current file being viewed.
---@return string|nil
M.get_current_file = function()
  return view_state.current_file
end

--- Jump cursor to a specific file line in the split view.
---@param side "old"|"new"
---@param lineno number
M.jump_to_line = function(side, lineno)
  local line_map = side == "old" and view_state.line_map_old or view_state.line_map_new
  local winnr = side == "old" and view_state.old_winnr or view_state.new_winnr

  if not line_map or not winnr or not vim.api.nvim_win_is_valid(winnr) then
    return
  end

  for i, entry in ipairs(line_map) do
    if entry.type == "diff_line" and entry.side == side and entry.lineno == lineno then
      vim.api.nvim_set_current_win(winnr)
      vim.api.nvim_win_set_cursor(winnr, { i, 0 })
      return
    end
  end
end

--- Close split view buffers.
M.close = function()
  closing_intentionally = true
  for _, bufnr in ipairs({ view_state.old_bufnr, view_state.new_bufnr }) do
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  view_state.old_bufnr = nil
  view_state.new_bufnr = nil
  view_state.old_winnr = nil
  view_state.new_winnr = nil
  view_state.line_map_old = {}
  view_state.line_map_new = {}
  view_state.current_file = nil
  view_state.session = nil
  closing_intentionally = false
end

return M
