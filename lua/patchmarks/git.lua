local M = {}

local function git(args, opts)
  opts = opts or {}

  local result = vim.system(vim.list_extend({ "git" }, args), {
    cwd = opts.cwd,
    text = true,
  }):wait()

  if result.code ~= 0 and not opts.allow_fail then
    local stderr = vim.trim(result.stderr or "")
    error(stderr ~= "" and stderr or ("git command failed: " .. table.concat(args, " ")))
  end

  return result
end

local function realpath(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function is_absolute(path)
  return path:match("^/") ~= nil or path:match("^%a:[/\\]") ~= nil
end

local function classify_xy(xy)
  if xy == "??" then
    return {
      include = true,
      kind = "untracked",
      quickfix_status = "??",
    }
  end

  if xy == "!!" then
    return {
      include = false,
    }
  end

  local x = xy:sub(1, 1)
  local y = xy:sub(2, 2)

  if x == "R" or y == "R" then
    return {
      include = true,
      kind = "renamed",
      consumes_next = true,
      quickfix_status = "R",
    }
  end

  if x == "C" or y == "C" then
    return {
      include = true,
      kind = "copied",
      consumes_next = true,
      quickfix_status = "C",
    }
  end

  if x == "D" or y == "D" then
    return {
      include = false,
    }
  end

  if x == "A" or y == "A" then
    return {
      include = true,
      kind = "added",
      quickfix_status = "A",
    }
  end

  if x == "M" or y == "M" or x == "T" or y == "T" or x == "U" or y == "U" then
    return {
      include = true,
      kind = "modified",
      quickfix_status = "M",
    }
  end

  return {
    include = false,
  }
end

local function parse_status_z(output)
  local files = {}
  local chunks = vim.split(output, "\0", { plain = true, trimempty = true })
  local i = 1

  while i <= #chunks do
    local chunk = chunks[i]
    local xy = chunk:sub(1, 2)
    local path = chunk:sub(4)
    local classification = classify_xy(xy)

    if classification.consumes_next then
      i = i + 1
    end

    if classification.include and path ~= "" then
      files[#files + 1] = {
        path = path,
        kind = classification.kind,
        quickfix_status = classification.quickfix_status,
        index = #files + 1,
      }
    end

    i = i + 1
  end

  return files
end

local function parse_first_changed_line(diff_text)
  for line in vim.gsplit(diff_text, "\n", { plain = true }) do
    if vim.startswith(line, "@@") then
      local new_start = line:match("%+(%d+)")
      if new_start ~= nil then
        local lnum = tonumber(new_start)
        if lnum == 0 then
          return 1
        end
        return lnum
      end
    end
  end

  return 1
end

local function read_file(path)
  local fd = vim.uv.fs_open(path, "r", 438)
  if fd == nil then
    return ""
  end

  local stat = vim.uv.fs_fstat(fd)
  local size = stat and stat.size or 0
  local content = size > 0 and (vim.uv.fs_read(fd, size, 0) or "") or ""
  vim.uv.fs_close(fd)
  return content
end

local function diff_text(repo_root, path)
  local result = git({ "diff", "--no-ext-diff", "--binary", "HEAD", "--", path }, {
    cwd = repo_root,
    allow_fail = true,
  })

  if result.code ~= 0 then
    return ""
  end

  return result.stdout or ""
end

local function build_change_key(repo_root, files, status_output)
  local parts = { status_output or "" }

  for _, file in ipairs(files) do
    parts[#parts + 1] = file.path
    parts[#parts + 1] = file.kind or ""

    if file.kind == "untracked" then
      parts[#parts + 1] = read_file(vim.fs.joinpath(repo_root, file.path))
    else
      parts[#parts + 1] = diff_text(repo_root, file.path)
    end
  end

  return vim.fn.sha256(table.concat(parts, "\0"))
end

function M.repo_root(cwd)
  local result = git({ "rev-parse", "--show-toplevel" }, {
    cwd = cwd,
    allow_fail = true,
  })

  if result.code ~= 0 then
    return nil
  end

  return realpath(vim.trim(result.stdout or ""))
end

function M.git_path(repo_root, suffix)
  local result = git({ "rev-parse", "--git-path", suffix }, {
    cwd = repo_root,
    allow_fail = true,
  })

  if result.code ~= 0 then
    return nil
  end

  local path = vim.trim(result.stdout or "")
  if path == "" then
    return nil
  end

  if is_absolute(path) then
    return realpath(path) or vim.fs.normalize(path)
  end

  return vim.fs.normalize(vim.fs.joinpath(repo_root, path))
end

function M.changed_files(repo_root)
  local result = git({ "status", "--porcelain=v1", "-z", "--untracked-files=all" }, {
    cwd = repo_root,
  })

  return parse_status_z(result.stdout or "")
end

function M.first_changed_line(repo_root, file)
  if file.kind == "untracked" then
    return 1
  end

  local result = git({ "diff", "--unified=0", "--no-ext-diff", "HEAD", "--", file.path }, {
    cwd = repo_root,
    allow_fail = true,
  })

  if result.code ~= 0 then
    return 1
  end

  return parse_first_changed_line(result.stdout or "")
end

function M.build_snapshot(repo_root)
  local repo_name = vim.fs.basename(repo_root)
  local status = git({ "status", "--porcelain=v1", "-z", "--untracked-files=all" }, {
    cwd = repo_root,
  })
  local files = parse_status_z(status.stdout or "")

  for _, file in ipairs(files) do
    file.first_changed_line = M.first_changed_line(repo_root, file)
    file.absolute_path = realpath(vim.fs.joinpath(repo_root, file.path))
  end

  return {
    repo_root = repo_root,
    repo_name = repo_name,
    files = files,
    annotation_count = 0,
    change_key = build_change_key(repo_root, files, status.stdout or ""),
  }
end

return M
