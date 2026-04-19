local session = require("patchmarks.session")
local storage = require("patchmarks.storage")

local M = {}

local function annotated_files(current)
  local files = {}
  for _, file in ipairs(current.files) do
    if #file.annotations > 0 then
      files[#files + 1] = file
    end
  end

  return files
end

function M.build_text(current)
  local files = annotated_files(current)
  local lines = {
    "PATCHMARKS REVIEW",
    string.format("repo: %s", current.repo_name),
    string.format("files: %d", #files),
    string.format("notes: %d", current.annotation_count or 0),
    "",
  }

  for _, file in ipairs(files) do
    for _, annotation in ipairs(file.annotations) do
      lines[#lines + 1] = string.format("[%s:%d-%d]", file.path, annotation.start_lnum, annotation.end_lnum)
      lines[#lines + 1] = annotation.body
      lines[#lines + 1] = ""
    end
  end

  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end

  return table.concat(lines, "\n")
end

function M.annotation_file_count(current)
  return #annotated_files(current)
end

function M.write_registers(text)
  vim.fn.setreg('"', text)

  for _, reg in ipairs({ "+", "*" }) do
    pcall(vim.fn.setreg, reg, text)
  end
end

function M.export_current()
  local current = session.get()
  if current == nil then
    vim.notify("Patchmarks: no active session", vim.log.levels.WARN)
    return nil
  end

  if (current.annotation_count or 0) == 0 or M.annotation_file_count(current) == 0 then
    vim.notify("Patchmarks: no annotations to export", vim.log.levels.INFO)
    return nil
  end

  local text = M.build_text(current)
  M.write_registers(text)
  current.exported_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  current.exported_change_key = current.change_key or ""
  storage.save(current)
  vim.notify("Patchmarks: exported review to registers", vim.log.levels.INFO)
  return text
end

return M
