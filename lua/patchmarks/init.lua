local config = require("patchmarks.config")
local git = require("patchmarks.git")
local review = require("patchmarks.review")
local session = require("patchmarks.session")
local export = require("patchmarks.export")
local storage = require("patchmarks.storage")

local M = {}

local function notification(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Patchmarks" })
end

local function load_previous(repo_root)
  local active = session.get()
  return (active ~= nil and active.repo_root == repo_root) and active or storage.load(repo_root)
end

local function build_session(snapshot, previous)
  if previous ~= nil then
    session.touch(previous)
  end
  return session.new_from_snapshot(snapshot, previous)
end

local function active_repo_root()
  local current = session.get()
  if current ~= nil then
    return current.repo_root
  end

  return git.repo_root(vim.uv.cwd())
end

function M.open()
  local repo_root = git.repo_root(vim.uv.cwd())
  if repo_root == nil or repo_root == "" then
    notification("not in a Git repository", vim.log.levels.ERROR)
    return false
  end

  local snapshot = git.build_snapshot(repo_root)
  local previous = load_previous(repo_root)
  if
    previous ~= nil
    and previous.exported_at ~= nil
    and previous.exported_change_key ~= snapshot.change_key
  then
    previous = nil
    notification("Git changes detected since last export; started a new review round")
  end

  local current = build_session(snapshot, previous)
  session.set(current)
  storage.save(current)
  return review.open(current)
end

function M.refresh()
  local repo_root = active_repo_root()
  if repo_root == nil or repo_root == "" then
    notification("no active Patchmarks repository", vim.log.levels.ERROR)
    return false
  end

  local current_path = vim.api.nvim_buf_get_name(0)
  local current_cursor = vim.api.nvim_win_get_cursor(0)
  local current = build_session(git.build_snapshot(repo_root), load_previous(repo_root))
  session.set(current)
  storage.save(current)

  return review.open(current, {
    preferred_path = current_path ~= "" and (vim.uv.fs_realpath(current_path) or vim.fs.normalize(
      current_path
    )) or nil,
    preferred_cursor = current_cursor,
  })
end

function M.new()
  local repo_root = git.repo_root(vim.uv.cwd())
  if repo_root == nil or repo_root == "" then
    notification("not in a Git repository", vim.log.levels.ERROR)
    return false
  end

  if not review.close(session.get()) then
    return false
  end

  local current = build_session(git.build_snapshot(repo_root), nil)
  session.set(current)
  storage.save(current)

  return review.open(current)
end

function M.close()
  local current = session.get()
  if current == nil then
    notification("no active Patchmarks session", vim.log.levels.INFO)
    return false
  end

  return review.close(current)
end

function M.discard()
  local repo_root = active_repo_root()
  if repo_root == nil or repo_root == "" then
    notification("no active Patchmarks repository", vim.log.levels.INFO)
    return false
  end

  if not review.close(session.get()) then
    return false
  end
  storage.delete(repo_root)
  session.clear()
  notification("discarded Patchmarks session")
  return true
end

function M.export()
  return export.export_current()
end

function M.setup(opts)
  return config.setup(opts)
end

function M.config()
  return config.get()
end

return M
