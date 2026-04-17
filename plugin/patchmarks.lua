if vim.g.loaded_patchmarks ~= nil then
  return
end

vim.g.loaded_patchmarks = 1

vim.api.nvim_create_user_command("PatchmarksOpen", function()
  require("patchmarks").open()
end, {
  desc = "Open a Patchmarks review session",
})

vim.api.nvim_create_user_command("PatchmarksRefresh", function()
  require("patchmarks").refresh()
end, {
  desc = "Refresh the active Patchmarks review session",
})

vim.api.nvim_create_user_command("PatchmarksNew", function()
  require("patchmarks").new()
end, {
  desc = "Start a fresh Patchmarks review round",
})

vim.api.nvim_create_user_command("PatchmarksClose", function()
  require("patchmarks").close()
end, {
  desc = "Close Patchmarks UI state and keep the session persisted",
})

vim.api.nvim_create_user_command("PatchmarksDiscard", function()
  require("patchmarks").discard()
end, {
  desc = "Discard the active Patchmarks session",
})

vim.api.nvim_create_user_command("PatchmarksExport", function()
  require("patchmarks").export()
end, {
  desc = "Export the active Patchmarks review session",
})
