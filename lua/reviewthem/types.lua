---@class ReviewSession
---@field version number
---@field id string
---@field name string
---@field project_root string
---@field base_ref string|nil
---@field compare_ref string|nil
---@field created_at number
---@field updated_at number
---@field diff_files DiffFile[]
---@field comments Comment[]
---@field reviewed_files table<string, boolean>

---@class DiffFile
---@field path string
---@field status string
---@field hunks Hunk[]

---@class Hunk
---@field header string
---@field old_start number
---@field old_count number
---@field new_start number
---@field new_count number
---@field lines HunkLine[]

---@class HunkLine
---@field type "context"|"add"|"remove"
---@field content string
---@field old_lineno number|nil
---@field new_lineno number|nil

---@class Comment
---@field id string
---@field file string
---@field side "old"|"new"
---@field start_line number
---@field end_line number
---@field text string
---@field diff_hunk string|nil
---@field created_at number
---@field updated_at number

return {}
