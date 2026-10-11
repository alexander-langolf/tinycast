# File Navigator (spec, draft)

> Status: **draft spec, not built.** Interaction model prototyped in
> [`docs/prototypes/file-navigator.prototype.html`](../prototypes/file-navigator.prototype.html)
> (branch `proto/file-navigator`). Research: vault `1 - Projects/Agent Infrastructure/Tinycast/File Navigator — Research.md`.
> Open decisions are listed at the end; nothing here is settled until they are.

A keyboard-first, nnn-style folder browser as a palette screen. It answers "get me to that file and
do something with it" faster than Finder, and hands files to the places Tinycast already owns: a
terminal view running `$EDITOR`, Ghostty, Quick Look, Search Files and agentkit agents. It is a
navigator, not a file manager: no rename, move, copy-to or bulk delete in v1.

## Entry points

- Launcher command **Browse Files** (and an optional global shortcut), starting in the last folder
  browsed, else `~`.
- From **Search Files**: ⌘↵ on a result browses its containing folder with the result focused.
- From a **terminal view**: a card action opens the navigator in that instance's current directory
  (OSC 7 cwd the session already tracks).
- Typing a path (`~/…` or `/…`) in the root palette routes here, as `$` routes to terminals.

## Interaction model

Single list (no Miller columns — the palette is narrow) plus an optional preview pane. Letters
always belong to the filter, so commands use arrows and modifiers.

| Key | Action |
|---|---|
| type | fuzzy-filter the current folder (same scorer as Search Files) |
| `~/…`, `/…` | path jump: walk to the deepest existing folder, keep the rest as the filter |
| ↑ ↓ | move focus |
| → | enter the focused folder |
| ← | parent folder, with the folder you came from focused |
| ⌫ on empty filter | parent folder |
| ↵ | folder: enter. File: **edit in a terminal view** (`$EDITOR`). With picked files: edit all of them |
| Space | pick / unpick (the pick list survives folder changes, nnn-style) |
| ⌘A | pick every visible row |
| ⌘K | action panel for the picked files, else the focused row |
| ⌘B | bookmarks + recent folders |
| ⌘Y | toggle the preview pane |
| ⌘. | show hidden and ignored entries |
| ⌘O | Ghostty tab in the current folder |
| ⌘T | new terminal view in the current folder |
| ⌘F | Search Files scoped to the current folder |
| ⌃G | close and `cd` the originating terminal view into the current folder |
| Esc | clear filter → clear picks → close (one step per press) |

⌘K actions: Edit in terminal (files only), Open with default app, Open Ghostty here, New terminal
here, Quick Look, Copy path(s), Copy relative path(s), Reveal in Finder, Search Files from here,
Hand to an agent (agentkit `agent_dispatch`, files as context), Bookmark folder.

## Edit in a terminal view

↵ on a file calls `TerminalInstancesCoordinator.open(command:directory:)` with
`$EDITOR '<file>'…` in the file's folder (paths shell-quoted, relative to that folder). The login
`zsh -il` provides `$EDITOR`; if it is unset the command falls back to a setting (default: the
editor chosen below). Constraints from the libghostty grid view, which this depends on:

- The grid renders full-screen programs and forwards keys, but **drops every ⌘ combination**
  (`GhosttyGridView.keyDown`). The editor must save and quit with ⌃/⌥ keys or modal keys; ⌘S will
  not reach it. Either pick such an editor, or map ⌘S/⌘Z/⌘C/⌘V to the editor's ⌃ equivalents for
  instances that run an editor.
- Instances have a fixed grid size from `TerminalInstanceMetrics`; an editor needs the larger
  layout (check `gridRows` gives a usable height, or let the editor instance request more rows).
- The old log renderer (`forkTerminalGhostty = NO`) cannot show full-screen programs; with it off,
  ↵ falls back to "Open Ghostty here + `$EDITOR`" in a real Ghostty tab.

## Reuse from Search Files

| Piece | Reused as |
|---|---|
| `FileSearchResult` (url, name, parent, isDirectory, home-abbreviated path) | the row value, built from a directory listing instead of Spotlight |
| shared `FuzzyMatch` scorer | the in-folder filter ranking |
| `FileSearchIgnoreList` (+ structural hidden / bundle rules) | default hiding; ⌘. reveals |
| `FileSearchPreviewKind` + `FileSearchPreview` surfaces (plain text, PDF, Quick Look, media) | the preview pane |
| `FileSearchCoordinator` actions (open, showInFinder, share, copyPath, copyName, copyFile, trash) | ⌘K actions, generalised to take one or many URLs |
| `FileSearchFilter` (type filter) | not in v1 |
| `FileSearchScope` / Spotlight session | not used for browsing; ⌘F hands the current folder to Search Files as a one-off scope |

New pieces:

- `FileNavigator/Model/FileNavigatorState.swift` — the pure reducer the prototype validates
  (folder, filter, focus, picks, panel, hidden toggle, bookmarks, recent). Foundation-only, with a
  `file-navigator-test` harness, following the `Model/` purity rule.
- `FileNavigator/Service/DirectoryLister.swift` — off-main listing with prefetched resource keys,
  streamed in chunks, cancelling stale listings; `getattrlistbulk` only if large folders measure slow.
- `FileNavigator/Service/FolderWatcher.swift` — a `DispatchSource` file-system object source on the
  visible folder only; picks keyed by path survive updates; vanished files drop out of picks.
- `FileNavigator/UI/FileNavigatorScreen.swift` + coordinator, a new palette mode beside `.fileSearch`.

## Behaviour rules

- Folders sort first, then by name; a non-empty filter sorts by score.
- `.app`/`.pkg` bundles are files (no package browsing in v1). Symlinked folders are entered by
  their logical path; loops are detected by canonical path.
- TCC-protected folders (Desktop, Documents, Downloads, iCloud, removable volumes) prompt once; a
  denied listing shows a "grant access" row, never an empty list.
- Every action re-validates its URLs: a file deleted between listing and action reports a notice and
  leaves the palette as it was.
- Bookmarks and recent folders persist under the dev/stable bundle id like other settings.

## Acceptance criteria

1. `~/github/agentkit/lib` reachable in ≤ 8 keystrokes from the root palette via path jump.
2. ↵ on a file opens a terminal view in its folder running `$EDITOR` on it; the editor is usable
   (renders, saves, quits) inside the grid.
3. Picks made in two folders survive navigation and reach ⌘K → Hand to an agent as file context.
4. A 10,000-entry folder lists without blocking the main thread; typing stays responsive.
5. ⌘. reveals `.git`, `.env`, `node_modules`; ⌘. again hides them.
6. A file deleted on disk while visible disappears from the list and from picks.
7. Harness `file-navigator-test` covers the reducer cases in the prototype's walkthroughs.

## Open decisions

1. **nnn auto-enter** (a filter leaving exactly one folder walks into it): with fuzzy matching it
   chains (`wor` → work, then `p` → platform). Default off, or on? Try the prototype's
   "Auto-enter surprise" tab.
2. **Default editor** when `$EDITOR` is unset — research (vault, 2026-10-11) ranks Fresh (non-modal,
   LSP, needs Ghostty Option-as-Alt), Helix (modal, diff gutter), Microsoft Edit (simplest); all
   unverified inside the grid, and the ⌘-key gap applies to each.
3. **Search algorithm** for ⌘F and in-folder filtering at scale (Spotlight vs a walker + fzf-style
   matcher such as nucleo/skim, possibly via Rust FFI) — research in progress.
4. Whether ↵ on a file should instead open the Monaco view once that exists (edit in place vs
   terminal editor).
