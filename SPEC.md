# Patchmarks.nvim Product Spec

## Identity

- Product name: `patchmarks.nvim`
- Primary goal: review changed files in a Git worktree and attach line-based annotations that can be exported back to an LLM coding agent.

## Product Summary

Patchmarks is a file-oriented review plugin for Neovim.

It starts a review session for the current Git change set and attaches a local
annotation layer to eligible normal file buffers. Users may optionally open a
native quickfix list for changed-file navigation.

Patchmarks does **not** implement Git diff rendering itself. It is designed to coexist with existing diff plugins such as `gitsigns.nvim` or `mini.diff`. Those plugins remain responsible for signs, inline hunk preview, staging, unstaging, and other Git-facing visuals. Patchmarks only owns:

- review session lifecycle
- changed-file discovery
- file navigation
- annotation storage
- annotation rendering
- annotation export

## Product Philosophy

Patchmarks follows a platform-first, Unix-style philosophy.

It should lean on:

- Neovim built-ins before custom infrastructure
- Git CLI before custom repository logic
- existing diff plugins before custom diff UI
- optional normal quickfix behavior before custom list UIs

Patchmarks should only implement the narrow layer that is actually unique:

- review-session orchestration
- annotation UX
- annotation persistence
- compact export for agent feedback

## Non-Goals

- Hunk-level review UI
- Replacing `gitsigns.nvim`, `mini.diff`, `fugitive`, or similar tools
- Managing Git staging/unstaging directly
- Persisting annotations across review rounds after the user starts a new round
- Supporting deleted tracked files in v1

## Supported Scope in v1

- Tracked modified files
- Tracked added files
- Renamed files, using the new path
- Copied files, using the new path
- Untracked files
- Line annotations on a single line
- Line-range annotations across multiple lines

## Explicitly Excluded in v1

- Deleted tracked files
- Column-precise annotations
- Overlapping annotations
- Multiple annotations covering the same line range
- Automatic carry-forward of annotations into a new review round
- Direct integration with any specific agent CLI

## Core UX Model

Patchmarks is centered on a review session.

When the user starts a session:

1. Patchmarks finds the Git repo root.
2. It computes the current changed-file set.
3. It creates or restores the persisted session.
4. It attaches Patchmarks keymaps and annotation extmarks to the current buffer if that buffer is an eligible source buffer.
5. It registers buffer-entry hooks so eligible source buffers attach when the user opens them normally.
6. It does not open quickfix, jump files, or move the cursor.

During the session:

- the user opens and moves between files however they normally do
- the user may run `:PatchmarksFiles` when they want a native quickfix list of changed files
- the user uses Patchmarks mappings to annotate line ranges
- the user may keep using their existing diff plugin to inspect or stage hunks
- Patchmarks only refreshes when the user explicitly asks it to

At export time:

- Patchmarks produces a compact text block
- it copies that block to Neovim registers and the system clipboard when available
- it keeps the current session intact until the user explicitly starts a new round or discards it
- if the review was exported and Git later changes, starting Patchmarks starts a fresh round automatically

## Why File-Oriented Instead of Hunk-Oriented

The source buffer must remain the real file buffer so the user gets:

- normal syntax highlighting
- their usual motions and text objects
- existing Git diff signs and inline hunk preview from external plugins

This removes the need for Patchmarks to synthesize diff buffers or build its own diff renderer.

## Dependencies

Required:

- Neovim `>= 0.10`
- Git available on `$PATH`

Optional:

- `lewis6991/gitsigns.nvim`
- `echasnovski/mini.diff`

Patchmarks has no hard dependency on either optional plugin.

## Configuration

Patchmarks exposes a small Lua setup surface:

```lua
require("patchmarks").setup({
  preview = {
    trigger = "manual", -- or "cursorhold"
    width = 72,
    height = 6,
  },
})
```

v1 intentionally keeps configuration narrow.

- `preview.trigger`
  - `"manual"` by default
  - `"cursorhold"` enables preview-on-hover for annotations in attached session buffers
- `preview.width`
  - preview float width
- `preview.height`
  - preview float height

## Session Lifecycle

### Commands

- `:PatchmarksStart`
  - Start the current review session if one exists.
  - Otherwise create a new session from the current Git state.
  - Do not open quickfix, switch buffers, or move the cursor.
- `:PatchmarksFiles`
  - Populate and open a native quickfix list for the active session's changed files.
- `:PatchmarksNew`
  - Discard any existing session and start a fresh round from the current Git state.
- `:PatchmarksRefresh`
  - Refresh changed-file metadata without discarding annotations.
- `:PatchmarksExport`
  - Export the current annotations to registers and clipboard.
- `:PatchmarksStop`
  - Stop Patchmarks UI state but keep the session persisted.
- `:PatchmarksDiscard`
  - Delete the active session and all annotations for it.

### Session Rules

- Only one active Patchmarks session exists per Git repo.
- Session state is persisted under `.git/patchmarks/current.json`.
- Starting a new round with `:PatchmarksNew` discards old annotations entirely.
- Exporting does not clear the session automatically.
- If Neovim crashes or closes, restarting with `:PatchmarksStart` restores the session.
- If the session was exported and Git has changed since that export, `:PatchmarksStart` starts a fresh round instead of restoring old annotations.

## Change Discovery

### File Set Source

Patchmarks uses:

- `git rev-parse --show-toplevel`
- `git status --porcelain=v1 -z --untracked-files=all`

### Included Statuses

Include files with statuses equivalent to:

- modified
- added
- renamed
- copied
- untracked
- mixed staged/unstaged variants of the above

### Excluded Statuses

- deleted tracked files

### Path Rules

- For renames and copies, Patchmarks uses the destination path.
- Paths are stored relative to repo root.
- Quickfix items use absolute paths internally and repo-relative paths for display/export.

## First Changed Line

Patchmarks still computes the first changed line for each tracked file so the initial cursor placement is useful.

### Source of Truth

For tracked existing files:

- use `git diff --unified=0 --no-ext-diff HEAD -- <path>`
- parse the first hunk header
- use the new-side start line as the target line

For untracked files:

- target line is `1`

For files where no diff hunk can be parsed but the file exists:

- target line is `1`

## Quickfix Design

Patchmarks can use Neovim's normal built-in quickfix list when explicitly requested.

It does not implement a custom quickfix UI.

Patchmarks only:

- populates the list with changed files via `setqflist()`
- opens it from `:PatchmarksFiles`
- updates the list title and item text as session metadata changes

Each quickfix item represents one file, not one hunk.

### Quickfix Item Fields

- `filename`: absolute file path
- `lnum`: first changed line or `1`
- `col`: `1`
- `text`: compact label with Git status and annotation count
- `user_data`: internal file metadata

### Quickfix Title

Format:

`Patchmarks: <repo-name> (<file-count> files, <annotation-count> notes)`

### Quickfix Text Format

Format:

`[<status>] <relative-path> (<note-count>)`

Examples:

- `[M] lua/patchmarks/session.lua (2)`
- `[??] notes/scratch.md (0)`
- `[R] lua/old.lua -> lua/new.lua (1)`

### Quickfix Ordering

Default order:

1. Git status order
2. files with stale annotations remain at the end

The quickfix list should stay stable while the user is actively reviewing.

## Source Buffer Behavior

Patchmarks uses the real file buffer.

### Buffer Constraints

- source buffers remain ordinary editable file buffers
- Patchmarks only attaches to buffers with `buftype == ""`
- Patchmarks only attaches when the normalized file path belongs to the active session
- no synthetic diff text is inserted into the buffer
- existing syntax highlighting remains untouched

### Non-File Buffers

Patchmarks is inactive in synthetic or plugin-owned buffers:

- quickfix
- help
- terminal
- prompt
- `nofile`
- `acwrite`
- Fugitive status/diff/index buffers
- other plugin-owned buffers without a stable real file identity

Annotations target source files, not Git control surfaces or synthetic views.

### Interaction With External Diff Plugins

Patchmarks does not render or manage hunks.

If another plugin is attached to the buffer, its gutter and inline diff UI are allowed to remain active. Patchmarks avoids owning the sign column to reduce conflicts.

## Annotation Model

Annotations are line-based, not column-based.

### Range Rules

- A normal-mode annotation targets the current line.
- A visual-mode annotation targets the selected line range.
- Characterwise and blockwise selections are normalized to full-line ranges.
- Range endpoints are inclusive.

### Overlap Rules

- Annotations may not overlap.
- Creating a new annotation on a range that overlaps an existing annotation opens the existing annotation for editing instead of creating a second one.

### Required Fields

Each annotation stores:

- `id`
- `path`
- `start_lnum`
- `end_lnum`
- `body`
- `created_at`
- `updated_at`
- `excerpt`

`excerpt` is a short snapshot of the annotated lines used for resilience and diagnostics after reload.

## Runtime Anchoring

Inside an active Neovim session, annotations are anchored with extmarks.

### Extmark Rules

- one extmark per annotation
- extmark starts on `start_lnum`
- extmark range covers `start_lnum..end_lnum`
- extmarks are only runtime anchors and are rebuilt from persisted data on restore

### Persistence Rules

Persisted JSON stores line ranges, not extmark ids.

On restore:

1. reopen the file
2. place the extmark back on the stored line range
3. if the file is shorter than before, clamp the range into valid bounds

## Annotation Rendering

Patchmarks renders annotations in the source buffer without taking over the gutter.

### Default Visuals

- subtle highlight over the full annotated line range
- compact end-of-line marker on the first line of the range

### Marker Policy

- marker only by default
- no inline annotation text preview by default

This keeps the buffer quiet and avoids competing with diff overlays from other plugins.

## Annotation Preview

Preview is separate from editing.

### Default Behavior

- preview is manual by default
- buffer-local mapping: `<localleader>p`
- if the same annotation is already previewed, Patchmarks should avoid reopening the float unnecessarily

### Optional Behavior

- config option `preview.trigger = "cursorhold"`
- when enabled, Patchmarks opens the preview float on `CursorHold` for the annotation under the cursor

### Default Choice Rationale

Manual preview avoids:

- hover flicker
- accidental popup churn while navigating
- interference with existing `CursorHold` workflows

## Floating Preview UI

The preview float is read-only.

### Preview Float Rules

- anchored near the cursor
- fixed size
- wrapped text
- non-focusable
- auto-closes on cursor move, buffer leave, or explicit close

### Default Size

- width: `72`
- height: `6`

### Preview Content

- title: `<relative-path>:<start>-<end>`
- body: full annotation text

## Floating Editor UI

Annotation creation and editing use a real floating editor buffer.

### Editor Rules

- anchored near the cursor position of the source buffer
- focusable
- fixed width and height
- multiline by default
- scrollable
- wraps long lines
- behaves like a temporary Vim buffer, not a modal form
- uses a custom-write scratch buffer
- source buffer remains visible behind it

### Default Size

- width: `72`
- height: `8`

### Anchor Behavior

- anchor to the cursor line of the source buffer
- prefer opening below the cursor
- if there is insufficient room below, open above

### Border Title

Format:

`Patchmarks: <relative-path>:<start>-<end>`

### Editor Keymaps

- `<Esc>` in insert mode returns to normal mode as usual
- normal-mode motions, scrolling, search, and text objects should work normally
- `:w` saves and keeps the editor open
- `:wq` and `ZZ` save and close
- `:q` closes only when there are no unsaved changes
- `:q!` and `ZQ` discard unsaved changes and close

### Save Semantics

- trim trailing blank lines
- on `:w`, save in place and redraw annotation extmarks without closing
- on `:wq` or `ZZ`, save and close
- saving an empty new annotation closes without creating anything
- quitting an empty existing annotation with `:q` keeps the original annotation unchanged
- saving an existing annotation as empty asks for deletion confirmation and deletes only on acceptance

## Buffer-Local Keymaps

These mappings exist only in normal file buffers that belong to the active Patchmarks session.

- `<localleader>a`
  - Add annotation on current line or visual selection.
- `<localleader>e`
  - Edit annotation under cursor.
- `<localleader>d`
  - Delete annotation under cursor.
- `<localleader>p`
  - Preview annotation under cursor.
- `]a`
  - Jump to next annotation in the current file, wrapping to the first annotation at the end.
- `[a`
  - Jump to previous annotation in the current file, wrapping to the last annotation at the start.
- `<localleader>x`
  - Export current session.
- `<localleader>r`
  - Refresh Patchmarks metadata.
- `<localleader>R`
  - Start a new round and discard the current session.

## Navigation Semantics

### Within File

- `[a` and `]a` only traverse annotations in the current file
- navigation wraps within the current file
- if no annotation exists in the current file, Patchmarks shows a short notification and does nothing

### Across Files

Patchmarks does not own file traversal by default. Users open files however they normally do.

When requested, `:PatchmarksFiles` provides a native quickfix list for changed-file traversal.

## Platform Choices

Patchmarks should prefer Neovim 0.10+ built-ins over homegrown helpers whenever possible.

Examples:

- `vim.fs` for path operations
- `vim.system()` for Git subprocesses
- `vim.iter` where it meaningfully simplifies traversal
- `vim.api.nvim_create_autocmd()` for lifecycle hooks
- `vim.api.nvim_open_win()` for preview/editor floats
- `setqflist()` and `getqflist()` for quickfix management
- extmarks for runtime annotation anchors

Avoid introducing utility wrappers unless they reduce real complexity.

## Refresh Model

Patchmarks refresh is metadata-oriented, not destructive.

### Refresh Policy

- refresh is explicit only
- there is no automatic refresh on focus, buffer entry, or window entry

### What Refresh Updates

- changed-file set from Git
- first changed line per file
- quickfix title and item labels if the Patchmarks file list is active

### What Refresh Does Not Do

- it does not discard annotations
- it does not start a new round
- it does not auto-resolve or auto-carry annotations

### Files That Leave the Change Set

If a file already has annotations and later leaves the live Git change set during the same session:

- keep it in the quickfix list
- mark it internally as `stale`
- keep its annotations intact

This prevents silent data loss.

## New Round Semantics

Starting a new round is explicit.

### Trigger

- `:PatchmarksNew`
- `<localleader>R`

### Effects

- delete current session data
- rebuild changed-file set from current Git state
- create a brand-new annotation set

## Post-Export Reopen Semantics

Patchmarks treats export as the handoff boundary to the agent.

If the current session was exported and Git later changes:

- starting with `:PatchmarksStart` starts a fresh round automatically
- old annotations from the exported round are not restored
- Patchmarks shows a short notice explaining why a fresh round was started

If the session was exported but Git is unchanged:

- `:PatchmarksStart` restores the existing session normally

There is no automatic annotation carry-forward in v1.

## Clipboard and Export

Export is optimized for compactness and agent usefulness.

### Export Destination

Always write to:

- unnamed register `"`

Also write to these when available:

- `+`
- `*`

Patchmarks should detect clipboard support instead of assuming Neovim is already synced to the system clipboard.

### Export Format

Use a compact plain-text block.

Default format:

```text
PATCHMARKS REVIEW
repo: <repo-name>
files: <annotated-file-count>
notes: <annotation-count>

[<relative-path>:<start>-<end>]
<annotation body>

[<relative-path>:<start>-<end>]
<annotation body>
```

### Export Ordering

1. files in session order
2. annotations in ascending line order within each file

### Export Omissions

Do not include:

- code excerpts
- Git diff text
- hunk metadata
- timestamps

This keeps the payload token-efficient and assumes the agent can inspect the repo directly.

## Diff Provider Coexistence

Patchmarks coexists with external diff plugins but does not control them.

### Rules

- Patchmarks does not toggle diff overlays, inline previews, or hunk popups automatically
- Patchmarks does not wrap provider-specific commands behind its own keymaps
- Patchmarks does not try to normalize provider UX across `mini.diff`, `gitsigns.nvim`, or any other plugin
- users keep using their existing diff plugin exactly how they already prefer

### Guarantee

Patchmarks should avoid interfering with provider signs, overlays, or buffer attachments.

## Data Model

### Session JSON

```json
{
  "version": 1,
  "repo_root": "/abs/path/to/repo",
  "created_at": "2026-04-16T16:00:00Z",
  "exported_at": null,
  "files": {
    "lua/patchmarks/session.lua": {
      "status": "M",
      "first_changed_line": 42,
      "stale": false,
      "annotations": [
        {
          "id": "ann_001",
          "start_lnum": 42,
          "end_lnum": 45,
          "body": "Collapse these two refresh paths into one debounced entry point.",
          "excerpt": "function Session.refresh(...)",
          "created_at": "2026-04-16T16:02:00Z",
          "updated_at": "2026-04-16T16:03:00Z"
        }
      ]
    }
  }
}
```

## Error Handling

### Not in a Git Repo

- fail with a clear message
- do not open Patchmarks UI

### No Changed Files

- open nothing
- show a short message: `Patchmarks: no changed files`

### Clipboard Provider Missing

- still write to unnamed register
- show a short message that system clipboard was unavailable

### External File Removal During Session

- if the file no longer exists, keep the annotation data in the session
- file-list entry remains if `:PatchmarksFiles` is used, but opening it shows a clear error

## Performance Constraints

- Git status refresh should avoid reopening all buffers unnecessarily
- annotation rendering should only update the current buffer when possible
- refresh should be debounced
- export should be linear in annotation count

Expected scale for v1:

- tens to low hundreds of changed files
- tens of annotations

## Implementation Notes

Recommended Lua module split:

- `patchmarks.init`
- `patchmarks.config`
- `patchmarks.git`
- `patchmarks.session`
- `patchmarks.annotations`
- `patchmarks.render`
- `patchmarks.float`
- `patchmarks.export`
- `patchmarks.commands`
- `patchmarks.keymaps`

## Delivery Model

Implementation should proceed slice by slice.

### Slice Rules

- each slice must be coherent and usable on its own
- each slice must be large enough to exercise a real user workflow
- each slice must remain small enough to test confidently
- after each slice, implementation must be reviewed against both the slice plan and this spec
- after each slice, headless tests must pass before handing off for manual testing
- no commit should be made until manual testing for that slice is complete

### Slice Style

Favor vertical slices over layer-only slices.

Good slices combine enough command, state, rendering, and test coverage to let the feature be used end to end.

## Final Defaults

- canonical name: `patchmarks.nvim`
- optional file-oriented quickfix list
- real source buffer, editable
- optional coexistence with `gitsigns.nvim` or `mini.diff`
- line-based non-overlapping annotations
- manual annotation preview by default
- optional `CursorHold` preview mode
- floating multiline editor anchored to cursor
- autosaved session under `.git/patchmarks/current.json`
- no deleted tracked files in v1
- no cross-round annotation carry-forward in v1
- compact plain-text clipboard export
