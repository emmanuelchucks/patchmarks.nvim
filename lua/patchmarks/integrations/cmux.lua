local M = {}

local function system(args)
  local result = vim.system(args, { text = true }):wait()
  if result.code ~= 0 then
    local err = vim.trim(result.stderr or result.stdout or "")
    return nil, err ~= "" and err or ("command failed: " .. table.concat(args, " "))
  end

  return result.stdout or ""
end

local function decode_json(output)
  local ok, decoded = pcall(vim.json.decode, output)
  if not ok then
    return nil, "invalid cmux JSON output"
  end
  return decoded
end

local function selected_surface_for_other_pane(workspace_ref, current_pane_ref)
  local output, err = system({ "cmux", "--json", "list-panes", "--workspace", workspace_ref })
  if output == nil then
    return nil, err
  end

  local data
  data, err = decode_json(output)
  if data == nil then
    return nil, err
  end

  local others = {}
  for _, pane in ipairs(data.panes or {}) do
    if pane.ref ~= current_pane_ref then
      others[#others + 1] = pane
    end
  end

  if #others == 0 then
    return nil, "no other cmux pane found in current workspace"
  end
  if #others > 1 then
    return nil, "multiple other cmux panes found; configure a custom handoff target"
  end

  local surface_ref = others[1].selected_surface_ref
  if surface_ref == nil or surface_ref == "" then
    return nil, "other cmux pane has no selected surface"
  end

  return surface_ref
end

function M.paste_to_other_pane(text, opts)
  opts = opts or {}

  if vim.fn.executable("cmux") ~= 1 then
    vim.notify("Patchmarks: cmux executable not found", vim.log.levels.ERROR)
    return false
  end

  local output, err = system({ "cmux", "identify", "--json" })
  if output == nil then
    vim.notify("Patchmarks: cmux identify failed: " .. err, vim.log.levels.ERROR)
    return false
  end

  local identity
  identity, err = decode_json(output)
  if identity == nil then
    vim.notify("Patchmarks: " .. err, vim.log.levels.ERROR)
    return false
  end

  local caller = identity.caller or identity.focused or {}
  local workspace_ref = opts.workspace or caller.workspace_ref
  local current_pane_ref = caller.pane_ref
  if workspace_ref == nil or current_pane_ref == nil then
    vim.notify("Patchmarks: not running inside a cmux terminal", vim.log.levels.ERROR)
    return false
  end

  local target_surface = opts.surface
  if target_surface == nil then
    target_surface, err = selected_surface_for_other_pane(workspace_ref, current_pane_ref)
    if target_surface == nil then
      vim.notify("Patchmarks: " .. err, vim.log.levels.ERROR)
      return false
    end
  end

  local paste_text = opts.prefix and (opts.prefix .. text) or text
  if opts.suffix then
    paste_text = paste_text .. opts.suffix
  end

  local delivery = opts.delivery or (opts.submit == true and "file" or "paste")
  if delivery == "file" then
    local path = opts.path
    local display_path = opts.display_path
    if path == nil then
      local git_dir_result = vim.system({ "git", "rev-parse", "--git-dir" }, { text = true }):wait()
      if git_dir_result.code == 0 then
        local git_dir = vim.trim(git_dir_result.stdout or "")
        if not vim.startswith(git_dir, "/") then
          git_dir = vim.fs.joinpath(vim.fn.getcwd(), git_dir)
        end
        local dir = vim.fs.joinpath(git_dir, "patchmarks")
        vim.fn.mkdir(dir, "p")
        path = vim.fs.joinpath(dir, "handoff.md")
        display_path = display_path or ".git/patchmarks/handoff.md"
      else
        path = vim.fn.tempname() .. ".md"
        display_path = display_path or path
      end
    end

    local ok, write_err = pcall(vim.fn.writefile, vim.split(text, "\n", { plain = true }), path)
    if not ok or write_err ~= 0 then
      vim.notify(
        "Patchmarks: failed to write handoff file: " .. tostring(write_err),
        vim.log.levels.ERROR
      )
      return false
    end

    paste_text = opts.message or string.format("patchmarks: %s", display_path or path)
  end

  local _, set_err = system({ "cmux", "set-buffer", paste_text })
  if set_err ~= nil then
    vim.notify("Patchmarks: cmux set-buffer failed: " .. set_err, vim.log.levels.ERROR)
    return false
  end

  local _, paste_err = system({
    "cmux",
    "paste-buffer",
    "--workspace",
    workspace_ref,
    "--surface",
    target_surface,
  })
  if paste_err ~= nil then
    vim.notify("Patchmarks: cmux paste-buffer failed: " .. paste_err, vim.log.levels.ERROR)
    return false
  end

  if opts.submit == true then
    local _, submit_err = system({
      "cmux",
      "send-key",
      "--workspace",
      workspace_ref,
      "--surface",
      target_surface,
      "Enter",
    })
    if submit_err ~= nil then
      vim.notify("Patchmarks: cmux submit failed: " .. submit_err, vim.log.levels.ERROR)
      return false
    end
  end

  vim.notify("Patchmarks: handed off review to cmux " .. target_surface, vim.log.levels.INFO)
  return true
end

return M
