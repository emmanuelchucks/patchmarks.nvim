return function()
  local H = require("tests.support.helpers")
  H.bootstrap()

  local T = H.new_harness("preview_export_spec")
  local annotations = require("patchmarks.annotations")
  local editor = require("patchmarks.editor")
  local exporter = require("patchmarks.export")
  local patchmarks = require("patchmarks")
  local preview = require("patchmarks.preview")
  local session = require("patchmarks.session")

  local function setup_repo()
    local tmp = vim.fn.tempname()
    H.mkdirp(tmp)

    H.git(tmp, "init", "-q")
    H.git(tmp, "config", "user.name", "Patchmarks Test")
    H.git(tmp, "config", "user.email", "patchmarks@example.com")

    H.write_file(vim.fs.joinpath(tmp, "alpha.txt"), { "one", "two", "three" })
    H.write_file(vim.fs.joinpath(tmp, "beta.txt"), { "red", "blue", "green" })
    H.git(tmp, "add", "alpha.txt", "beta.txt")
    H.git(tmp, "commit", "-qm", "init")

    H.write_file(vim.fs.joinpath(tmp, "alpha.txt"), { "one", "TWO", "three" })
    H.write_file(vim.fs.joinpath(tmp, "beta.txt"), { "red", "blue", "GREEN" })
    return tmp
  end

  local function save_editor(body)
    local state = editor.state
    T.expect(state ~= nil, "editor should be open")
    if state == nil then
      error("editor should be open")
    end

    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, vim.split(body, "\n", { plain = true }))
    vim.cmd("wq")
  end

  local function run_preview_and_export_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)

    T.expect(patchmarks.open() == true, "PatchmarksOpen should succeed")

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.add_current()
    save_editor("Tighten this naming.")

    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(repo, "beta.txt")))
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    annotations.add_current()
    save_editor("Double-check the semantics here.")

    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(repo, "alpha.txt")))
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.preview_current()
    T.expect(preview.is_open(), "preview should open for annotation under cursor")
    T.expect(preview.state ~= nil, "preview state should be tracked")
    if preview.state == nil then
      error("preview state should be tracked")
    end

    local preview_lines = vim.api.nvim_buf_get_lines(preview.state.bufnr, 0, -1, false)
    T.expect_eq(
      table.concat(preview_lines, "\n"),
      "Tighten this naming.",
      "preview should show annotation body"
    )

    vim.cmd("normal! k")
    vim.api.nvim_exec_autocmds("CursorMoved", {})
    T.expect(not preview.is_open(), "preview should close on cursor move")

    local text = exporter.export_current()
    T.expect(text ~= nil, "export should produce text")
    if text == nil then
      error("export should produce text")
    end

    T.expect(text:match("PATCHMARKS REVIEW"), "export header should be present")
    T.expect(text:match("%[alpha.txt:2%-2%]"), "alpha annotation should be exported")
    T.expect(text:match("%[beta.txt:3%-3%]"), "beta annotation should be exported")
    T.expect_eq(vim.fn.getreg('"'), text, "unnamed register should receive export")

    local current = session.get()
    if current == nil then
      error("session should exist after export")
    end

    T.expect(current.exported_at ~= nil, "session should record exported_at")
  end

  local function run_editor_append_and_empty_export_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)

    T.expect(patchmarks.open() == true, "PatchmarksOpen should succeed for append test")

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.add_current()
    save_editor("First line.\nSecond line.")

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.edit_current()
    T.expect(editor.state ~= nil, "editor should open for edit")
    local cursor = vim.api.nvim_win_get_cursor(editor.state.winid)
    T.expect_eq(cursor[1], 2, "edit cursor should start on last line")
    T.expect_eq(cursor[2], #"Second line.", "edit cursor should start at end of last line")
    vim.cmd("normal! ZQ")

    vim.fn.setreg('"', "sentinel")
    annotations.delete_current()
    local exported = exporter.export_current()
    T.expect_eq(exported, nil, "empty export should return nil")
    T.expect_eq(
      vim.fn.getreg('"'),
      "sentinel",
      "empty export should not overwrite unnamed register"
    )
  end

  run_preview_and_export_test()
  run_editor_append_and_empty_export_test()
  T.finish()
end
