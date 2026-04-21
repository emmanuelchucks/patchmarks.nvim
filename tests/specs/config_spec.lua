return function()
  local H = require("tests.support.helpers")
  H.bootstrap()

  local T = H.new_harness("config_spec")
  local annotations = require("patchmarks.annotations")
  local config = require("patchmarks.config")
  local patchmarks = require("patchmarks")
  local preview = require("patchmarks.preview")

  local function setup_repo()
    local tmp = vim.fn.tempname()
    H.mkdirp(tmp)

    H.git(tmp, "init", "-q")
    H.git(tmp, "config", "user.name", "Patchmarks Test")
    H.git(tmp, "config", "user.email", "patchmarks@example.com")

    H.write_file(vim.fs.joinpath(tmp, "tracked.txt"), { "alpha", "beta", "gamma" })
    H.git(tmp, "add", "tracked.txt")
    H.git(tmp, "commit", "-qm", "init")

    H.write_file(vim.fs.joinpath(tmp, "tracked.txt"), { "alpha", "BETA", "gamma" })
    return tmp
  end

  local function edit_tracked(repo)
    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(repo, "tracked.txt")))
  end

  local function save_editor(body)
    local state = require("patchmarks.editor").state
    T.expect(state ~= nil, "editor should be open")
    if state == nil then
      error("editor should be open")
    end

    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, vim.split(body, "\n", { plain = true }))
    vim.cmd("wq")
  end

  local function run_setup_and_cursorhold_preview_test()
    config.reset()
    local applied = patchmarks.setup({
      preview = {
        trigger = "cursorhold",
        width = 50,
        height = 4,
      },
    })

    T.expect_eq(applied.preview.trigger, "cursorhold", "setup should apply preview trigger")
    T.expect_eq(applied.preview.width, 50, "setup should apply preview width")
    T.expect_eq(applied.preview.height, 4, "setup should apply preview height")

    local repo = setup_repo()
    vim.cmd.cd(repo)
    edit_tracked(repo)

    T.expect(patchmarks.start() == true, "PatchmarksStart should succeed for cursorhold preview")
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.add_current()
    save_editor("Hover note.")

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_exec_autocmds("CursorHold", { buffer = 0 })
    T.expect(preview.is_open(), "CursorHold should open preview on annotated line")
    T.expect(preview.state ~= nil, "preview state should exist after CursorHold")
    T.expect_eq(
      vim.api.nvim_win_get_width(preview.state.winid),
      50,
      "CursorHold preview should use configured width"
    )
    T.expect_eq(
      vim.api.nvim_win_get_height(preview.state.winid),
      4,
      "CursorHold preview should use configured height"
    )

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_exec_autocmds("CursorHold", { buffer = 0 })
    T.expect(not preview.is_open(), "CursorHold on a plain line should close preview")

    patchmarks.setup({})
    local current = config.get()
    T.expect_eq(
      current.preview.trigger,
      "manual",
      "setup with empty opts should restore default trigger"
    )
    T.expect_eq(current.preview.width, 72, "setup with empty opts should restore default width")
    T.expect_eq(current.preview.height, 6, "setup with empty opts should restore default height")
  end

  run_setup_and_cursorhold_preview_test()
  T.finish()
end
