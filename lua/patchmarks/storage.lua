local git = require("patchmarks.git")

local M = {}

local function read_json(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  local raw = table.concat(vim.fn.readfile(path), "\n")
  if raw == "" then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok then
    return nil
  end

  return decoded
end

local function to_session(repo_root, data)
  if type(data) ~= "table" or type(data.files) ~= "table" then
    return nil
  end

  local files = {}
  for path, entry in pairs(data.files) do
    files[#files + 1] = {
      path = path,
      kind = entry.kind or "modified",
      quickfix_status = entry.status or entry.quickfix_status or "M",
      index = entry.index or #files + 1,
      absolute_path = entry.absolute_path or vim.fs.joinpath(repo_root, path),
      first_changed_line = entry.first_changed_line or 1,
      stale = entry.stale or false,
      annotations = vim.deepcopy(entry.annotations or {}),
    }
  end

  table.sort(files, function(a, b)
    return (a.index or math.huge) < (b.index or math.huge)
  end)

  return {
    version = data.version or 1,
    repo_root = repo_root,
    repo_name = data.repo_name or vim.fs.basename(repo_root),
    created_at = data.created_at,
    exported_at = data.exported_at,
    exported_change_key = data.exported_change_key,
    change_key = data.change_key or "",
    next_annotation_seq = data.next_annotation_seq or 1,
    files = files,
  }
end

function M.path(repo_root)
  return git.git_path(repo_root, "patchmarks/current.json")
end

function M.load(repo_root)
  local path = M.path(repo_root)
  if path == nil then
    return nil
  end

  return to_session(repo_root, read_json(path))
end

function M.save(session)
  local path = M.path(session.repo_root)
  if path == nil then
    return false
  end

  vim.fn.mkdir(vim.fs.dirname(path), "p")

  local files = {}
  for _, file in ipairs(session.files) do
    files[file.path] = {
      status = file.quickfix_status,
      kind = file.kind,
      index = file.index,
      first_changed_line = file.first_changed_line,
      stale = file.stale or false,
      absolute_path = file.absolute_path,
      annotations = vim.deepcopy(file.annotations),
    }
  end

  local payload = vim.json.encode({
    version = session.version or 1,
    repo_name = session.repo_name,
    created_at = session.created_at,
    exported_at = session.exported_at,
    exported_change_key = session.exported_change_key,
    change_key = session.change_key or "",
    next_annotation_seq = session.next_annotation_seq,
    files = files,
  })

  vim.fn.writefile({ payload }, path)
  return true
end

function M.delete(repo_root)
  local path = M.path(repo_root)
  if path == nil or vim.fn.filereadable(path) == 0 then
    return false
  end

  return vim.fn.delete(path) == 0
end

return M
