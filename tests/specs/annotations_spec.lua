return function()
  local H = require("tests.support.helpers")
  H.bootstrap()

  local T = H.new_harness("annotations_spec")
  local annotations = require("patchmarks.annotations")
  local editor = require("patchmarks.editor")
  local patchmarks = require("patchmarks")
  local render = require("patchmarks.render")
  local session = require("patchmarks.session")
  local storage = require("patchmarks.storage")

  local function setup_repo()
    local tmp = vim.fn.tempname()
    H.mkdirp(tmp)

    H.git(tmp, "init", "-q")
    H.git(tmp, "config", "user.name", "Patchmarks Test")
    H.git(tmp, "config", "user.email", "patchmarks@example.com")

    H.write_file(vim.fs.joinpath(tmp, "tracked.txt"), { "alpha", "beta", "gamma", "delta" })
    H.git(tmp, "add", "tracked.txt")
    H.git(tmp, "commit", "-qm", "init")

    H.write_file(
      vim.fs.joinpath(tmp, "tracked.txt"),
      { "alpha", "beta changed", "gamma changed", "delta" }
    )
    return tmp
  end

  local function edit_tracked(repo)
    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(repo, "tracked.txt")))
  end

  local function open_editor_and_save(body)
    local state = H.require_value(editor.state, "editor state should exist")
    T.expect(editor.is_open(), "editor should be open")
    local source_cursor = vim.deepcopy(state.source_cursor)
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, vim.split(body, "\n", { plain = true }))
    vim.cmd("wq")
    T.expect(not editor.is_open(), "editor should close after :wq")
    T.expect_eq(
      vim.api.nvim_win_get_cursor(0)[1],
      source_cursor[1],
      "cursor line should restore after save"
    )
  end

  local function open_editor_write_and_close(body)
    local state = H.require_value(editor.state, "editor state should exist for :write test")
    T.expect_eq(vim.bo[state.bufnr].buftype, "acwrite", "editor buffer should use acwrite")

    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, vim.split(body, "\n", { plain = true }))
    vim.cmd.write()
    T.expect(editor.is_open(), "editor should remain open after :write")
    T.expect_eq(vim.bo[state.bufnr].modified, false, "editor buffer should be clean after :write")

    vim.cmd("wq")
    T.expect(not editor.is_open(), "editor should close after :wq")
  end

  local function run_annotation_flow_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)
    edit_tracked(repo)

    local ok = patchmarks.start()
    T.expect(ok == true, "PatchmarksStart should succeed")
    T.expect_eq(
      vim.api.nvim_buf_get_name(0),
      vim.uv.fs_realpath(vim.fs.joinpath(repo, "tracked.txt")),
      "tracked file should stay open"
    )
    T.expect_eq(vim.b.patchmarks_keymaps_applied, true, "review keymaps should be applied")

    local current = H.require_value(session.get(), "session should exist after start")
    local session_path =
      H.require_value(storage.path(current.repo_root), "session path should exist")
    T.expect(vim.fn.filereadable(session_path) == 1, "session JSON should be written on open")

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.add_current()
    open_editor_and_save("Simplify this branch.")

    current = H.require_value(session.get(), "session should exist after save")
    local file =
      H.require_value(session.find_file(current, "tracked.txt"), "tracked file should exist")
    T.expect_eq(#file.annotations, 1, "annotation should be created")
    T.expect_eq(
      file.annotations[1].body,
      "Simplify this branch.",
      "annotation body should persist in memory"
    )
    T.expect_eq(current.annotation_count, 1, "session annotation count")

    local extmarks = vim.api.nvim_buf_get_extmarks(0, render.ns, 0, -1, {})
    T.expect(#extmarks > 0, "annotation rendering should place extmarks")

    local persisted = H.decode_json(session_path)
    T.expect_eq(
      #persisted.files["tracked.txt"].annotations,
      1,
      "session JSON should include annotation"
    )

    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    annotations.add_current()
    open_editor_write_and_close("Read this carefully.\nSecond line.")
    T.expect_eq(#file.annotations, 2, "second annotation should be created via :write/:wq flow")

    annotations.upsert("tracked.txt", 2, 3, "Merged overlapping note.")
    T.expect_eq(#file.annotations, 2, "overlapping annotation should update instead of duplicating")
    T.expect_eq(
      file.annotations[1].body,
      "Merged overlapping note.",
      "overlapping annotation body should be updated"
    )

    session.clear()
    local reopened = patchmarks.start()
    T.expect(reopened == true, "PatchmarksStart should restore persisted session")
    current = H.require_value(session.get(), "session should exist after reopen")
    file = H.require_value(session.find_file(current, "tracked.txt"), "tracked file should exist")
    T.expect_eq(#file.annotations, 2, "annotations should restore from persisted session")
    T.expect_eq(file.annotations[1].body, "Merged overlapping note.", "restored annotation body")

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.delete_current()
    T.expect_eq(#file.annotations, 1, "annotation should delete from memory")
    T.expect_eq(current.annotation_count, 1, "annotation count should decrement")

    persisted = H.decode_json(session_path)
    T.expect_eq(
      #persisted.files["tracked.txt"].annotations,
      1,
      "session JSON should reflect deletion"
    )
  end

  local function run_empty_body_semantics_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)
    edit_tracked(repo)

    T.expect(patchmarks.start() == true, "PatchmarksStart should succeed for empty-body test")

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.add_current()
    local state = H.require_value(editor.state, "editor should open for new annotation")
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, { "" })
    vim.cmd("q")

    local current = H.require_value(session.get(), "session should exist for empty-body test")
    local file =
      H.require_value(session.find_file(current, "tracked.txt"), "tracked file should exist")
    T.expect_eq(#file.annotations, 0, "empty new annotation should not create a note")

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.add_current()
    open_editor_and_save("Delete me if cleared.")
    T.expect_eq(#file.annotations, 1, "setup annotation should exist")

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.edit_current()
    state = H.require_value(editor.state, "editor should open for existing annotation")
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, { "" })
    local ok = pcall(function()
      vim.cmd("q")
    end)
    T.expect(ok, "empty existing annotation should quit cleanly on plain :q")
    T.expect_eq(
      #file.annotations,
      1,
      "plain :q on empty existing annotation should keep the original annotation"
    )

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    annotations.edit_current()
    state = H.require_value(editor.state, "editor should reopen for existing annotation deletion")
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, { "" })
    H.with_confirm_result(1, function()
      vim.cmd("wq")
    end)

    T.expect_eq(#file.annotations, 0, "empty save on existing annotation should delete it")
  end

  local function run_visual_range_annotation_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)
    edit_tracked(repo)

    T.expect(patchmarks.start() == true, "PatchmarksStart should succeed for visual-range test")

    vim.cmd("normal! 2GVj")
    annotations.add_current()
    open_editor_and_save("Range note.")

    local current = H.require_value(session.get(), "session should exist for visual-range test")
    local file =
      H.require_value(session.find_file(current, "tracked.txt"), "tracked file should exist")
    T.expect_eq(#file.annotations, 1, "visual range should create one annotation")
    T.expect_eq(
      file.annotations[1].start_lnum,
      2,
      "visual range should start on first selected line"
    )
    T.expect_eq(file.annotations[1].end_lnum, 3, "visual range should end on last selected line")
  end

  local function run_out_of_range_restore_test()
    local repo = setup_repo()
    vim.cmd.cd(repo)
    edit_tracked(repo)

    T.expect(
      patchmarks.start() == true,
      "PatchmarksStart should succeed for out-of-range restore test"
    )
    local current = H.require_value(session.get(), "session should exist for out-of-range restore")
    local session_path =
      H.require_value(storage.path(current.repo_root), "session path should exist")

    vim.fn.writefile({
      vim.json.encode({
        version = 1,
        repo_name = current.repo_name,
        created_at = current.created_at,
        exported_at = nil,
        next_annotation_seq = 2,
        files = {
          ["tracked.txt"] = {
            status = "M",
            kind = "modified",
            index = 1,
            first_changed_line = 2,
            absolute_path = vim.fs.joinpath(repo, "tracked.txt"),
            annotations = {
              {
                id = "ann_0001",
                start_lnum = 2,
                end_lnum = 99,
                body = "Out of range note.",
                created_at = "2026-04-17T00:00:00Z",
                updated_at = "2026-04-17T00:00:00Z",
              },
            },
          },
        },
      }),
    }, session_path)

    session.clear()
    T.expect(
      patchmarks.start() == true,
      "PatchmarksStart should reopen even with out-of-range annotations"
    )
    current = H.require_value(session.get(), "session should exist after out-of-range reopen")
    local file =
      H.require_value(session.find_file(current, "tracked.txt"), "tracked file should exist")
    T.expect_eq(#file.annotations, 1, "out-of-range restore should keep annotation")
    T.expect_eq(
      file.annotations[1].start_lnum,
      2,
      "out-of-range restore should preserve valid start"
    )
    T.expect_eq(file.annotations[1].end_lnum, 4, "out-of-range restore should clamp end to EOF")
  end

  run_annotation_flow_test()
  run_empty_body_semantics_test()
  run_visual_range_annotation_test()
  run_out_of_range_restore_test()
  T.finish()
end
