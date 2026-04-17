local float = require("patchmarks.float")

local M = {
  state = nil,
}

local augroup = vim.api.nvim_create_augroup("PatchmarksEditor", { clear = false })
local editor_seq = 0

local function trim_trailing_blank(lines)
  local last = #lines
  while last > 0 and vim.trim(lines[last]) == "" do
    last = last - 1
  end

  if last == 0 then
    return {}
  end

  return vim.list_slice(lines, 1, last)
end

local function close()
  if M.state == nil then
    return
  end

  local state = M.state
  M.state = nil

  if vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end

  if vim.api.nvim_win_is_valid(state.source_winid) then
    local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(state.source_winid))
    local row = math.min(state.source_cursor[1], math.max(line_count, 1))
    local col = state.source_cursor[2]
    vim.api.nvim_set_current_win(state.source_winid)
    vim.api.nvim_win_set_cursor(state.source_winid, { row, col })
  end
end

local function editor_body(bufnr)
  local lines = trim_trailing_blank(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  return table.concat(lines, "\n")
end

local function save()
  if M.state == nil then
    return false
  end

  local body = editor_body(M.state.bufnr)
  local result = M.state.on_save(body) or { outcome = "saved", annotation = body ~= "" }
  if result.outcome == "cancelled" then
    return false
  end

  M.state.original_body = result.annotation and body or ""
  M.state.annotation_exists = result.annotation ~= nil
  if vim.api.nvim_buf_is_valid(M.state.bufnr) then
    vim.bo[M.state.bufnr].modified = false
  end

  return result.outcome
end

local function save_and_close()
  if save() then
    close()
  end
end

local function sync_modified_state(bufnr)
  if M.state == nil or M.state.bufnr ~= bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local body = editor_body(bufnr)
  local is_empty = vim.trim(body) == ""
  local modified
  if is_empty then
    modified = M.state.annotation_exists
  else
    modified = body ~= M.state.original_body
  end
  vim.bo[bufnr].modified = modified
end

local function apply_empty_semantics_on_quit(bufnr)
  if M.state == nil or M.state.bufnr ~= bufnr then
    return
  end

  local body = editor_body(bufnr)
  if vim.trim(body) ~= "" then
    return
  end

  if vim.api.nvim_buf_is_valid(bufnr) then
    M.state.original_body = ""
    vim.bo[bufnr].modified = false
  end
end

local function place_cursor_for_open(winid, lines, append)
  if append and #lines > 0 then
    vim.api.nvim_win_set_cursor(winid, { #lines, #lines[#lines] })
    vim.cmd("startinsert!")
    return
  end

  vim.api.nvim_win_set_cursor(winid, { 1, 0 })
  vim.cmd.startinsert()
end

function M.is_open()
  return M.state ~= nil
end

function M.has_unsaved_changes()
  return M.state ~= nil and vim.api.nvim_buf_is_valid(M.state.bufnr) and vim.bo[M.state.bufnr].modified
end

function M.request_close(reason)
  if M.state == nil then
    return true
  end

  if not M.has_unsaved_changes() then
    close()
    return true
  end

  local answer = vim.fn.confirm(
    string.format("Discard unsaved annotation edits before %s?", reason or "continuing"),
    "&Yes\n&No",
    2
  )

  if answer ~= 1 then
    return false
  end

  close()
  return true
end

function M.save_current()
  return save()
end

function M.open(opts)
  close()

  local source_winid = vim.api.nvim_get_current_win()
  local width = 72
  local height = 8
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(bufnr, true, float.window_opts(source_winid, width, height, {
    title = opts.title,
    title_pos = "center",
  }))

  local lines = vim.split(opts.body or "", "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end

  editor_seq = editor_seq + 1
  vim.api.nvim_buf_set_name(bufnr, string.format("patchmarks://editor/%d", editor_seq))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].modifiable = true
  vim.wo[winid].winfixbuf = true
  vim.wo[winid].wrap = true
  vim.bo[bufnr].modified = false

  M.state = {
    bufnr = bufnr,
    winid = winid,
    source_winid = source_winid,
    source_cursor = vim.api.nvim_win_get_cursor(source_winid),
    original_body = opts.body or "",
    annotation_exists = opts.annotation_exists == true,
    on_save = opts.on_save,
  }

  local map_opts = { buffer = bufnr, nowait = true, silent = true }
  vim.keymap.set("n", "ZZ", save_and_close, map_opts)
  vim.keymap.set("n", "ZQ", function()
    close()
  end, map_opts)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      save()
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      sync_modified_state(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("QuitPre", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      apply_empty_semantics_on_quit(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      if M.state == nil then
        return
      end

      if M.state.bufnr == bufnr then
        M.state = nil
      end
    end,
  })

  sync_modified_state(bufnr)
  place_cursor_for_open(winid, lines, opts.append_at_end == true)
  return { bufnr = bufnr, winid = winid }
end

return M
