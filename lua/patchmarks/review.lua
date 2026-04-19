local config = require("patchmarks.config")
local keymaps = require("patchmarks.keymaps")
local preview = require("patchmarks.preview")
local render = require("patchmarks.render")

local M = {}

local augroup = vim.api.nvim_create_augroup("PatchmarksReview", { clear = true })

local function notification(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Patchmarks" })
end

local function quickfix_title(session)
  return string.format(
    "Patchmarks: %s (%d files, %d notes)",
    session.repo_name,
    #session.files,
    session.annotation_count or 0
  )
end

local function quickfix_label(file)
  return string.format("[%s] %s (%d)", file.quickfix_status, file.path, #file.annotations)
end

local function in_session(session, path)
  if not path or path == "" then
    return false
  end

  return session.paths[vim.fs.normalize(path)] ~= nil
end

function M.apply_review_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if vim.b[bufnr].patchmarks_saved_modifiable == nil then
    vim.b[bufnr].patchmarks_saved_modifiable = vim.bo[bufnr].modifiable
  end

  if vim.b[bufnr].patchmarks_saved_readonly == nil then
    vim.b[bufnr].patchmarks_saved_readonly = vim.bo[bufnr].readonly
  end

  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
  vim.b[bufnr].patchmarks_review = true
  keymaps.apply(bufnr)
  render.render_buffer(bufnr)
end

function M.attach(session)
  vim.api.nvim_clear_autocmds({
    group = augroup,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if in_session(session, path) then
        M.apply_review_buffer(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("CursorHold", {
    group = augroup,
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if not in_session(session, path) then
        preview.close()
        return
      end

      if config.get().preview.trigger ~= "cursorhold" then
        return
      end

      require("patchmarks.annotations").cursorhold_preview()
    end,
  })
end

function M.release_review_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  render.clear_buffer(bufnr)
  keymaps.clear(bufnr)

  local saved_readonly = vim.b[bufnr].patchmarks_saved_readonly
  local saved_modifiable = vim.b[bufnr].patchmarks_saved_modifiable

  if saved_readonly ~= nil then
    vim.bo[bufnr].readonly = saved_readonly
  end

  if saved_modifiable ~= nil then
    vim.bo[bufnr].modifiable = saved_modifiable
  end

  vim.b[bufnr].patchmarks_review = nil
  vim.b[bufnr].patchmarks_saved_readonly = nil
  vim.b[bufnr].patchmarks_saved_modifiable = nil
end

function M.close(session)
  vim.api.nvim_clear_autocmds({ group = augroup })
  local editor = require("patchmarks.editor")

  if not editor.request_close("closing Patchmarks") then
    return false
  end

  preview.close()

  if session ~= nil then
    for _, file in ipairs(session.files) do
      local bufnr = vim.fn.bufnr(file.absolute_path, false)
      if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
        M.release_review_buffer(bufnr)
      end
    end
  end

  pcall(vim.cmd, "cclose")
  return true
end

local function current_quickfix_path()
  local index = vim.fn.getqflist({ idx = 0 }).idx or 0
  if index <= 0 then
    return nil
  end

  local items = vim.fn.getqflist()
  local item = items[index]
  if item == nil then
    return nil
  end

  if item.bufnr ~= nil and item.bufnr > 0 and vim.api.nvim_buf_is_valid(item.bufnr) then
    local path = vim.api.nvim_buf_get_name(item.bufnr)
    if path ~= "" then
      return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
    end
  end

  if item.filename ~= nil and item.filename ~= "" then
    return vim.uv.fs_realpath(item.filename) or vim.fs.normalize(item.filename)
  end

  return nil
end

function M.refresh_quickfix(session, preferred_path)
  if #session.files == 0 then
    notification("no changed files")
    return 0
  end

  local items = {}
  session.paths = {}
  preferred_path = preferred_path
    or (function()
      local current_path = vim.api.nvim_buf_get_name(0)
      if current_path ~= "" then
        return vim.uv.fs_realpath(current_path) or vim.fs.normalize(current_path)
      end

      return current_quickfix_path()
    end)()
  local preferred_index = 1

  for index, file in ipairs(session.files) do
    session.paths[file.absolute_path] = true
    items[#items + 1] = {
      filename = file.absolute_path,
      lnum = file.first_changed_line,
      col = 1,
      text = quickfix_label(file),
      user_data = {
        path = file.path,
        status = file.quickfix_status,
      },
    }

    if preferred_path ~= nil and file.absolute_path == preferred_path then
      preferred_index = index
    end
  end

  vim.fn.setqflist({}, "r", {
    title = quickfix_title(session),
    items = items,
    idx = preferred_index,
  })

  return preferred_index
end

function M.open(session, opts)
  opts = opts or {}

  local preferred_path = opts.preferred_path
  local preferred_cursor = opts.preferred_cursor
  local index = M.refresh_quickfix(session, preferred_path)
  if index == 0 then
    return false
  end

  local file = session.files[index]
  vim.cmd.edit(vim.fn.fnameescape(file.absolute_path))
  local target_cursor = { file.first_changed_line, 0 }
  if preferred_path ~= nil and preferred_cursor ~= nil and file.absolute_path == preferred_path then
    local max_line = math.max(vim.api.nvim_buf_line_count(0), 1)
    target_cursor = {
      math.min(preferred_cursor[1], max_line),
      preferred_cursor[2],
    }
  end

  vim.api.nvim_win_set_cursor(0, target_cursor)
  M.apply_review_buffer(0)
  vim.cmd("botright copen")
  vim.cmd("wincmd p")
  M.attach(session)

  return true
end

return M
