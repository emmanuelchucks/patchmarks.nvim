local handoff_file = require("patchmarks.integrations.handoff")

local M = {}

local function system(args, opts)
  opts = opts or {}
  local result = vim.system(args, { text = true, stdin = opts.stdin }):wait()
  if result.code ~= 0 then
    local err = vim.trim(result.stderr or result.stdout or "")
    return nil, err ~= "" and err or ("command failed: " .. table.concat(args, " "))
  end

  return result.stdout or ""
end

local function resolve_target(target)
  local output, err = system({ "tmux", "display-message", "-p", "-t", target, "#{pane_id}" })
  if output == nil then
    return nil, err
  end

  local pane_id = vim.trim(output)
  if pane_id == "" then
    return nil, "target did not resolve to a pane: " .. target
  end

  return pane_id, nil
end

local function load_buffer(name, text)
  local _, err = system({ "tmux", "load-buffer", "-b", name, "-" }, { stdin = text })
  return err
end

local function paste_buffer(name, target_pane)
  local _, err = system({
    "tmux",
    "paste-buffer",
    "-p",
    "-d",
    "-b",
    name,
    "-t",
    target_pane,
  })
  return err
end

local function submit(target_pane)
  local _, err = system({ "tmux", "send-keys", "-t", target_pane, "Enter" })
  return err
end

local function focus(target_pane)
  local _, window_err = system({ "tmux", "select-window", "-t", target_pane })
  if window_err ~= nil then
    return window_err
  end

  local _, pane_err = system({ "tmux", "select-pane", "-t", target_pane })
  return pane_err
end

function M.paste_to_pane(text, opts)
  opts = opts or {}

  if vim.fn.executable("tmux") ~= 1 then
    vim.notify("Patchmarks: tmux executable not found", vim.log.levels.ERROR)
    return false
  end

  if vim.env.TMUX == nil or vim.env.TMUX == "" then
    vim.notify("Patchmarks: not running inside tmux", vim.log.levels.ERROR)
    return false
  end

  local target = opts.target or "{last}"
  local target_pane, err = resolve_target(target)
  if target_pane == nil then
    vim.notify("Patchmarks: tmux target failed: " .. err, vim.log.levels.ERROR)
    return false
  end

  local paste_text = opts.prefix and (opts.prefix .. text) or text
  if opts.suffix then
    paste_text = paste_text .. opts.suffix
  end

  local delivery = opts.delivery or (opts.submit == true and "file" or "paste")
  if delivery == "file" then
    local written
    written, err = handoff_file.write_file(text, {
      path = opts.path,
      display_path = opts.display_path,
      repo_root = opts.repo_root,
    })
    if written == nil then
      vim.notify("Patchmarks: failed to write handoff file: " .. err, vim.log.levels.ERROR)
      return false
    end

    paste_text = opts.message or string.format("address review: %s", written.display_path)
  elseif delivery ~= "paste" then
    vim.notify("Patchmarks: invalid tmux delivery: " .. tostring(delivery), vim.log.levels.ERROR)
    return false
  end

  local buffer_name = opts.buffer_name or "patchmarks-handoff"
  err = load_buffer(buffer_name, paste_text)
  if err ~= nil then
    vim.notify("Patchmarks: tmux load-buffer failed: " .. err, vim.log.levels.ERROR)
    return false
  end

  err = paste_buffer(buffer_name, target_pane)
  if err ~= nil then
    vim.notify("Patchmarks: tmux paste-buffer failed: " .. err, vim.log.levels.ERROR)
    return false
  end

  if opts.submit == true then
    err = submit(target_pane)
    if err ~= nil then
      vim.notify("Patchmarks: tmux submit failed: " .. err, vim.log.levels.ERROR)
      return false
    end
  end

  if opts.focus == true then
    err = focus(target_pane)
    if err ~= nil then
      vim.notify("Patchmarks: tmux focus failed: " .. err, vim.log.levels.ERROR)
      return false
    end
  end

  vim.notify("Patchmarks: handed off review to tmux " .. target_pane, vim.log.levels.INFO)
  return true
end

return M
