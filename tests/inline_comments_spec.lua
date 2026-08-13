-- Headless functional check for inline comment rendering via virt_lines.
-- Run with: nvim --headless -l tests/inline_comments_spec.lua

local script = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script, ":h:h")
vim.opt.rtp:prepend(root)

require("reviewthem").setup()

local renderer = require("reviewthem.diff.renderer")
local split = require("reviewthem.diff.split")

local failures = 0
local function check(cond, msg)
  if cond then
    print("ok - " .. msg)
  else
    failures = failures + 1
    print("FAIL - " .. msg)
  end
end

--- All virt_lines extmarks of a buffer as { row = 0-indexed, lines = string[] }.
---@param bufnr number
---@return table[]
local function virt_line_marks(bufnr)
  local marks = {}
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, renderer.get_namespace(), 0, -1, { details = true })
  for _, mark in ipairs(extmarks) do
    if mark[4].virt_lines then
      local lines = {}
      for _, vline in ipairs(mark[4].virt_lines) do
        local text = ""
        for _, chunk in ipairs(vline) do
          text = text .. chunk[1]
        end
        table.insert(lines, text)
      end
      table.insert(marks, { row = mark[2], lines = lines })
    end
  end
  return marks
end

--- Marks that actually draw text, i.e. comment blocks and not alignment fillers.
---@param bufnr number
---@return table[]
local function comment_block_marks(bufnr)
  local blocks = {}
  for _, mark in ipairs(virt_line_marks(bufnr)) do
    for _, line in ipairs(mark.lines) do
      if line ~= "" then
        table.insert(blocks, mark)
        break
      end
    end
  end
  return blocks
end

--- Total number of virtual lines per buffer row.
---@param bufnr number
---@return table<number, number>
local function virt_line_heights(bufnr)
  local heights = {}
  for _, mark in ipairs(virt_line_marks(bufnr)) do
    heights[mark.row] = (heights[mark.row] or 0) + #mark.lines
  end
  return heights
end

---@type DiffFile
local file = {
  path = "test.lua",
  status = "M",
  hunks = {
    {
      header = "@@ -1,3 +1,3 @@",
      old_start = 1,
      old_count = 3,
      new_start = 1,
      new_count = 3,
      lines = {
        { type = "context", content = "line one", old_lineno = 1, new_lineno = 1 },
        { type = "remove", content = "old line", old_lineno = 2 },
        { type = "add", content = "new line", new_lineno = 2 },
        { type = "context", content = "line three", old_lineno = 3, new_lineno = 3 },
      },
    },
  },
}

local session = {
  comments = {
    {
      id = "1",
      file = "test.lua",
      side = "new",
      start_line = 2,
      end_line = 2,
      text = "Fix this\nplease",
      created_at = 0,
      updated_at = 0,
    },
    {
      id = "2",
      file = "test.lua",
      side = "new",
      start_line = 1,
      end_line = 2,
      text = "これは日本語の長いコメントです。マルチバイト文字が表示幅で正しく折り返されることを確認します。"
        .. "さらに長くしてラップを強制します。",
      created_at = 0,
      updated_at = 0,
    },
    {
      id = "3",
      file = "test.lua",
      side = "old",
      start_line = 2,
      end_line = 2,
      text = "comment on the base side",
      created_at = 0,
      updated_at = 0,
    },
  },
}

-- Two windows for old/new panes
vim.cmd("vsplit")
local wins = vim.api.nvim_tabpage_list_wins(0)
split.render_file(session, file, wins[1], wins[2])

local new_bufnr = vim.fn.bufnr("reviewthem://new")
local old_bufnr = vim.fn.bufnr("reviewthem://old")
check(new_bufnr ~= -1, "new diff buffer exists")
check(old_bufnr ~= -1, "old diff buffer exists")

local new_blocks = comment_block_marks(new_bufnr)
local old_blocks = comment_block_marks(old_bufnr)

check(#new_blocks == 1, "one comment block on the new pane (both new-side comments share the anchor)")
check(#old_blocks == 1, "one comment block on the old pane (the base-side comment)")

local mark = new_blocks[1]
-- Buffer layout: row 0 file header, row 1 hunk header, row 2 context L1, row 3 add L2
check(mark and mark.row == 3, "comment block anchored at the buffer row of new line 2")

-- Recompute the wrap width the renderer was given, so this tracks the window
-- instead of a hardcoded number that passes trivially.
local win_width = vim.api.nvim_win_get_width(wins[2])
local wrap_width = math.max(20, math.min(80, win_width - 10))

local max_text_width = 0
for _, text in ipairs(mark and mark.lines or {}) do
  local body = text:match("│ (.*)$")
  if body then
    max_text_width = math.max(max_text_width, vim.api.nvim_strwidth(body))
  end
end
local joined = table.concat(mark and mark.lines or {}, "\n")

check(joined:find("💬 L1%-2") ~= nil, "range header rendered for multi-line comment (L1-2)")
check(joined:find("💬 L2") ~= nil, "header rendered for single-line comment (L2)")
check(joined:find("│ Fix this", 1, true) ~= nil, "first line of multi-line comment rendered")
check(joined:find("│ please", 1, true) ~= nil, "second line of multi-line comment rendered")
check(joined:find("日本語", 1, true) ~= nil, "multibyte comment text rendered")

local header_count = select(2, joined:gsub("┌─", ""))
local footer_count = select(2, joined:gsub("└─", ""))
check(header_count == 2 and footer_count == 2, "two stacked comment blocks rendered")

local first_pos = joined:find("💬 L1%-2")
local second_pos = joined:find("💬 L2%f[%D]")
check(first_pos ~= nil and second_pos ~= nil and first_pos < second_pos, "blocks sorted by start_line")
check(
  max_text_width <= wrap_width,
  string.format("wrapped text stays within the wrap width (got %d, limit %d)", max_text_width, wrap_width)
)

-- Japanese comment is wider than the wrap width, so it must have wrapped
local body_line_count = select(2, joined:gsub("│ ", ""))
check(body_line_count >= 4, "long multibyte comment wrapped onto multiple lines")

-- The panes are scrollbind/cursorbind'ed, so each row must occupy the same
-- number of screen rows on both sides or the split view drifts apart.
local old_heights = virt_line_heights(old_bufnr)
local new_heights = virt_line_heights(new_bufnr)
local misaligned_row = nil
for row in pairs(vim.tbl_extend("force", old_heights, new_heights)) do
  if (old_heights[row] or 0) ~= (new_heights[row] or 0) then
    misaligned_row = row
  end
end
check(
  misaligned_row == nil,
  "both panes have equal virtual line height on every row"
    .. (misaligned_row and (" (row " .. misaligned_row .. " differs)") or "")
)
check(next(old_heights) ~= nil and next(new_heights) ~= nil, "alignment fillers added on both panes")

-- Tabs and non-UTF-8 bytes: the measured width must match the drawn text and no
-- byte may be dropped while wrapping.
local scratch = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "anchor" })

--- Render one comment on a scratch buffer and return its text lines.
---@param text string
---@param max_width number
---@return string[]
local function render_body(text, max_width)
  vim.api.nvim_buf_clear_namespace(scratch, renderer.get_namespace(), 0, -1)
  renderer.add_inline_comments(scratch, 0, {
    { id = "x", file = "f", side = "new", start_line = 1, end_line = 1, text = text },
  }, "*", max_width)
  local body = {}
  for _, m in ipairs(virt_line_marks(scratch)) do
    for _, line in ipairs(m.lines) do
      local line_body = line:match("│ (.*)$")
      if line_body then
        table.insert(body, line_body)
      end
    end
  end
  return body
end

local tab_body = render_body("a\tb", 40)
check(#tab_body == 1 and tab_body[1] == "a    b", "tab expanded to spaces instead of forcing a line break")

local raw_text = "0123456789\255" .. "0123456789"
local raw_body = render_body(raw_text, 8)
-- Neovim draws a byte that is not valid UTF-8 as <ff> in virtual text; what
-- matters here is that wrap_line does not silently swallow it.
local raw_expected = (raw_text:gsub("\255", "<ff>"))
check(#raw_body > 1, "a line longer than the wrap width is split")
check(table.concat(raw_body, "") == raw_expected, "wrapping keeps bytes that are not valid UTF-8")

-- A UTF-8 continuation byte at the very start of a line cannot be matched by
-- the wrap iterator's pattern; it must still be kept, not dropped.
local lead_text = "\128" .. "0123456789" .. "0123456789"
local lead_body = render_body(lead_text, 8)
local lead_expected = (lead_text:gsub("\128", "<80>"))
check(#lead_body > 1, "a line starting with a continuation byte is split when too long")
check(
  table.concat(lead_body, "") == lead_expected,
  "wrapping keeps a continuation byte at the start of a line"
)

-- Control chars are drawn caret-notated (^X, two cells) in virt_lines but
-- nvim_strwidth measures the raw char as one cell; they must be normalized so
-- wrapped lines do not overflow the wrap width.
local esc_body = render_body("abc\27def", 40)
check(#esc_body == 1 and esc_body[1] == "abc^[def", "control char rendered in literal caret notation")
local ctrl_body = render_body(string.rep("\27x", 20), 20)
local ctrl_max = 0
for _, line in ipairs(ctrl_body) do
  ctrl_max = math.max(ctrl_max, vim.api.nvim_strwidth(line))
end
check(
  #ctrl_body > 1 and ctrl_max <= 20,
  string.format("control-char text wraps within the wrap width (got %d, limit 20)", ctrl_max)
)

-- VimResized fires globally: refreshing while another tabpage is current must
-- still wrap to the pane width, not fall back to the full screen width.
vim.cmd("tabnew")
split.refresh_decorations(session)
local tab_max = 0
for _, m in ipairs(comment_block_marks(new_bufnr)) do
  for _, text in ipairs(m.lines) do
    local body = text:match("│ (.*)$")
    if body then
      tab_max = math.max(tab_max, vim.api.nvim_strwidth(body))
    end
  end
end
check(
  tab_max > 0 and tab_max <= wrap_width,
  string.format("refresh from another tabpage keeps the pane wrap width (got %d, limit %d)", tab_max, wrap_width)
)
vim.cmd("tabclose")

-- A range whose end_line is not a rendered lineno (e.g. saved by an older
-- version that overshot the hunk) must still display, anchored at the last
-- rendered line of the range.
local overshoot_session = {
  comments = {
    {
      id = "o1",
      file = "test.lua",
      side = "new",
      start_line = 2,
      end_line = 5,
      text = "range overshoots the hunk",
      created_at = 0,
      updated_at = 0,
    },
  },
}
split.refresh_decorations(overshoot_session)
local overshoot_blocks = comment_block_marks(new_bufnr)
check(#overshoot_blocks == 1, "comment whose end_line is beyond the hunk still renders a block")
-- Buffer layout: row 4 is context line new_lineno=3, the last rendered line in range 2-5
check(
  overshoot_blocks[1] and overshoot_blocks[1].row == 4,
  "overshooting range anchors at the last rendered line of the range"
)

-- Toggle off: no virt_lines should be produced on either pane
require("reviewthem.config").setup({ inline_comments = false })
split.refresh_decorations(session)
check(#virt_line_marks(new_bufnr) == 0, "no virt_lines on the new pane when inline_comments = false")
check(#virt_line_marks(old_bufnr) == 0, "no virt_lines on the old pane when inline_comments = false")

-- Avoid the accidental-close guard firing on exit in this headless harness
split.set_closing_intentionally()

if failures > 0 then
  print(failures .. " check(s) failed")
  os.exit(1)
end
print("all checks passed")
