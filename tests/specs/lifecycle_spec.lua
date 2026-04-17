return function()
  local H = require("tests.support.helpers")
  H.bootstrap()

  local T = H.new_harness("lifecycle_spec")
  local annotations = require("patchmarks.annotations")
  local editor = require("patchmarks.editor")
  local patchmarks = require("patchmarks")
  local session = require("patchmarks.session")
  local storage = require("patchmarks.storage")

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

  local function save_editor(body)
    local state = editor.state
    T.expect(state ~= nil, "editor should be open")
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, vim.split(body, "\n", { plain = true }))
    vim.cmd("wq")
  end

  local function run_session_command_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)

    T.expect(patchmarks.open() == true, "PatchmarksOpen should succeed")
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.add_current()
    save_editor("Persist me.")

    local current = session.get()
    local session_path = storage.path(current.repo_root)
    T.expect(vim.fn.filereadable(session_path) == 1, "session should be persisted")

    vim.b.patchmarks_saved_readonly = true
    vim.b.patchmarks_saved_modifiable = false
    vim.bo.readonly = true
    vim.bo.modifiable = false
    T.expect(patchmarks.close() == true, "PatchmarksClose should succeed")
    T.expect_eq(vim.b.patchmarks_review, nil, "close should remove review marker")
    T.expect_eq(vim.bo.modifiable, false, "close should restore original modifiable")
    T.expect_eq(vim.bo.readonly, true, "close should restore original readonly")

    local qf = vim.fn.getqflist({ winid = 1 })
    T.expect_eq(qf.winid, 0, "close should close quickfix window")
    T.expect(session.get() ~= nil, "close should keep session in memory")

    T.expect(patchmarks.open() == true, "PatchmarksOpen should reopen persisted session")
    current = session.get()
    T.expect_eq(current.annotation_count, 1, "reopen should preserve annotations")

    T.expect(patchmarks.new() == true, "PatchmarksNew should start a new round")
    current = session.get()
    T.expect_eq(current.annotation_count, 0, "new round should discard old annotations")
    local persisted = H.decode_json(session_path)
    T.expect_eq(#persisted.files["tracked.txt"].annotations, 0, "new round should persist cleared annotations")

    T.expect(patchmarks.discard() == true, "PatchmarksDiscard should succeed")
    T.expect_eq(session.get(), nil, "discard should clear current session")
    T.expect(vim.fn.filereadable(session_path) == 0, "discard should delete session file")
  end

  local function run_autorefresh_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)

    T.expect(patchmarks.open() == true, "PatchmarksOpen should succeed for autorefresh")
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    H.write_file(vim.fs.joinpath(repo, "second.txt"), { "one", "two" })

    vim.api.nvim_exec_autocmds("FocusGained", {})
    local refreshed = vim.wait(500, function()
      local qf = vim.fn.getqflist({ size = 1 })
      return qf.size == 2
    end, 50)

    T.expect(refreshed, "autorefresh should pick up new changed files")
    T.expect_eq(vim.api.nvim_win_get_cursor(0)[1], 3, "autorefresh should preserve cursor position in current file")
  end

  local function run_dirty_editor_guard_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)

    T.expect(patchmarks.open() == true, "PatchmarksOpen should succeed for dirty-editor guard")
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.add_current()
    local state = editor.state
    T.expect(state ~= nil, "editor should open")
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, { "Unsaved draft" })

    local original_confirm = vim.fn.confirm
    vim.fn.confirm = function()
      return 2
    end
    T.expect_eq(patchmarks.close(), false, "PatchmarksClose should abort when unsaved editor close is declined")
    vim.fn.confirm = original_confirm

    T.expect(editor.is_open(), "editor should remain open after declining close")
    T.expect(session.get() ~= nil, "session should remain active after declining close")

    vim.fn.confirm = function()
      return 1
    end
    T.expect_eq(patchmarks.close(), true, "PatchmarksClose should proceed when unsaved editor discard is accepted")
    vim.fn.confirm = original_confirm
    T.expect(not editor.is_open(), "editor should close after accepted discard")
  end

  run_session_command_test()
  run_autorefresh_test()
  run_dirty_editor_guard_test()
  T.finish()
end
