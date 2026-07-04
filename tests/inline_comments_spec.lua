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
  },
}

-- Two windows for old/new panes
vim.cmd("vsplit")
local wins = vim.api.nvim_tabpage_list_wins(0)
split.render_file(session, file, wins[1], wins[2])

local new_bufnr = vim.fn.bufnr("reviewthem://new")
check(new_bufnr ~= -1, "new diff buffer exists")

local extmarks = vim.api.nvim_buf_get_extmarks(new_bufnr, renderer.get_namespace(), 0, -1, { details = true })

local virt_lines_marks = {}
for _, mark in ipairs(extmarks) do
  if mark[4].virt_lines then
    table.insert(virt_lines_marks, mark)
  end
end

check(#virt_lines_marks == 1, "exactly one virt_lines extmark on the new buffer (both comments share the anchor)")

local mark = virt_lines_marks[1]
-- Buffer layout: row 0 file header, row 1 hunk header, row 2 context L1, row 3 add L2
check(mark and mark[2] == 3, "virt_lines anchored at the buffer row of new line 2")

local lines = {}
local max_text_width = 0
for _, vline in ipairs(mark and mark[4].virt_lines or {}) do
  local text = ""
  for _, chunk in ipairs(vline) do
    text = text .. chunk[1]
  end
  table.insert(lines, text)
  local body = text:match("│ (.*)$")
  if body then
    max_text_width = math.max(max_text_width, vim.fn.strdisplaywidth(body))
  end
end
local joined = table.concat(lines, "\n")

check(joined:find("💬 L1%-2") ~= nil, "range header rendered for multi-line comment (L1-2)")
check(joined:find("💬 L2") ~= nil, "header rendered for single-line comment (L2)")
check(joined:find("│ Fix this", 1, true) ~= nil, "first line of multi-line comment rendered")
check(joined:find("│ please", 1, true) ~= nil, "second line of multi-line comment rendered")
check(joined:find("日本語", 1, true) ~= nil, "multibyte comment text rendered")

local header_count = select(2, joined:gsub("┌─", ""))
local footer_count = select(2, joined:gsub("└─", ""))
check(header_count == 2 and footer_count == 2, "two stacked comment blocks rendered")

check(joined:find("💬 L1%-2") < joined:find("💬 L2%f[%D]"), "blocks sorted by start_line")
check(max_text_width <= 80, "wrapped text lines stay within max width (got " .. max_text_width .. ")")

-- Japanese comment is wider than any window here, so it must have wrapped
local body_line_count = select(2, joined:gsub("│ ", ""))
check(body_line_count >= 4, "long multibyte comment wrapped onto multiple lines")

-- Toggle off: no virt_lines should be produced
require("reviewthem.config").setup({ inline_comments = false })
split.refresh_decorations(session)
local extmarks_off = vim.api.nvim_buf_get_extmarks(new_bufnr, renderer.get_namespace(), 0, -1, { details = true })
local off_count = 0
for _, m in ipairs(extmarks_off) do
  if m[4].virt_lines then
    off_count = off_count + 1
  end
end
check(off_count == 0, "no virt_lines when inline_comments = false")

-- Avoid the accidental-close guard firing on exit in this headless harness
split.set_closing_intentionally()

if failures > 0 then
  print(failures .. " check(s) failed")
  os.exit(1)
end
print("all checks passed")
