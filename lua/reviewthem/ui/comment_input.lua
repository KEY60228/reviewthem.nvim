local M = {}

---@class CommentInputState
---@field bufnr number|nil
---@field winnr number|nil
---@field input_start_line number
---@field autocmd_group number|nil

---@type CommentInputState
local float_state = {
  bufnr = nil,
  winnr = nil,
  input_start_line = 1,
  autocmd_group = nil,
}

local function safe_close()
  if float_state.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, float_state.autocmd_group)
    float_state.autocmd_group = nil
  end
  if float_state.winnr and vim.api.nvim_win_is_valid(float_state.winnr) then
    pcall(vim.api.nvim_win_close, float_state.winnr, true)
  end
  if float_state.bufnr and vim.api.nvim_buf_is_valid(float_state.bufnr) then
    pcall(vim.api.nvim_buf_delete, float_state.bufnr, { force = true })
  end
  float_state.bufnr = nil
  float_state.winnr = nil
  float_state.input_start_line = 1
end

--- Open a comment input floating window.
---@param opts {title: string|nil, preview_lines: string[]|nil, initial_text: string|nil, on_confirm: fun(text: string), on_cancel: fun()|nil}
M.open = function(opts)
  opts = opts or {}

  local config = require("reviewthem.config").get()
  local confirm_key = config.keymaps.confirm_comment
  local cancel_key = config.keymaps.cancel_comment

  local preview_lines = opts.preview_lines or {}
  local height = math.max(8, #preview_lines + 6)
  local width = 60

  for _, line in ipairs(preview_lines) do
    width = math.max(width, #line + 4)
  end
  width = math.min(width, math.floor(vim.o.columns * 0.8))

  -- Center the window
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. (opts.title or "Add Comment") .. " ",
    title_pos = "center",
  })

  vim.wo[winnr].wrap = true
  vim.wo[winnr].linebreak = true

  -- Build content: preview + separator + input area
  local content = {}
  local input_start_line

  if #preview_lines > 0 then
    table.insert(content, "── Preview ──")
    for _, line in ipairs(preview_lines) do
      table.insert(content, line)
    end
    table.insert(content, "── Comment ──")
    input_start_line = #content + 1
  else
    input_start_line = 1
  end

  -- Initial text or empty line
  if opts.initial_text then
    for line in (opts.initial_text .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(content, line)
    end
  else
    table.insert(content, "")
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

  -- Highlight preview area
  if #preview_lines > 0 then
    local ns = vim.api.nvim_create_namespace("reviewthem_comment_preview")
    for i = 0, input_start_line - 2 do
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", i, 0, -1)
    end
  end

  float_state.bufnr = bufnr
  float_state.winnr = winnr
  float_state.input_start_line = input_start_line

  -- Cursor restriction for preview area
  if input_start_line > 1 then
    local group = vim.api.nvim_create_augroup("ReviewThemCommentInput", { clear = true })
    float_state.autocmd_group = group

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = group,
      buffer = bufnr,
      callback = function()
        if not vim.api.nvim_win_is_valid(winnr) then
          return
        end
        local cursor = vim.api.nvim_win_get_cursor(winnr)
        if cursor[1] < input_start_line then
          vim.api.nvim_win_set_cursor(winnr, { input_start_line, 0 })
        end
      end,
    })
  end

  -- Confirm callback
  local function confirm()
    local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, input_start_line - 1, -1, false)
    if not ok then
      safe_close()
      return
    end
    -- Trim trailing empty lines
    while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
    end
    local text = table.concat(lines, "\n")
    safe_close()
    if text ~= "" and opts.on_confirm then
      opts.on_confirm(text)
    elseif opts.on_cancel then
      opts.on_cancel()
    end
  end

  local function cancel()
    safe_close()
    if opts.on_cancel then
      opts.on_cancel()
    end
  end

  -- Keymaps
  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, confirm_key, confirm, { buffer = bufnr, nowait = true, silent = true })
    vim.keymap.set(mode, cancel_key, cancel, { buffer = bufnr, nowait = true, silent = true })
  end

  -- Move cursor to input and start insert
  vim.api.nvim_win_set_cursor(winnr, { input_start_line, 0 })
  vim.cmd("startinsert")

  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].buftype = "nofile"
end

return M
