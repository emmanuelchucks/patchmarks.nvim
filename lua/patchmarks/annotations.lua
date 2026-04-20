local editor = require("patchmarks.editor")
local preview = require("patchmarks.preview")
local render = require("patchmarks.render")
local session = require("patchmarks.session")
local storage = require("patchmarks.storage")

local M = {}

local function current_session()
  return session.get()
end

local function current_file()
  local current = current_session()
  if current == nil then
    return nil, nil
  end

  return current, session.file_for_buf(current, 0)
end

local function read_excerpt(file, start_lnum, end_lnum)
  local bufnr = vim.fn.bufnr(file.absolute_path, false)
  local lines

  if bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) then
    lines = vim.api.nvim_buf_get_lines(bufnr, start_lnum - 1, end_lnum, false)
  else
    lines = vim.fn.readfile(file.absolute_path)
    lines = vim.list_slice(lines, start_lnum, end_lnum)
  end

  return vim.trim(table.concat(lines, " ")):sub(1, 200)
end

local function visual_range()
  local start = vim.fn.line("v")
  local finish = vim.api.nvim_win_get_cursor(0)[1]
  if start > finish then
    start, finish = finish, start
  end

  return start, finish
end

local function current_range()
  local mode = vim.api.nvim_get_mode().mode
  if mode:match("[vV\22]") then
    local start_lnum, end_lnum = visual_range()
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
    return start_lnum, end_lnum
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  return line, line
end

local function annotation_title(file, start_lnum, end_lnum)
  return string.format("Patchmarks: %s:%d-%d", file.path, start_lnum, end_lnum)
end

local function sort_annotations(file)
  table.sort(file.annotations, function(a, b)
    if a.start_lnum == b.start_lnum then
      return a.end_lnum < b.end_lnum
    end

    return a.start_lnum < b.start_lnum
  end)
end

local function overlapping_annotation(file, start_lnum, end_lnum, ignore_id)
  for _, annotation in ipairs(file.annotations) do
    if
      annotation.id ~= ignore_id
      and start_lnum <= annotation.end_lnum
      and end_lnum >= annotation.start_lnum
    then
      return annotation
    end
  end

  return nil
end

local function annotation_at_line(file, line)
  for _, annotation in ipairs(file.annotations) do
    if annotation.start_lnum <= line and line <= annotation.end_lnum then
      return annotation
    end
  end

  return nil
end

local function open_preview_for_annotation(file, annotation)
  return preview.open({
    title = string.format("%s:%d-%d", file.path, annotation.start_lnum, annotation.end_lnum),
    body = annotation.body,
    source_winid = vim.api.nvim_get_current_win(),
    key = string.format("%s:%s", file.path, annotation.id),
  })
end

local function refresh_views(current)
  local preferred_path = nil
  if editor.state ~= nil and vim.api.nvim_win_is_valid(editor.state.source_winid) then
    local source_buf = vim.api.nvim_win_get_buf(editor.state.source_winid)
    local source_path = vim.api.nvim_buf_get_name(source_buf)
    if source_path ~= "" then
      preferred_path = vim.uv.fs_realpath(source_path) or vim.fs.normalize(source_path)
    end
  end

  session.touch(current)
  storage.save(current)
  if preferred_path == nil then
    local current_path = vim.api.nvim_buf_get_name(0)
    if current_path ~= "" then
      preferred_path = vim.uv.fs_realpath(current_path) or vim.fs.normalize(current_path)
    end
  end

  require("patchmarks.review").refresh_quickfix(current, preferred_path)
  render.render_buffer(0)
end

local function remove_annotation(file, annotation_id)
  for index, candidate in ipairs(file.annotations) do
    if candidate.id == annotation_id then
      table.remove(file.annotations, index)
      return true
    end
  end

  return false
end

local function save_annotation(file, start_lnum, end_lnum, body, existing)
  local current = current_session()
  if current == nil then
    return {
      outcome = "cancelled",
      annotation = existing,
    }
  end

  if vim.trim(body) == "" then
    if existing ~= nil then
      if vim.fn.confirm("Delete annotation?", "&Yes\n&No", 2) ~= 1 then
        return {
          outcome = "cancelled",
          annotation = existing,
        }
      end

      remove_annotation(file, existing.id)
      refresh_views(current)
      return {
        outcome = "deleted",
        annotation = nil,
      }
    end

    return {
      outcome = "noop",
      annotation = nil,
    }
  end

  local overlapping =
    overlapping_annotation(file, start_lnum, end_lnum, existing and existing.id or nil)
  if overlapping ~= nil then
    overlapping.start_lnum = start_lnum
    overlapping.end_lnum = end_lnum
    overlapping.body = body
    overlapping.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
    overlapping.excerpt = read_excerpt(file, start_lnum, end_lnum)
    sort_annotations(file)
    refresh_views(current)
    return {
      outcome = "saved",
      annotation = overlapping,
    }
  end

  local annotation = existing
    or {
      id = session.next_annotation_id(current),
      created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

  annotation.start_lnum = start_lnum
  annotation.end_lnum = end_lnum
  annotation.body = body
  annotation.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  annotation.excerpt = read_excerpt(file, start_lnum, end_lnum)

  if existing == nil then
    file.annotations[#file.annotations + 1] = annotation
  end

  sort_annotations(file)
  refresh_views(current)
  return {
    outcome = "saved",
    annotation = annotation,
  }
end

function M.upsert(path, start_lnum, end_lnum, body, existing_id)
  local current = current_session()
  if current == nil then
    return nil
  end

  local file = session.find_file(current, path)
  if file == nil then
    return nil
  end

  local existing = nil
  if existing_id ~= nil then
    for _, annotation in ipairs(file.annotations) do
      if annotation.id == existing_id then
        existing = annotation
        break
      end
    end
  end

  local result = save_annotation(file, start_lnum, end_lnum, body, existing)
  return result and result.annotation or nil
end

function M.open_editor_for_range(file, start_lnum, end_lnum, existing)
  local context = {
    existing = existing,
  }

  editor.open({
    title = annotation_title(file, start_lnum, end_lnum),
    body = existing and existing.body or "",
    append_at_end = existing ~= nil,
    annotation_exists = existing ~= nil,
    on_save = function(body)
      local result = save_annotation(file, start_lnum, end_lnum, body, context.existing)
      context.existing = result and result.annotation or nil
      return result
    end,
  })
end

function M.add_current()
  local current, file = current_file()
  if current == nil or file == nil then
    vim.notify("Patchmarks: current buffer is not part of the active session", vim.log.levels.WARN)
    return
  end

  local start_lnum, end_lnum = current_range()
  local existing = overlapping_annotation(file, start_lnum, end_lnum, nil)
  M.open_editor_for_range(file, start_lnum, end_lnum, existing)
end

function M.edit_current()
  local _, file = current_file()
  if file == nil then
    vim.notify("Patchmarks: current buffer is not part of the active session", vim.log.levels.WARN)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local annotation = annotation_at_line(file, line)
  if annotation == nil then
    vim.notify("Patchmarks: no annotation under cursor", vim.log.levels.INFO)
    return
  end

  M.open_editor_for_range(file, annotation.start_lnum, annotation.end_lnum, annotation)
end

function M.delete_current()
  local current, file = current_file()
  if current == nil or file == nil then
    vim.notify("Patchmarks: current buffer is not part of the active session", vim.log.levels.WARN)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local annotation = annotation_at_line(file, line)
  if annotation == nil then
    vim.notify("Patchmarks: no annotation under cursor", vim.log.levels.INFO)
    return
  end

  remove_annotation(file, annotation.id)
  refresh_views(current)
end

function M.preview_current()
  local _, file = current_file()
  if file == nil then
    vim.notify("Patchmarks: current buffer is not part of the active session", vim.log.levels.WARN)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local annotation = annotation_at_line(file, line)
  if annotation == nil then
    vim.notify("Patchmarks: no annotation under cursor", vim.log.levels.INFO)
    return
  end

  open_preview_for_annotation(file, annotation)
end

function M.cursorhold_preview()
  if editor.is_open() then
    return
  end

  local _, file = current_file()
  if file == nil then
    preview.close()
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local annotation = annotation_at_line(file, line)
  if annotation == nil then
    preview.close()
    return
  end

  open_preview_for_annotation(file, annotation)
end

local function jump(direction)
  local _, file = current_file()
  if file == nil or #file.annotations == 0 then
    vim.notify("Patchmarks: no annotations in current file", vim.log.levels.INFO)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  if direction == "next" then
    for _, annotation in ipairs(file.annotations) do
      if annotation.start_lnum > line then
        vim.api.nvim_win_set_cursor(0, { annotation.start_lnum, 0 })
        return
      end
    end
  else
    for index = #file.annotations, 1, -1 do
      local annotation = file.annotations[index]
      if annotation.end_lnum < line then
        vim.api.nvim_win_set_cursor(0, { annotation.start_lnum, 0 })
        return
      end
    end
  end

  vim.notify("Patchmarks: no annotation in that direction", vim.log.levels.INFO)
end

function M.next_in_file()
  jump("next")
end

function M.prev_in_file()
  jump("prev")
end

function M.annotations_for_path(path)
  local current = current_session()
  if current == nil then
    return {}
  end

  local file = session.find_file(current, path)
  return file and file.annotations or {}
end

return M
