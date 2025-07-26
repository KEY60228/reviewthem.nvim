local M = {}

-- Store active float window state
local active_float = {
  buf = nil,
  win = nil,
  input_start_line = nil,
  autocmd_group = nil,
}

local function create_float_window(opts)
  local width = opts.width or 60
  local height = opts.height or 10
  local row = opts.row or 0
  local col = opts.col or 0

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Window options
  local win_opts = {
    relative = "cursor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = opts.title or "Comment",
    title_pos = "center",
  }

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set window options
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "linebreak", true)

  return buf, win
end

local function setup_keymaps(buf, confirm_key, cancel_key, on_confirm, on_cancel, input_start_line)
  local confirm_callback = function()
    -- Get only the lines from the input area (after preview)
    local lines = vim.api.nvim_buf_get_lines(buf, input_start_line - 1, -1, false)
    -- Remove empty lines at the end
    while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
    end
    local text = table.concat(lines, "\n")
    if text ~= "" then
      on_confirm(text)
    else
      on_cancel()
    end
  end

  -- Confirm keybindings (both insert and normal mode)
  vim.api.nvim_buf_set_keymap(buf, "i", confirm_key, "", {
    noremap = true,
    silent = true,
    callback = confirm_callback
  })

  vim.api.nvim_buf_set_keymap(buf, "n", confirm_key, "", {
    noremap = true,
    silent = true,
    callback = confirm_callback
  })

  -- Cancel keybindings (both insert and normal mode)
  vim.api.nvim_buf_set_keymap(buf, "n", cancel_key, "", {
    noremap = true,
    silent = true,
    callback = on_cancel
  })

  vim.api.nvim_buf_set_keymap(buf, "i", cancel_key, "", {
    noremap = true,
    silent = true,
    callback = on_cancel
  })

  -- Allow normal mode editing
  vim.api.nvim_buf_set_keymap(buf, "n", "i", "i", { noremap = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "a", "a", { noremap = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "o", "o", { noremap = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "O", "O", { noremap = true })
end

local function setup_cursor_restriction(buf, win, input_start_line)
  -- Create autocmd group
  local group = vim.api.nvim_create_augroup("ReviewThemFloatCursor", { clear = true })

  -- Store the active state
  active_float.buf = buf
  active_float.win = win
  active_float.input_start_line = input_start_line
  active_float.autocmd_group = group

  -- Restrict cursor movement
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end

      local cursor = vim.api.nvim_win_get_cursor(win)
      local row = cursor[1]

      -- If cursor is in preview area (before input_start_line), move it back
      if row < input_start_line then
        vim.api.nvim_win_set_cursor(win, { input_start_line, 0 })
      end
    end,
  })

  -- Also prevent text changes in preview area
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end

      -- Get current buffer lines
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      -- If preview area was modified, restore it
      if #lines < input_start_line - 1 then
        -- Buffer was cleared or preview lines were deleted
        local cursor = vim.api.nvim_win_get_cursor(win)
        vim.api.nvim_win_set_cursor(win, { input_start_line, 0 })
      end
    end,
  })
end

local function cleanup_autocmds()
  if active_float.autocmd_group then
    vim.api.nvim_del_augroup_by_id(active_float.autocmd_group)
    active_float.buf = nil
    active_float.win = nil
    active_float.input_start_line = nil
    active_float.autocmd_group = nil
  end
end

local function add_preview_lines(buf, preview_lines)
  if not preview_lines or #preview_lines == 0 then
    return 1  -- Return 1 instead of 0 for no preview case
  end

  local lines = {}
  table.insert(lines, "── Preview ──")
  for _, line in ipairs(preview_lines) do
    table.insert(lines, line)
  end
  table.insert(lines, "── Comment ──")
  table.insert(lines, "")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Make preview lines read-only by highlighting them differently
  local ns_id = vim.api.nvim_create_namespace("reviewthem_preview")
  for i = 0, #preview_lines + 1 do
    vim.api.nvim_buf_add_highlight(buf, ns_id, "Comment", i, 0, -1)
  end

  -- Return the line number where user input should start (1-indexed)
  return #lines
end

function M.open(opts)
  opts = opts or {}

  -- Get config for keybindings
  local config = require("reviewthem.config").get()
  local confirm_key = config.keymaps.confirm_comment
  local cancel_key = config.keymaps.cancel_comment

  -- Calculate window dimensions based on preview
  local preview_lines = opts.preview_lines or {}
  local height = math.max(10, #preview_lines + 6) -- Preview + separators + input space
  local width = 60

  -- Calculate max width from preview lines
  for _, line in ipairs(preview_lines) do
    width = math.max(width, #line + 4)
  end

  -- Position window slightly below cursor
  local row = 1
  local col = 0

  -- Create float window
  local buf, win = create_float_window({
    width = width,
    height = height,
    row = row,
    col = col,
    title = opts.title or "Add Comment",
  })

  -- Add preview lines
  local input_start_line = add_preview_lines(buf, preview_lines)

  -- Set up completion function
  local on_confirm = function(text)
    cleanup_autocmds()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    if opts.on_confirm then
      opts.on_confirm(text)
    end
  end

  local on_cancel = function()
    cleanup_autocmds()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    if opts.on_cancel then
      opts.on_cancel()
    end
  end

  -- Set up keymaps with input_start_line
  setup_keymaps(buf, confirm_key, cancel_key, on_confirm, on_cancel, input_start_line)

  -- Set up cursor restriction to protect preview area (only if there's preview)
  if input_start_line > 1 then
    setup_cursor_restriction(buf, win, input_start_line)
  end

  -- Move cursor to input area and enter insert mode
  vim.api.nvim_win_set_cursor(win, {input_start_line, 0})
  vim.cmd("startinsert")

  -- Set buffer to be modifiable
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  return buf, win
end

return M
