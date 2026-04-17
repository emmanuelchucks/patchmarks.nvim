local editor = require("patchmarks.editor")
local session = require("patchmarks.session")

local M = {}

local augroup = vim.api.nvim_create_augroup("PatchmarksLifecycle", { clear = true })
local timer = nil
local busy = false
local enabled = false

local function ensure_timer()
  if timer == nil then
    timer = vim.uv.new_timer()
  end

  return timer
end

local function stop_timer()
  if timer ~= nil then
    timer:stop()
  end
end

local function can_refresh()
  return enabled and not busy and session.get() ~= nil and not editor.is_open()
end

function M.schedule_refresh()
  if not can_refresh() then
    return
  end

  ensure_timer():stop()
  timer:start(150, 0, vim.schedule_wrap(function()
    if not can_refresh() then
      return
    end

    busy = true
    pcall(require("patchmarks").refresh)
    busy = false
  end))
end

function M.attach()
  enabled = true

  vim.api.nvim_clear_autocmds({ group = augroup })
  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "WinEnter" }, {
    group = augroup,
    callback = function()
      M.schedule_refresh()
    end,
  })
end

function M.detach()
  enabled = false
  stop_timer()
  vim.api.nvim_clear_autocmds({ group = augroup })
end

return M
