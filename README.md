# patchmarks.nvim

`patchmarks.nvim` is a file-oriented Git review plugin for Neovim.

It opens the current changed-file set into normal source buffers, uses the
built-in quickfix list for file navigation, and lets you attach freeform
line or line-range annotations that can be exported back to an LLM coding
agent.

Patchmarks does not render diffs itself. It is designed to coexist with your
existing diff workflow, whether that is `gitsigns.nvim`, `mini.diff`, or
plain Git commands.

## Requirements

- Neovim `>= 0.10`
- Git on `$PATH`

## License

MIT. See [LICENSE](./LICENSE).

## Installation

With `lazy.nvim`:

```lua
{
  "emmanuelchucks/patchmarks.nvim",
  config = function()
    require("patchmarks").setup({
      preview = {
        trigger = "manual", -- or "cursorhold"
      },
    })
  end,
}
```

For local development:

```lua
{
  dir = "/absolute/path/to/patchmarks.nvim",
  name = "patchmarks.nvim",
  config = function()
    require("patchmarks").setup()
  end,
}
```

## Configuration

```lua
require("patchmarks").setup({
  preview = {
    trigger = "manual", -- "manual" | "cursorhold"
    width = 72,
    height = 6,
  },
})
```

Defaults:

- `preview.trigger = "manual"`
- `preview.width = 72`
- `preview.height = 6`

## Commands

- `:PatchmarksOpen`
  Open the current review session, or create one from the current Git state.
- `:PatchmarksRefresh`
  Explicitly refresh changed-file metadata without discarding annotations.
- `:PatchmarksNew`
  Start a fresh round and discard existing annotations.
- `:PatchmarksExport`
  Export annotations to registers and clipboard when available.
- `:PatchmarksClose`
  Close Patchmarks UI state but keep the session persisted.
- `:PatchmarksDiscard`
  Delete the persisted session and clear in-memory state.

## Buffer-Local Keymaps

These mappings exist only in Patchmarks review buffers.

- `<localleader>a`
  Add an annotation on the current line, or on the current visual line range.
- `<localleader>e`
  Edit the annotation under the cursor.
- `<localleader>d`
  Delete the annotation under the cursor.
- `<localleader>p`
  Preview the annotation under the cursor.
- `<localleader>x`
  Export the current review.
- `<localleader>r`
  Refresh the session.
- `<localleader>R`
  Start a new round.
- `[a`
  Jump to the previous annotation in the current file.
- `]a`
  Jump to the next annotation in the current file.

## Workflow

1. Run `:PatchmarksOpen` inside a Git worktree.
2. Use quickfix to move between changed files.
3. Add annotations with `<localleader>a`.
4. Edit or preview them as needed.
5. Run `:PatchmarksExport` to copy a compact review block for your agent.
6. After the agent makes more Git changes, run `:PatchmarksOpen` to start a fresh round automatically if the last review was already exported.
7. Use `:PatchmarksNew` when you want to force a fresh round yourself.

## Annotation Editor

The annotation editor is a normal writable floating buffer, not a form.

- `Esc` returns to normal mode.
- `:w` saves and keeps the editor open.
- `:wq` and `ZZ` save and close.
- `:q!` and `ZQ` discard.

Empty-body behavior:

- New annotation:
  empty `:q`, `:w`, and `:wq` are all no-ops.
- Existing annotation:
  empty `:q` keeps the original annotation unchanged.
  empty `:w` or `:wq` asks whether to delete the annotation.

## Session Storage

Patchmarks persists the active session under the repo Git dir:

```text
.git/patchmarks/current.json
```

This lets `:PatchmarksOpen` restore a session after restarting Neovim.

If the session was already exported and Git has changed since that export,
`PatchmarksOpen` starts a fresh round automatically instead of restoring the
old annotations.

## Scope

Supported in v1:

- modified tracked files
- added tracked files
- renamed and copied files
- untracked files
- single-line annotations
- line-range annotations

Not supported in v1:

- deleted tracked files
- overlapping annotations
- multiple annotations covering the same range
- automatic carry-forward into a new review round
- agent-specific CLI integration

## Testing

Headless test suite:

```sh
nvim --headless -u NONE -i NONE -c "lua dofile('tests/run.lua')" -c qall!
```

## Quality

Local development commands:

```sh
make format
make lint
make test
make check
```

Tooling:

- `StyLua` for Lua formatting
- `Selene` for Lua linting
- `.luarc.json` for LuaLS project diagnostics

If you need the tools locally and already have Rust installed:

```sh
cargo install --locked stylua
cargo install selene
```

Test layout:

- `tests/specs/`
  feature-oriented specs
- `tests/support/helpers.lua`
  shared test helpers
- `tests/run.lua`
  single test entrypoint

## Contributing

Keep changes aligned with the project boundary:

- Patchmarks owns review-session orchestration and annotation UX.
- Diff rendering and hunk UX belong to the user's existing diff tools.
- Favor Neovim and Git built-ins over extra abstraction.
- Run `make check` before sending changes upstream.

## Help

After installing locally, generate helptags if needed:

```vim
:helptags ./doc
```

Then see:

```vim
:help patchmarks
```
