return function()
  local H = require("tests.support.helpers")
  H.bootstrap()

  local T = H.new_harness("review_session_spec")
  local annotations = require("patchmarks.annotations")
  local editor = require("patchmarks.editor")
  local patchmarks = require("patchmarks")
  local session = require("patchmarks.session")

  local function setup_repo()
    local tmp = vim.fn.tempname()
    H.mkdirp(tmp)

    H.git(tmp, "init", "-q")
    H.git(tmp, "config", "user.name", "Patchmarks Test")
    H.git(tmp, "config", "user.email", "patchmarks@example.com")

    H.write_file(vim.fs.joinpath(tmp, "tracked.txt"), { "alpha", "beta", "gamma" })
    H.write_file(vim.fs.joinpath(tmp, "rename_me.txt"), { "rename", "me" })
    H.write_file(vim.fs.joinpath(tmp, "delete_me.txt"), { "delete", "me" })
    H.git(tmp, "add", "tracked.txt", "rename_me.txt", "delete_me.txt")
    H.git(tmp, "commit", "-qm", "init")

    H.write_file(vim.fs.joinpath(tmp, "tracked.txt"), { "alpha", "beta changed", "gamma" })
    H.git(tmp, "mv", "rename_me.txt", "renamed.txt")
    H.write_file(vim.fs.joinpath(tmp, "renamed.txt"), { "rename", "me changed" })
    H.write_file(vim.fs.joinpath(tmp, "untracked.txt"), { "new", "file" })
    H.git(tmp, "rm", "-q", "delete_me.txt")

    return tmp
  end

  local function run_open_flow_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)

    local ok = patchmarks.open()
    T.expect(ok == true, "PatchmarksOpen should succeed in a git repo with changes")

    local current = H.require_value(session.get(), "session should be stored")
    T.expect_eq(current.repo_root, H.realpath(repo), "session repo_root")
    T.expect_eq(#current.files, 3, "should include modified, renamed, and untracked files only")
    T.expect_eq(
      current.files[1].path,
      "renamed.txt",
      "git order should be preserved with deleted file skipped"
    )

    local qf = vim.fn.getqflist({ title = 1, items = 1, idx = 1, size = 1, winid = 1 })
    T.expect(qf.winid > 0, "quickfix window should be open")
    T.expect_eq(qf.idx, 1, "quickfix should focus the first item")
    T.expect_eq(qf.size, 3, "quickfix item count")
    T.expect(qf.title:match("Patchmarks:"), "quickfix title should be set")
    T.expect_eq(qf.items[1].user_data.path, "renamed.txt", "quickfix user_data path")

    local current_path = vim.api.nvim_buf_get_name(0)
    T.expect_eq(
      current_path,
      vim.api.nvim_buf_get_name(qf.items[1].bufnr),
      "current buffer should match first quickfix item"
    )
    T.expect_eq(
      vim.api.nvim_win_get_cursor(0)[1],
      qf.items[1].lnum,
      "cursor should land on first changed line"
    )
    T.expect_eq(vim.bo.readonly, false, "session file buffer should remain writable")
    T.expect_eq(vim.bo.modifiable, true, "session file buffer should remain modifiable")
    T.expect_eq(vim.b.patchmarks_attached, true, "session file buffer should be attached")
  end

  local function run_buffer_eligibility_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)

    T.expect(patchmarks.open() == true, "PatchmarksOpen should succeed for eligibility test")
    T.expect_eq(vim.b.patchmarks_attached, true, "opened session file should be attached")

    H.write_file(vim.fs.joinpath(repo, "outside.txt"), { "not", "changed" })
    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(repo, "outside.txt")))
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
    T.expect_eq(vim.b.patchmarks_attached, nil, "non-session file should not be attached")
    T.expect_eq(
      vim.b.patchmarks_keymaps_applied,
      nil,
      "non-session file should not receive keymaps"
    )

    vim.cmd.enew()
    vim.bo.buftype = "nofile"
    vim.api.nvim_buf_set_name(0, vim.fs.joinpath(repo, "tracked.txt"))
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
    T.expect_eq(vim.b.patchmarks_attached, nil, "nofile buffer should not be attached")
    T.expect_eq(vim.b.patchmarks_keymaps_applied, nil, "nofile buffer should not receive keymaps")
  end

  local function run_refresh_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)

    patchmarks.open()
    H.write_file(vim.fs.joinpath(repo, "second_untracked.txt"), { "another", "file" })

    local ok = patchmarks.refresh()
    T.expect(ok == true, "PatchmarksRefresh should succeed for the active repo")

    local qf = vim.fn.getqflist({ items = 1, title = 1 })
    T.expect_eq(#qf.items, 4, "refresh should pick up newly changed files")
    T.expect(qf.title:match("%(4 files, 0 notes%)"), "refresh should update title counts")
  end

  local function run_quickfix_order_stability_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)

    T.expect(
      patchmarks.open() == true,
      "PatchmarksOpen should succeed for quickfix order stability"
    )
    local before = vim.tbl_map(function(item)
      return item.user_data.path
    end, vim.fn.getqflist())

    vim.cmd("cc 2")
    local selected_before_idx = vim.fn.getqflist({ idx = 0 }).idx
    T.expect_eq(
      selected_before_idx,
      2,
      "test should move quickfix selection to the second item before annotating"
    )
    T.expect_eq(
      vim.fs.basename(vim.api.nvim_buf_get_name(0)),
      "tracked.txt",
      "test should annotate a non-first quickfix item"
    )
    annotations.add_current()
    local state = H.require_value(editor.state, "editor should open for quickfix order stability")
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, { "Keep order stable." })
    vim.cmd("wq")

    local after_qf = vim.fn.getqflist()
    local after = vim.tbl_map(function(item)
      return item.user_data.path
    end, after_qf)
    T.expect_eq(
      table.concat(after, ","),
      table.concat(before, ","),
      "quickfix order should stay stable after annotation"
    )
    T.expect_eq(
      vim.fn.getqflist({ idx = 0 }).idx,
      2,
      "quickfix focus should stay on the same item after annotation"
    )
    T.expect_eq(
      vim.fs.basename(vim.api.nvim_buf_get_name(0)),
      "tracked.txt",
      "current buffer should stay on the annotated file after annotation"
    )
  end

  run_open_flow_test()
  run_buffer_eligibility_test()
  run_refresh_test()
  run_quickfix_order_stability_test()
  T.finish()
end
