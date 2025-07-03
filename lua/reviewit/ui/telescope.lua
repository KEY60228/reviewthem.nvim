local M = {}

-- Check if telescope is available
M.is_available = function()
  local ok, _ = pcall(require, "telescope")
  return ok
end

-- Show comments using telescope
M.show_comments = function()
  local ok, _ = pcall(require, "telescope")
  if not ok then
    vim.notify("Telescope not available", vim.log.levels.ERROR)
    return
  end

  local state = require("reviewit.state")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")

  local all_comments = state.get_comments()
  local comment_list = {}

  for file, file_comments in pairs(all_comments) do
    for _, comment in ipairs(file_comments) do
      local display
      if comment.line_start == comment.line_end then
        display = string.format("%s:%d - %s", file, comment.line_start, comment.text)
      else
        display = string.format("%s:%d-%d - %s", file, comment.line_start, comment.line_end, comment.text)
      end
      table.insert(comment_list, {
        display = display,
        file = file,
        line = comment.line_start,
        text = comment.text,
      })
    end
  end

  pickers.new({}, {
    prompt_title = "Review Comments",
    finder = finders.new_table({
      results = comment_list,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.display,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        -- Do nothing on Enter key - just close the picker
        actions.close(prompt_bufnr)
      end)
      return true
    end,
  }):find()
end

return M

