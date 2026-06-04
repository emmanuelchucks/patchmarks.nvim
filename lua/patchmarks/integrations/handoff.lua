local git = require("patchmarks.git")

local M = {}

function M.active_repo_root(opts)
  opts = opts or {}
  if opts.repo_root ~= nil and opts.repo_root ~= "" then
    return opts.repo_root
  end

  local ok, session = pcall(require, "patchmarks.session")
  if ok then
    local current = session.get()
    if current ~= nil and current.repo_root ~= nil then
      return current.repo_root
    end
  end

  local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if result.code == 0 then
    return vim.trim(result.stdout or "")
  end

  return nil
end

local function default_display_path(repo_root, path)
  local cwd = vim.uv.fs_realpath(vim.fn.getcwd()) or vim.fs.normalize(vim.fn.getcwd())
  local real_repo_root = vim.uv.fs_realpath(repo_root) or vim.fs.normalize(repo_root)
  local default_path = vim.fs.joinpath(repo_root, ".git", "patchmarks", "handoff.md")
  local real_path = vim.uv.fs_realpath(path) or vim.fs.normalize(path)
  local real_default_path = vim.uv.fs_realpath(default_path) or vim.fs.normalize(default_path)

  if cwd == real_repo_root and real_path == real_default_path then
    return ".git/patchmarks/handoff.md"
  end

  return path
end

function M.write_file(text, opts)
  opts = opts or {}

  local path = opts.path
  local display_path = opts.display_path
  if path == nil then
    local repo_root = M.active_repo_root(opts)
    if repo_root ~= nil then
      path = git.git_path(repo_root, "patchmarks/handoff.md")
      if path ~= nil then
        vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
        display_path = display_path or default_display_path(repo_root, path)
      end
    end

    if path == nil then
      path = vim.fn.tempname() .. ".md"
      display_path = display_path or path
    end
  end

  local ok, write_err = pcall(vim.fn.writefile, vim.split(text, "\n", { plain = true }), path)
  if not ok or write_err ~= 0 then
    return nil, tostring(write_err)
  end

  return {
    path = path,
    display_path = display_path or path,
  }, nil
end

return M
