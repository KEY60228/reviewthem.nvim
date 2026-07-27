local M = {}

local ns = vim.api.nvim_create_namespace("reviewthem_diff")

--- Extmark priorities. Treesitter highlights use 100, so the add/remove line
--- background stays below it (syntax colors keep their foreground) and the
--- word-level diff span sits above it.
M.PRIORITY_LINE = 90
M.PRIORITY_WORD = 200

--- Define highlight groups.
M.setup_highlights = function()
  local groups = {
    ReviewThemAdd = { default = true, link = "DiffAdd" },
    ReviewThemDelete = { default = true, link = "DiffDelete" },
    ReviewThemChange = { default = true, link = "DiffChange" },
    ReviewThemWordAdd = { default = true, link = "DiffText" },
    ReviewThemWordDelete = { default = true, link = "DiffText" },
    ReviewThemHunkHeader = { default = true, bg = "#3b3b4f", fg = "#a0a0c0", italic = true },
    ReviewThemFileHeader = { default = true, bg = "#2a4a2a", fg = "#c0e0c0", bold = true },
    ReviewThemLineNrOld = { default = true, fg = "#e06060" },
    ReviewThemLineNrNew = { default = true, fg = "#60e060" },
    ReviewThemLineNrContext = { default = true, link = "LineNr" },
    ReviewThemCommentSign = { default = true, fg = "#f0c060" },
    ReviewThemSeparator = { default = true, fg = "#555555" },
    ReviewThemPadding = { default = true, bg = "#1a1a2a" },
  }
  for name, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

---@return number namespace id
M.get_namespace = function()
  return ns
end

--- Format line number pair as virtual text for unified view.
---@param old_lineno number|nil
---@param new_lineno number|nil
---@return string
M.format_line_numbers = function(old_lineno, new_lineno)
  local old_str = old_lineno and string.format("%4d", old_lineno) or "    "
  local new_str = new_lineno and string.format("%4d", new_lineno) or "    "
  return old_str .. " " .. new_str
end

--- Apply line highlight and virtual text to a buffer line.
---@param bufnr number
---@param line_idx number  0-indexed line in buffer
---@param hunk_line HunkLine
M.decorate_line = function(bufnr, line_idx, hunk_line)
  local hl_group
  local nr_hl_group
  if hunk_line.type == "add" then
    hl_group = "ReviewThemAdd"
    nr_hl_group = "ReviewThemLineNrNew"
  elseif hunk_line.type == "remove" then
    hl_group = "ReviewThemDelete"
    nr_hl_group = "ReviewThemLineNrOld"
  else
    hl_group = nil
    nr_hl_group = "ReviewThemLineNrContext"
  end

  -- Line highlight.
  --
  -- Painted as a character range that spans the end of the line (`hl_eol`
  -- extends it across the rest of the screen line) instead of
  -- `line_hl_group`: `line_hl_group` ignores `priority` and hides any
  -- `hl_group` extmark on the same line, which would swallow the
  -- word-level diff span.
  if hl_group then
    vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
      end_row = line_idx + 1,
      end_col = 0,
      hl_group = hl_group,
      hl_eol = true,
      priority = M.PRIORITY_LINE,
    })
  end

  -- Line number virtual text in sign column area
  local nr_text = M.format_line_numbers(hunk_line.old_lineno, hunk_line.new_lineno)
  vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
    virt_text = { { nr_text .. " ", nr_hl_group } },
    virt_text_pos = "inline",
    priority = 10,
  })
end

--- Highlight the differing span within a changed line (word-level diff).
---@param bufnr number
---@param line_idx number  0-indexed line in buffer
---@param start_col number  0-indexed byte column, inclusive
---@param end_col number  0-indexed byte column, exclusive
---@param hl_group string
M.add_word_diff = function(bufnr, line_idx, start_col, end_col, hl_group)
  vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, start_col, {
    end_col = end_col,
    hl_group = hl_group,
    priority = M.PRIORITY_WORD,
  })
end

--- Add a comment indicator on a buffer line.
---@param bufnr number
---@param line_idx number  0-indexed
---@param sign string
M.add_comment_sign = function(bufnr, line_idx, sign)
  vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
    virt_text = { { " " .. sign, "ReviewThemCommentSign" } },
    virt_text_pos = "eol",
    priority = 20,
  })
end

--- Add a file header decoration.
---@param bufnr number
---@param line_idx number  0-indexed
M.decorate_file_header = function(bufnr, line_idx)
  vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
    line_hl_group = "ReviewThemFileHeader",
  })
end

--- Add a hunk header decoration.
---@param bufnr number
---@param line_idx number  0-indexed
M.decorate_hunk_header = function(bufnr, line_idx)
  vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
    line_hl_group = "ReviewThemHunkHeader",
  })
end

--- Clear all extmarks in a buffer.
---@param bufnr number
M.clear = function(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

return M
