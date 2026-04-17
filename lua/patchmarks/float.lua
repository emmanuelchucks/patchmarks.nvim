local M = {}

function M.position(source_winid, width, height)
  local cursor = vim.api.nvim_win_get_cursor(source_winid)
  local screenpos = vim.fn.screenpos(source_winid, cursor[1], cursor[2] + 1)
  local editor_row = math.max(screenpos.row - 1, 0)
  local editor_col = math.max(screenpos.col - 1, 0)
  local lines = vim.o.lines - vim.o.cmdheight
  local columns = vim.o.columns
  local border = 2
  local row = editor_row + 1

  if row + height + border > lines then
    row = math.max(editor_row - height - border, 0)
  end

  if row + height + border > lines then
    row = math.max(lines - height - border, 0)
  end

  local col = editor_col
  if col + width + border > columns then
    col = math.max(columns - width - border, 0)
  end

  return {
    row = row,
    col = col,
    source_row = editor_row,
    source_col = editor_col,
  }
end

function M.window_opts(source_winid, width, height, extra)
  local pos = M.position(source_winid, width, height)
  return vim.tbl_extend("force", {
    relative = "editor",
    row = pos.row,
    col = pos.col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  }, extra or {})
end

return M
