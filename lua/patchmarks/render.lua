local session = require("patchmarks.session")

local M = {}

M.ns = vim.api.nvim_create_namespace("patchmarks.annotations")

local function ensure_highlights()
  vim.api.nvim_set_hl(0, "PatchmarksRange", {
    link = "Visual",
    default = true,
  })
  vim.api.nvim_set_hl(0, "PatchmarksMarker", {
    link = "Comment",
    default = true,
  })
end

local function clamped_range(bufnr, annotation)
  local line_count = math.max(vim.api.nvim_buf_line_count(bufnr), 1)
  local start_lnum = math.floor(tonumber(annotation.start_lnum) or 1)
  local end_lnum = math.floor(tonumber(annotation.end_lnum) or start_lnum)

  if start_lnum > end_lnum then
    start_lnum, end_lnum = end_lnum, start_lnum
  end

  start_lnum = math.max(math.min(start_lnum, line_count), 1)
  end_lnum = math.max(math.min(end_lnum, line_count), start_lnum)

  annotation.start_lnum = start_lnum
  annotation.end_lnum = end_lnum

  return start_lnum, end_lnum
end

function M.render_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local current = session.get()
  if current == nil then
    return
  end

  ensure_highlights()
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)

  local file = session.file_for_buf(current, bufnr)
  if file == nil then
    return
  end

  for _, annotation in ipairs(file.annotations) do
    local start_lnum, end_lnum = clamped_range(bufnr, annotation)
    annotation.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, start_lnum - 1, 0, {
      end_row = end_lnum - 1,
      end_col = 0,
      right_gravity = false,
      end_right_gravity = true,
      invalidate = true,
      virt_text = { { " [pm]", "PatchmarksMarker" } },
      virt_text_pos = "eol",
    })

    for lnum = start_lnum, end_lnum do
      vim.api.nvim_buf_set_extmark(bufnr, M.ns, lnum - 1, 0, {
        line_hl_group = "PatchmarksRange",
        priority = 60,
      })
    end
  end
end

function M.clear_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
end

return M
