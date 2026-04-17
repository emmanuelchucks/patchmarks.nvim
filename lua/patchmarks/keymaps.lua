local M = {}

local mappings = {
  { { "n", "x" }, "<localleader>a" },
  { "n", "<localleader>e" },
  { "n", "<localleader>d" },
  { "n", "<localleader>p" },
  { "n", "<localleader>x" },
  { "n", "<localleader>r" },
  { "n", "<localleader>R" },
  { "n", "]a" },
  { "n", "[a" },
}

function M.apply(bufnr)
  if vim.b[bufnr].patchmarks_keymaps_applied then
    return
  end

  local opts = { buffer = bufnr, silent = true, nowait = true }
  local annotations = require("patchmarks.annotations")

  vim.keymap.set({ "n", "x" }, "<localleader>a", annotations.add_current, opts)
  vim.keymap.set("n", "<localleader>e", annotations.edit_current, opts)
  vim.keymap.set("n", "<localleader>d", annotations.delete_current, opts)
  vim.keymap.set("n", "<localleader>p", annotations.preview_current, opts)
  vim.keymap.set("n", "<localleader>x", function()
    require("patchmarks.export").export_current()
  end, opts)
  vim.keymap.set("n", "<localleader>r", function()
    require("patchmarks").refresh()
  end, opts)
  vim.keymap.set("n", "<localleader>R", function()
    require("patchmarks").new()
  end, opts)
  vim.keymap.set("n", "]a", annotations.next_in_file, opts)
  vim.keymap.set("n", "[a", annotations.prev_in_file, opts)

  vim.b[bufnr].patchmarks_keymaps_applied = true
end

function M.clear(bufnr)
  for _, mapping in ipairs(mappings) do
    pcall(vim.keymap.del, mapping[1], mapping[2], { buffer = bufnr })
  end

  vim.b[bufnr].patchmarks_keymaps_applied = nil
end

return M
