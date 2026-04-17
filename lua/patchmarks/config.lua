local M = {}

local defaults = {
  preview = {
    trigger = "manual",
    width = 72,
    height = 6,
  },
}

local values = vim.deepcopy(defaults)

local function normalize(opts)
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local preview = merged.preview or {}

  if preview.trigger ~= "manual" and preview.trigger ~= "cursorhold" then
    error("patchmarks: preview.trigger must be 'manual' or 'cursorhold'")
  end

  preview.width = math.max(1, math.floor(tonumber(preview.width) or defaults.preview.width))
  preview.height = math.max(1, math.floor(tonumber(preview.height) or defaults.preview.height))
  merged.preview = preview

  return merged
end

function M.setup(opts)
  values = normalize(opts)
  return M.get()
end

function M.get()
  return vim.deepcopy(values)
end

function M.reset()
  values = vim.deepcopy(defaults)
end

return M
