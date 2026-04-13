local M = {}

--- Open a floating picker window.
--- API is compatible with vim.ui.select for easy replacement.
---@param items any[]
---@param opts {prompt: string|nil, format_item: (fun(item: any): string)|nil, highlight_item: (fun(item: any): {[1]: string, [2]: number, [3]: number}[])|nil, on_delete: (fun(item: any))|nil}
---@param on_choice fun(item: any|nil)
M.open = function(items, opts, on_choice)
  opts = opts or {}
  if #items == 0 then
    on_choice(nil)
    return
  end

  local format_item = opts.format_item or tostring

  -- Build display lines
  local lines = {}
  for _, item in ipairs(items) do
    table.insert(lines, "  " .. format_item(item))
  end

  -- Size
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end
  local width = math.min(math.max(max_width + 2, 30), math.floor(vim.o.columns * 0.8))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.6))

  -- Center
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = "nofile"

  -- Apply per-item highlights
  if opts.highlight_item then
    local hl_ns = vim.api.nvim_create_namespace("reviewthem_picker_hl")
    local prefix_len = 2 -- "  " prefix
    for i, item in ipairs(items) do
      local highlights = opts.highlight_item(item)
      for _, hl in ipairs(highlights) do
        pcall(vim.api.nvim_buf_add_highlight, bufnr, hl_ns, hl[1], i - 1, prefix_len + hl[2], prefix_len + hl[3])
      end
    end
  end

  local title = opts.prompt and (" " .. opts.prompt:gsub(":?%s*$", "") .. " ") or nil
  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = title and "center" or nil,
  })

  vim.wo[winnr].cursorline = true
  vim.wo[winnr].wrap = false
  vim.wo[winnr].scrollbind = false
  vim.wo[winnr].cursorbind = false
  vim.api.nvim_win_set_cursor(winnr, { 1, 0 })

  -- Suppress cursorline in all background windows while picker is open
  local saved_cursorlines = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= winnr then
      saved_cursorlines[w] = vim.wo[w].cursorline
      vim.wo[w].cursorline = false
    end
  end

  local closed = false

  local function close()
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    -- Restore cursorline state
    for w, val in pairs(saved_cursorlines) do
      if vim.api.nvim_win_is_valid(w) then
        vim.wo[w].cursorline = val
      end
    end
  end

  local function confirm()
    local cursor = vim.api.nvim_win_get_cursor(winnr)
    local idx = cursor[1]
    close()
    vim.schedule(function()
      on_choice(items[idx])
    end)
  end

  local function cancel()
    close()
    on_choice(nil)
  end

  -- Keymaps
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = bufnr, nowait = true, silent = true })
  end

  map("<CR>", confirm)
  map("<Esc>", cancel)
  map("q", cancel)
  map("j", "j")
  map("k", "k")

  if opts.on_delete then
    map("d", function()
      local cursor = vim.api.nvim_win_get_cursor(winnr)
      local idx = cursor[1]
      local item = items[idx]
      if not item then
        return
      end
      local label = format_item(item)
      local choice = vim.fn.confirm("Delete '" .. label .. "'?", "&Yes\n&No", 2)
      if choice ~= 1 then
        return
      end
      opts.on_delete(item)
      -- Remove from items and rebuild display
      table.remove(items, idx)
      if #items == 0 then
        cancel()
        return
      end
      table.remove(lines, idx)
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].modifiable = false
      -- Adjust cursor if we deleted the last line
      if idx > #items then
        vim.api.nvim_win_set_cursor(winnr, { #items, 0 })
      end
      -- Resize window height
      local new_height = math.min(#lines, math.floor(vim.o.lines * 0.6))
      vim.api.nvim_win_set_config(winnr, { height = new_height })
    end)
  end

  -- Close on BufLeave
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = bufnr,
    once = true,
    callback = function()
      vim.schedule(cancel)
    end,
  })
end

return M
