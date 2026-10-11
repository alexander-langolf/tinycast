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
- From **Search Files** *(optional hook)*: ⌘↵ on a result browses its containing folder with the result focused.
- From a **terminal view**: a card action opens the navigator in that instance's current directory
  (OSC 7 cwd the session already tracks).
- Typing a path (`~/…` or `/…`) in the root palette routes here, as `$` routes to terminals.

## Interaction model

Follows Script Kit Next's File Search (`src/file_search/directory.rs`): **the input is the path.**
`~/github/agentkit/li` lists `~/github/agentkit/` filtered by `li`; input that does not start with
`~` or `/` searches everywhere. Single list (no Miller columns — the palette is narrow) plus an
optional preview pane. The input owns letters, so commands use arrows, Tab and modifiers.

| Key | Action |
|---|---|
| type | edits the path; the last segment fuzzy-filters its folder (`ForkFzf`, fzf syntax: `'exact`, `^prefix`, `!exclude`) |
| words without `~`/`/` | search everywhere: Spotlight through Search Files' existing session, used as is |
| `/` | descends into the folder the input names |
| ⌫ | edits the input; across a `/` it lands in the parent, already filtered by the folder you left |
| Tab | completes the focused row into the input (a folder descends) |
| ⇧Tab | parent folder, with the folder you came from focused (from a mistyped path: back to the last real folder) |
| ↑ ↓ | move focus |
| ↵ | folder: descend. File: **edit in a terminal view** (`$EDITOR`). With picked files: edit all of them |
| Space | pick / unpick (the pick list survives folder changes, nnn-style) |
| ⌘A | pick every visible row |
| ⌘K | action panel for the picked files, else the focused row |
| ⌘B | bookmarks + recent folders |
| ⌘Y | toggle the preview pane |
| ⌘. | show hidden and ignored entries |
| ⌘O | Ghostty tab in the current folder |
| ⌘T | new terminal view in the current folder |
| ⌃G | close and `cd` the originating terminal view into the current folder |
| Esc | trim to the folder → clear picks → close (one step per press) |

A mistyped folder (`~/nope/x`) shows "No folder ~/nope" and no rows; nothing is guessed. nnn's
auto-enter does not apply in this model.

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
| fork-owned `ForkFzf` / `ForkSearch` (`Tinycast/Fork/Search/`, fzf v2 + extended syntax) | the in-folder filter ranking, same syntax as every other list |
| `FileSearchIgnoreList` (+ structural hidden / bundle rules) | default hiding; ⌘. reveals |
| `FileSearchPreviewKind` + `FileSearchPreview` surfaces (plain text, PDF, Quick Look, media) | the preview pane |
| `FileSearchCoordinator` actions (open, showInFinder, share, copyPath, copyName, copyFile, trash) | ⌘K actions, generalised to take one or many URLs |
| `FileSearchFilter` (type filter) | not in v1 |
| `FileSearchScope` / Spotlight session | not used for browsing; ⌘F hands the current folder to Search Files as a one-off scope |

New pieces:

All new code is fork-owned under `Tinycast/Fork/FileNavigator/` (docs/fork.md: customisations live
in `Tinycast/Fork/`). Upstream's Search Files files (24 upstream commits since 2026-08-01) are
**used, never edited**; a thin fork adapter maps them so an upstream API change breaks the build in
one place instead of producing merge conflicts.

- `Fork/FileNavigator/Model/FileNavigatorState.swift` — the pure reducer the prototype validates
  (folder, filter, focus, picks, panel, hidden toggle, bookmarks, recent). Foundation-only, with a
  `file-navigator-test` harness, following the `Model/` purity rule.
- `Fork/FileNavigator/Service/DirectoryLister.swift` — off-main listing with prefetched resource keys,
  streamed in chunks, cancelling stale listings; `getattrlistbulk` only if large folders measure slow.
- `Fork/FileNavigator/Service/FolderWatcher.swift` — a `DispatchSource` file-system object source on the
  visible folder only; picks keyed by path survive updates; vanished files drop out of picks.
- `Fork/FileNavigator/UI/FileNavigatorScreen.swift` + coordinator.

Upstream integration points (each `// FORK: file-navigator`, listed in docs/fork.md):
1. `PaletteMode.fileNavigator` case.
2. `RootPaletteView.screen` routing: a root query starting `~/` or `/` opens the navigator
   (Alfred's entry, beside the existing `$` → terminal hook).
3. Launcher command registration for **Browse Files**.
4. *(optional)* ⌘↵ on a Search Files result browses its folder — the only hook inside upstream's
   Search Files; skip it if upstream churn there keeps conflicting.
5. Terminal card action (already fork-owned code).

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

1. ~~nnn auto-enter~~ — moot: Sasha chose the Script Kit model (input is the path) on 2026-10-11;
   the nnn folder + filter model stays in the prototype only for comparison.
2. **Default editor** when `$EDITOR` is unset — research (vault, 2026-10-11) ranks Fresh (non-modal,
   LSP, needs Ghostty Option-as-Alt), Helix (modal, diff gutter), Microsoft Edit (simplest); all
   unverified inside the grid, and the ⌘-key gap applies to each.
3. **Search candidates** — matching is settled (2026-10-11): **`ForkFzf` only, no Rust fuzzy
   libraries** (no nucleo/skim/FFI). Still open: where ⌘F subtree candidates come from — a
   `FileManager` walk in Swift, or a bundled `fd`/`rg --files` streamed into `ForkFzf` (Spotlight
   stays the global fallback; content search would be a bundled `rg`). Decide after benchmarking
   both on `~/work`.
4. Ship the optional Search Files ⌘↵ hook (integration point 4), or keep Search Files untouched?
5. Whether ↵ on a file should instead open the Monaco view once that exists (edit in place vs
   terminal editor).
