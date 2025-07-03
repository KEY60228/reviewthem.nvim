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

  local state = require("reviewthem.state")
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

-- Show review status using telescope
M.show_status = function()
  local ok, telescope = pcall(require, "telescope")
  if not ok then
    vim.notify("Telescope not available", vim.log.levels.ERROR)
    return
  end

  local state = require("reviewthem.state")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local base, compare = state.get_review_branches()
  local files = state.get_diff_files()
  if #files == 0 then
    vim.notify("No files in the current review session.", vim.log.levels.INFO)
    return
  end

  local file_list = {}

  for _, file in ipairs(files) do
    local reviewed = state.is_file_reviewed(file)
    local status = reviewed and "[✓]" or "[ ]"
    table.insert(file_list, {
      display = string.format("%s %s", status, file),
      file = file,
      reviewed = reviewed,
    })
  end

  pickers.new({}, {
    prompt_title = string.format("Review Status: %s...%s", base, compare or "Working Directory"),
    finder = finders.new_table({
      results = file_list,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.file,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        -- Do nothing on Enter key - just close the picker
        actions.close(prompt_bufnr)
      end)

      -- Add toggle reviewed mapping
      map("i", "<C-t>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          if selection.value.reviewed then
            state.unmark_file_reviewed(selection.value.file)
          else
            state.mark_file_reviewed(selection.value.file)
          end

          -- Update the entry in file_list
          for _, entry in ipairs(file_list) do
            if entry.file == selection.value.file then
              entry.reviewed = not entry.reviewed
              local status = entry.reviewed and "[✓]" or "[ ]"
              entry.display = string.format("%s %s", status, entry.file)
              break
            end
          end

          -- Refresh picker
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          current_picker:refresh(finders.new_table({
            results = file_list,
            entry_maker = function(entry)
              return {
                value = entry,
                display = entry.display,
                ordinal = entry.file,
              }
            end,
          }), {})
        end
      end)

      return true
    end,
  }):find()
end

return M

