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

local function attach_current(current)
  review.attach(current)
  review.attach_buffer(current, vim.api.nvim_get_current_buf())
  return true
end

function M.start()
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
  return attach_current(current)
end

function M.refresh()
  local repo_root = active_repo_root()
  if repo_root == nil or repo_root == "" then
    notification("no active Patchmarks repository", vim.log.levels.ERROR)
    return false
  end

  local current = build_session(git.build_snapshot(repo_root), load_previous(repo_root))
  session.set(current)
  storage.save(current)
  review.refresh_files(current)

  return attach_current(current)
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

  return attach_current(current)
end

function M.stop()
  local current = session.get()
  if current == nil then
    notification("no active Patchmarks session", vim.log.levels.INFO)
    return false
  end

  return review.close(current)
end

function M.files()
  local current = session.get()
  if current == nil then
    notification("no active Patchmarks session", vim.log.levels.INFO)
    return false
  end

  return review.open_files(current)
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

function M.handoff()
  local text = export.export_current()
  if text == nil then
    return false
  end

  local current = session.get()
  local export_config = config.get().export or {}
  if export_config.handoff == nil then
    notification("no export.handoff configured", vim.log.levels.WARN)
    return false
  end

  local ok, result = pcall(export_config.handoff, {
    text = text,
    session = current,
    repo_root = current and current.repo_root or nil,
    repo_name = current and current.repo_name or nil,
  })

  if not ok then
    notification("handoff failed: " .. tostring(result), vim.log.levels.ERROR)
    return false
  end

  if result == false then
    notification("handoff failed", vim.log.levels.ERROR)
    return false
  end

  if export_config.stop_after_handoff ~= false then
    return M.stop()
  end

  notification("handoff complete")
  return true
end

function M.setup(opts)
  return config.setup(opts)
end

function M.config()
  return config.get()
end

return M
