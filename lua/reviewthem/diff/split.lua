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

---@type table<number, number> Last wrap width used per buffer, to skip no-op refreshes
local wrap_widths = {}

--- Wrap width for inline comment text: keep blocks readable without
--- overflowing the window.
---@param bufnr number
---@return number
local function compute_wrap_width(bufnr)
  -- win_findbuf searches all tabpages; bufwinid only searches the current
  -- one, which made a resize from another tab fall back to the full screen
  -- width and persist a wrap width wider than the pane.
  local winid = vim.fn.win_findbuf(bufnr)[1]
  if not winid then
    return wrap_widths[bufnr] or math.max(20, math.min(80, vim.o.columns - 10))
  end
  return math.max(20, math.min(80, vim.api.nvim_win_get_width(winid) - 10))
end

--- Apply decorations to a split buffer.
---@param bufnr number
---@param line_map table[]
---@param session ReviewSession
---@return table<number, number> inline_heights  virt_lines count per 0-indexed row
local function apply_split_decorations(bufnr, line_map, session)
  renderer.clear(bufnr)

  local config = require("reviewthem.config").get()

  -- Linenos actually rendered in this buffer. A comment's end_line may not
  -- be among them (e.g. a range saved by an older version overshot the
  -- hunk), so inline blocks anchor at the last rendered line of their range
  -- instead of blindly at end_line — otherwise the block silently vanishes.
  local rendered = {}
  for _, entry in ipairs(line_map) do
    if entry.type == "diff_line" then
      rendered[entry.file .. ":" .. entry.side .. ":" .. entry.lineno] = true
    end
  end

  local comment_lookup = {}
  local inline_lookup = {}
  for _, c in ipairs(session.comments) do
    for l = c.start_line, c.end_line do
      comment_lookup[c.file .. ":" .. c.side .. ":" .. l] = true
    end
    if config.inline_comments then
      for l = c.end_line, c.start_line, -1 do
        local key = c.file .. ":" .. c.side .. ":" .. l
        if rendered[key] then
          inline_lookup[key] = inline_lookup[key] or {}
          table.insert(inline_lookup[key], c)
          break
        end
      end
    end
  end
  for _, list in pairs(inline_lookup) do
    table.sort(list, function(a, b)
      if a.start_line ~= b.start_line then
        return a.start_line < b.start_line
      end
      return tostring(a.id) < tostring(b.id)
    end)
  end

  local wrap_width = compute_wrap_width(bufnr)
  wrap_widths[bufnr] = wrap_width

  local inline_heights = {}

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
      local inline_comments = inline_lookup[key]
      if inline_comments then
        inline_heights[line_idx] =
          renderer.add_inline_comments(bufnr, line_idx, inline_comments, config.comment_sign, wrap_width)
      end
    elseif entry.type == "padding" then
      vim.api.nvim_buf_set_extmark(bufnr, renderer.get_namespace(), line_idx, 0, {
        line_hl_group = "ReviewThemPadding",
      })
    end
  end

  return inline_heights
end

--- Decorate both panes of the current view.
--- Inline comment blocks only exist on the side they belong to, so the opposite
--- pane gets blank filler lines of the same height. Without them the panes would
--- drift apart on screen: 'scrollbind' syncs buffer lines, not screen rows.
---@param session ReviewSession
local function apply_both_decorations(session)
  local old_bufnr = view_state.old_bufnr
  local new_bufnr = view_state.new_bufnr
  local old_valid = old_bufnr ~= nil and vim.api.nvim_buf_is_valid(old_bufnr)
  local new_valid = new_bufnr ~= nil and vim.api.nvim_buf_is_valid(new_bufnr)

  local old_heights = old_valid and apply_split_decorations(old_bufnr, view_state.line_map_old, session) or {}
  local new_heights = new_valid and apply_split_decorations(new_bufnr, view_state.line_map_new, session) or {}

  if not (old_valid and new_valid) then
    return
  end

  -- Both line maps are built in lockstep, so a row index means the same
  -- position in either pane.
  for line_idx, height in pairs(old_heights) do
    renderer.add_filler_lines(new_bufnr, line_idx, height - (new_heights[line_idx] or 0))
  end
  for line_idx, height in pairs(new_heights) do
    renderer.add_filler_lines(old_bufnr, line_idx, height - (old_heights[line_idx] or 0))
  end
end

local RESIZE_AUGROUP = "ReviewThemSplitResize"

--- Re-render decorations when a pane resize changes the inline comment wrap
--- width. Registered once per render; the augroup is cleared on re-register.
local function setup_resize_refresh()
  local group = vim.api.nvim_create_augroup(RESIZE_AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = group,
    callback = function()
      local session = view_state.session
      if not session then
        return
      end
      local changed = false
      for _, bufnr in ipairs({ view_state.old_bufnr, view_state.new_bufnr }) do
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) and wrap_widths[bufnr] ~= compute_wrap_width(bufnr) then
          changed = true
        end
      end
      if not changed then
        return
      end
      vim.schedule(function()
        if view_state.session then
          M.refresh_decorations(view_state.session)
        end
      end)
    end,
  })
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

  -- Update state (decorations below need both line maps for pane alignment)
  view_state.old_bufnr = old_bufnr
  view_state.new_bufnr = new_bufnr
  view_state.old_winnr = old_winnr
  view_state.new_winnr = new_winnr
  view_state.line_map_old = old_map
  view_state.line_map_new = new_map
  view_state.current_file = file.path
  view_state.session = session

  -- Apply decorations
  apply_both_decorations(session)

  -- Re-wrap inline comments when the panes change width
  setup_resize_refresh()
end

--- Refresh decorations for the current split view.
---@param session ReviewSession
M.refresh_decorations = function(session)
  apply_both_decorations(session)
end

--- Get context info for a range of buffer rows in either split buffer.
--- Rows that are not diff lines (padding, hunk/file headers) are skipped, so
--- start_lineno/end_lineno cover only real file lines within the range.
---@param row1 number  1-indexed first buffer row
---@param row2 number  1-indexed last buffer row
---@return table|nil
M.get_range_context = function(row1, row2)
  local current_buf = vim.api.nvim_get_current_buf()

  local line_map
  if current_buf == view_state.old_bufnr then
    line_map = view_state.line_map_old
  elseif current_buf == view_state.new_bufnr then
    line_map = view_state.line_map_new
  else
    return nil
  end

  local first, start_lineno, end_lineno
  for row = row1, row2 do
    local entry = line_map[row]
    if entry and entry.type == "diff_line" then
      first = first or entry
      start_lineno = math.min(start_lineno or entry.lineno, entry.lineno)
      end_lineno = math.max(end_lineno or entry.lineno, entry.lineno)
    end
  end

  if not first then
    return nil
  end

  return {
    file = first.file,
    side = first.side,
    lineno = first.lineno,
    start_lineno = start_lineno,
    end_lineno = end_lineno,
    hunk_line = first.hunk_line,
  }
end

--- Get context info for cursor position in either split buffer.
---@return table|nil
M.get_cursor_context = function()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return M.get_range_context(row, row)
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
  pcall(vim.api.nvim_del_augroup_by_name, RESIZE_AUGROUP)
  for _, bufnr in ipairs({ view_state.old_bufnr, view_state.new_bufnr }) do
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  wrap_widths = {}
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
