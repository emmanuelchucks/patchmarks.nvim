# patchmarks.nvim

`patchmarks.nvim` is a file-oriented Git review plugin for Neovim.

It starts a review session for the current Git change set and lets you attach
freeform line or line-range annotations in normal file buffers. Those
annotations can be exported back to an LLM coding agent.

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

- `:PatchmarksStart`
  Start or resume a Patchmarks session for the current Git worktree.
- `:PatchmarksFiles`
  Open a native quickfix list for the active session's changed files.
- `:PatchmarksRefresh`
  Explicitly refresh changed-file metadata without discarding annotations.
- `:PatchmarksNew`
  Start a fresh round and discard existing annotations.
- `:PatchmarksExport`
  Export annotations to registers and clipboard when available.
- `:PatchmarksStop`
  Stop Patchmarks UI state but keep the session persisted.
- `:PatchmarksDiscard`
  Delete the persisted session and clear in-memory state.

## Buffer-Local Keymaps

These mappings exist only in normal file buffers that belong to the active
Patchmarks session.

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
  Jump to the previous annotation in the current file, wrapping to the last.
- `]a`
  Jump to the next annotation in the current file, wrapping to the first.

## Workflow

1. Open a changed source file normally.
2. Run `:PatchmarksStart` inside the Git worktree.
3. Add annotations with `<localleader>a`.
4. Edit or preview them as needed.
5. Optionally run `:PatchmarksFiles` if you want a native quickfix list of changed files.
6. Run `:PatchmarksExport` to copy a compact review block for your agent.
7. After the agent makes more Git changes, run `:PatchmarksStart` to start a fresh round automatically if the last review was already exported.
8. Use `:PatchmarksNew` when you want to force a fresh round yourself.

Patchmarks does not make source buffers read-only. Session files remain normal
editable file buffers, so you can keep using tools like `gitsigns.nvim`,
`mini.diff`, or Fugitive for hunk navigation and staging. Patchmarks stays
inactive in non-file buffers such as quickfix, help, terminal, prompt,
`nofile`, `acwrite`, and plugin-owned buffers.

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

This lets `:PatchmarksStart` restore a session after restarting Neovim.

If the session was already exported and Git has changed since that export,
`PatchmarksStart` starts a fresh round automatically instead of restoring the
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
