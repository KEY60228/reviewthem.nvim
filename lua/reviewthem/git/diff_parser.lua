local M = {}

--- Parse a unified diff hunk header.
---@param line string
---@return number, number, number, number, string|nil  old_start, old_count, new_start, new_count, header
M.parse_hunk_header = function(line)
  local old_start, old_count, new_start, new_count =
    line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if not old_start then
    return 0, 0, 0, 0, nil
  end
  old_start = tonumber(old_start)
  old_count = tonumber(old_count) or 1
  new_start = tonumber(new_start)
  new_count = tonumber(new_count) or 1
  return old_start, old_count, new_start, new_count, line
end

--- Parse unified diff output lines into Hunk structures.
---@param diff_lines string[]
---@return Hunk[]
M.parse = function(diff_lines)
  local hunks = {}
  local current_hunk = nil
  local old_lineno, new_lineno

  for _, line in ipairs(diff_lines) do
    if line:match("^@@") then
      -- New hunk
      if current_hunk then
        table.insert(hunks, current_hunk)
      end

      local old_start, old_count, new_start, new_count, header = M.parse_hunk_header(line)
      if header then
        current_hunk = {
          header = header,
          old_start = old_start,
          old_count = old_count,
          new_start = new_start,
          new_count = new_count,
          lines = {},
        }
        old_lineno = old_start
        new_lineno = new_start
      end
    elseif current_hunk then
      if line:sub(1, 1) == "+" then
        table.insert(current_hunk.lines, {
          type = "add",
          content = line:sub(2),
          old_lineno = nil,
          new_lineno = new_lineno,
        })
        new_lineno = new_lineno + 1
      elseif line:sub(1, 1) == "-" then
        table.insert(current_hunk.lines, {
          type = "remove",
          content = line:sub(2),
          old_lineno = old_lineno,
          new_lineno = nil,
        })
        old_lineno = old_lineno + 1
      elseif line:sub(1, 1) == " " then
        table.insert(current_hunk.lines, {
          type = "context",
          content = line:sub(2),
          old_lineno = old_lineno,
          new_lineno = new_lineno,
        })
        old_lineno = old_lineno + 1
        new_lineno = new_lineno + 1
      elseif line:match("^\\ No newline at end of file") then
        -- Skip this marker
      end
    end
    -- Skip diff headers (diff --git, index, ---, +++)
  end

  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  return hunks
end

--- Extract the diff hunk text around a specific line for output context.
---@param hunks Hunk[]
---@param side "old"|"new"
---@param line_number number
---@return string|nil
M.get_hunk_context = function(hunks, side, line_number)
  for _, hunk in ipairs(hunks) do
    for _, hline in ipairs(hunk.lines) do
      local lineno = side == "new" and hline.new_lineno or hline.old_lineno
      if lineno == line_number then
        -- Found the line, return the whole hunk as text
        local parts = { hunk.header }
        for _, l in ipairs(hunk.lines) do
          local prefix
          if l.type == "add" then
            prefix = "+"
          elseif l.type == "remove" then
            prefix = "-"
          else
            prefix = " "
          end
          table.insert(parts, prefix .. l.content)
        end
        return table.concat(parts, "\n")
      end
    end
  end
  return nil
end

return M
