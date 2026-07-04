local M = {}

local ns = vim.api.nvim_create_namespace("reviewthem_diff")

--- Define highlight groups.
M.setup_highlights = function()
  local groups = {
    ReviewThemAdd = { default = true, link = "DiffAdd" },
    ReviewThemDelete = { default = true, link = "DiffDelete" },
    ReviewThemChange = { default = true, link = "DiffChange" },
    ReviewThemHunkHeader = { default = true, bg = "#3b3b4f", fg = "#a0a0c0", italic = true },
    ReviewThemFileHeader = { default = true, bg = "#2a4a2a", fg = "#c0e0c0", bold = true },
    ReviewThemLineNrOld = { default = true, fg = "#e06060" },
    ReviewThemLineNrNew = { default = true, fg = "#60e060" },
    ReviewThemLineNrContext = { default = true, link = "LineNr" },
    ReviewThemCommentSign = { default = true, fg = "#f0c060" },
    ReviewThemInlineComment = { default = true, link = "Comment" },
    ReviewThemInlineCommentBorder = { default = true, link = "NonText" },
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

  -- Line highlight
  if hl_group then
    vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
      line_hl_group = hl_group,
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

--- Wrap a single line of text by display width, safe for multibyte text.
---@param line string
---@param max_width number
---@return string[]
local function wrap_line(line, max_width)
  if max_width < 1 then
    max_width = 1
  end
  if line == "" or vim.fn.strdisplaywidth(line) <= max_width then
    return { line }
  end

  local wrapped = {}
  local current = ""
  local current_width = 0
  -- Iterate over UTF-8 characters
  for ch in line:gmatch("[\1-\127\194-\244][\128-\191]*") do
    local w = vim.fn.strdisplaywidth(ch)
    if current_width + w > max_width and current ~= "" then
      table.insert(wrapped, current)
      current = ""
      current_width = 0
    end
    current = current .. ch
    current_width = current_width + w
  end
  if current ~= "" then
    table.insert(wrapped, current)
  end
  return wrapped
end

--- Render comment blocks inline below a buffer line using virt_lines.
--- Multiple comments are stacked in order.
---@param bufnr number
---@param line_idx number  0-indexed anchor line
---@param comments Comment[]
---@param sign string
---@param max_width number  maximum display width for comment text lines
M.add_inline_comments = function(bufnr, line_idx, comments, sign, max_width)
  local virt_lines = {}
  for _, comment in ipairs(comments) do
    local range = comment.start_line == comment.end_line and ("L" .. comment.start_line)
      or ("L" .. comment.start_line .. "-" .. comment.end_line)
    table.insert(virt_lines, {
      { "  ┌─ ", "ReviewThemInlineCommentBorder" },
      { sign .. " " .. range, "ReviewThemInlineComment" },
      { " ─", "ReviewThemInlineCommentBorder" },
    })
    for _, text_line in ipairs(vim.split(comment.text, "\n", { plain = true })) do
      for _, chunk in ipairs(wrap_line(text_line, max_width)) do
        table.insert(virt_lines, {
          { "  │ ", "ReviewThemInlineCommentBorder" },
          { chunk, "ReviewThemInlineComment" },
        })
      end
    end
    table.insert(virt_lines, { { "  └─", "ReviewThemInlineCommentBorder" } })
  end

  vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
    virt_lines = virt_lines,
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
