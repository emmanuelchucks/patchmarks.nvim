local M = {}

function M.bootstrap()
  vim.opt.runtimepath:prepend(vim.uv.cwd())
end

function M.new_harness(name)
  local failures = {}

  local function fail(msg)
    failures[#failures + 1] = msg
  end

  local function expect(condition, msg)
    if not condition then
      fail(msg)
    end
  end

  local function expect_eq(actual, expected, msg)
    if actual ~= expected then
      fail(string.format("%s: expected %s, got %s", msg, vim.inspect(expected), vim.inspect(actual)))
    end
  end

  local function finish()
    if #failures > 0 then
      error(table.concat(failures, "\n"))
    end

    print(string.format("%s: ok", name))
  end

  return {
    fail = fail,
    expect = expect,
    expect_eq = expect_eq,
    finish = finish,
  }
end

function M.git(cwd, ...)
  local args = { ... }
  local result = vim.system(vim.list_extend({ "git" }, args), {
    cwd = cwd,
    text = true,
  }):wait()

  if result.code ~= 0 then
    error(string.format("git failed (%s): %s", table.concat(args, " "), result.stderr))
  end

  return result.stdout or ""
end

function M.write_file(path, lines)
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  local payload = table.concat(lines, "\n") .. "\n"
  assert(vim.uv.fs_write(fd, payload, 0))
  assert(vim.uv.fs_close(fd))
end

function M.mkdirp(path)
  vim.fn.mkdir(path, "p")
end

function M.decode_json(path)
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

function M.realpath(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

return M
