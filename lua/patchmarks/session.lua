local M = {
  current = nil,
}

local function now_utc()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function annotation_number(id)
  local suffix = tostring(id or ""):match("ann_(%d+)$")
  return tonumber(suffix) or 0
end

local function annotation_count(files)
  local total = 0

  for _, file in ipairs(files) do
    total = total + #file.annotations
  end

  return total
end

local function normalize_file(file)
  file.annotations = file.annotations or {}
  file.stale = file.stale or false
  file.note_count = #file.annotations
  file.first_changed_line = file.first_changed_line or 1
  file.quickfix_status = file.quickfix_status or "M"
  file.absolute_path = vim.uv.fs_realpath(file.absolute_path or "") or vim.fs.normalize(file.absolute_path or "")

  table.sort(file.annotations, function(a, b)
    if a.start_lnum == b.start_lnum then
      return a.end_lnum < b.end_lnum
    end

    return a.start_lnum < b.start_lnum
  end)
end

local function rebuild_indexes(session)
  session.paths = {}
  session.file_lookup = {}
  session.annotation_count = annotation_count(session.files)
  session.next_annotation_seq = session.next_annotation_seq or 1

  local max_seen = 0
  for index, file in ipairs(session.files) do
    file.index = index
    normalize_file(file)
    session.paths[file.absolute_path] = true
    session.file_lookup[file.path] = file

    for _, annotation in ipairs(file.annotations) do
      max_seen = math.max(max_seen, annotation_number(annotation.id))
    end
  end

  session.next_annotation_seq = math.max(session.next_annotation_seq, max_seen + 1)
end

local function clone_annotations(annotations)
  return vim.deepcopy(annotations or {})
end

local function stale_file(repo_root, previous)
  local first_line = previous.first_changed_line or 1
  if #previous.annotations > 0 then
    first_line = previous.annotations[1].start_lnum
  end

  return {
    path = previous.path,
    kind = previous.kind or "modified",
    quickfix_status = previous.quickfix_status or "M",
    index = previous.index or 999999,
    absolute_path = previous.absolute_path or vim.fs.joinpath(repo_root, previous.path),
    first_changed_line = first_line,
    annotations = clone_annotations(previous.annotations),
    stale = true,
  }
end

function M.new_from_snapshot(snapshot, previous)
  local files = {}
  local seen = {}

  for _, file in ipairs(snapshot.files) do
    local previous_file = previous and previous.file_lookup and previous.file_lookup[file.path] or nil
    files[#files + 1] = {
      path = file.path,
      kind = file.kind,
      quickfix_status = file.quickfix_status,
      index = file.index,
      absolute_path = file.absolute_path,
      first_changed_line = file.first_changed_line,
      annotations = clone_annotations(previous_file and previous_file.annotations or {}),
      stale = false,
    }
    seen[file.path] = true
  end

  if previous ~= nil then
    for _, file in ipairs(previous.files) do
      if not seen[file.path] and #file.annotations > 0 then
        files[#files + 1] = stale_file(snapshot.repo_root, file)
      end
    end
  end

  table.sort(files, function(a, b)
    local a_annotated = #a.annotations > 0
    local b_annotated = #b.annotations > 0
    if a_annotated ~= b_annotated then
      return a_annotated
    end

    return (a.index or math.huge) < (b.index or math.huge)
  end)

  local session = {
    version = 1,
    repo_root = snapshot.repo_root,
    repo_name = snapshot.repo_name,
    created_at = previous and previous.created_at or now_utc(),
    exported_at = previous and previous.exported_at or nil,
    next_annotation_seq = previous and previous.next_annotation_seq or 1,
    files = files,
  }

  rebuild_indexes(session)
  return session
end

function M.set(session)
  rebuild_indexes(session)
  M.current = session
end

function M.get()
  return M.current
end

function M.clear()
  M.current = nil
end

function M.find_file(session, path)
  if session == nil then
    return nil
  end

  return session.file_lookup[path]
end

function M.file_for_buf(session, bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return nil
  end

  local normalized = vim.uv.fs_realpath(path) or vim.fs.normalize(path)
  for _, file in ipairs(session.files) do
    if file.absolute_path == normalized then
      return file
    end
  end

  return nil
end

function M.next_annotation_id(session)
  local id = string.format("ann_%04d", session.next_annotation_seq)
  session.next_annotation_seq = session.next_annotation_seq + 1
  return id
end

function M.touch(session)
  rebuild_indexes(session)
end

return M
