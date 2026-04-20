local config = require("patchmarks.config")
local float = require("patchmarks.float")

---@class Patchmarks.PreviewState
---@field bufnr integer
---@field winid integer
---@field augroup integer
---@field key string?

local M = {
  ---@type Patchmarks.PreviewState?
  state = nil,
}

local function close()
  local state = M.state
  if state == nil then
    return
  end

  M.state = nil

  pcall(vim.api.nvim_del_augroup_by_id, state.augroup)

  if vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
end

function M.close()
  close()
end

function M.is_open()
  return M.state ~= nil
end

function M.open(opts)
  if
    M.state ~= nil
    and M.state.key ~= nil
    and M.state.key == opts.key
    and vim.api.nvim_win_is_valid(M.state.winid)
  then
    return {
      bufnr = M.state.bufnr,
      winid = M.state.winid,
    }
  end

  close()

  local preview_config = config.get().preview
  local source_winid = opts.source_winid or vim.api.nvim_get_current_win()
  local width = opts.width or preview_config.width
  local height = opts.height or preview_config.height
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(
    bufnr,
    false,
    float.window_opts(source_winid, width, height, {
      title = opts.title,
      title_pos = "center",
      focusable = false,
    })
  )

  local lines = vim.split(opts.body or "", "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.wo[winid].wrap = true
  vim.wo[winid].winfixbuf = true

  local preview_group =
    vim.api.nvim_create_augroup(string.format("PatchmarksPreview%d", bufnr), { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "WinLeave" }, {
    group = preview_group,
    callback = function()
      close()
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = preview_group,
    buffer = bufnr,
    callback = function()
      if M.state ~= nil and M.state.bufnr == bufnr then
        M.state = nil
      end
    end,
  })

  M.state = {
    bufnr = bufnr,
    winid = winid,
    augroup = preview_group,
    key = opts.key,
  }

  return { bufnr = bufnr, winid = winid }
end

return M
