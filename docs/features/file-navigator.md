# File Navigator (spec, draft)

> Status: **spec, decisions settled 2026-10-11; implementation on `al/file-navigator`.** Interaction
> model prototyped in `docs/prototypes/file-navigator.prototype.html` on the throwaway branch
> `proto/file-navigator`. Research: vault `1 - Projects/Agent Infrastructure/Tinycast/File Navigator — Research.md`.

A keyboard-first, nnn-style folder browser as a palette screen. It answers "get me to that file and
do something with it" faster than Finder, and hands files to the places Tinycast already owns: a
terminal view running `$EDITOR`, Ghostty, Quick Look, Search Files and agentkit agents. It is a
navigator, not a file manager: no rename, move, copy-to or bulk delete in v1.

## Entry points

- Launcher command **Browse Files** (and an optional global shortcut), starting in the last folder
  browsed, else `~`.
- From a **terminal view**: a card action opens the navigator in that instance's current directory
  (OSC 7 cwd the session already tracks).
- Typing a path (`~/…` or `/…`) in the root palette routes here, as `$` routes to terminals.

## Interaction model

Follows Script Kit Next's File Search (`src/file_search/directory.rs`): **the input is the path.**
`~/github/agentkit/li` lists `~/github/agentkit/` filtered by `li`; input that does not start with
`~` or `/` searches everywhere. Single list (no Miller columns — the palette is narrow) plus an
preview pane, **on by default** (⌘Y hides it). The input owns letters, so commands use arrows, Tab and modifiers.

| Key | Action |
|---|---|
| type | edits the path; the last segment fuzzy-filters its folder (`ForkFzf`, fzf syntax: `'exact`, `^prefix`, `!exclude`) |
| words without `~`/`/` | search everywhere: Spotlight through Search Files' existing session, used as is |
| `/` | descends into the folder the input names |
| ⌫ | edits the input; across a `/` it lands in the parent, already filtered by the folder you left |
| Tab | completes the focused row into the input (a folder descends) |
| ⇧Tab | parent folder, with the folder you came from focused (from a mistyped path: back to the last real folder) |
| ↑ ↓ | move focus |
| ↵ | folder: descend. File, or any picks: **open the ⌘K action panel** (first action: Edit in Fresh) |
| Space | pick / unpick (the pick list survives folder changes, nnn-style) |
| ⌘A | pick every visible row |
| ⌘K | action panel for the picked files, else the focused row |
| ⌘B | bookmarks + recent folders |
| ⌘Y | hide / show the preview pane (shown by default) |
| ⌘. | show hidden and ignored entries |
| ⌘O | Ghostty tab in the current folder |
| ⌘T | new terminal view in the current folder |
| ⌘F | search below this folder: the last segment matches recursively (Swift walk + `ForkFzf`), rows show their subfolder; ⌘F again returns to the folder listing |
| ⌃G | close and `cd` the originating terminal view into the current folder |
| Esc | trim to the folder → clear picks → close (one step per press) |

A mistyped folder (`~/nope/x`) shows "No folder ~/nope" and no rows; nothing is guessed. nnn's
auto-enter does not apply in this model.

⌘K actions: **Edit in Fresh** (files only; terminal view), Open with default app, Open Ghostty here, New terminal
here, Quick Look, Copy path(s), Copy relative path(s), Reveal in Finder, Search below this folder,
Hand to an agent (agentkit `agent_dispatch`, files as context), Bookmark folder.

## Edit in a terminal view

**Edit in Fresh** (the first ⌘K action; ↵ on a file opens the panel with it focused, so ↵↵ edits) calls `TerminalInstancesCoordinator.open(command:directory:)` with
`$EDITOR '<file>'…` in the file's folder (paths shell-quoted, relative to that folder). The login
`zsh -il` provides `$EDITOR`; Tinycast runs `${EDITOR:-fresh}` and has a setting to override it.
**Default editor: [Fresh](https://github.com/sinelaw/fresh)** (decided 2026-10-11): non-modal,
Ctrl-key driven (fits the ⌘-key gap below), `brew install fresh-editor`; needs Ghostty's
`macos-option-as-alt = left`, which the libghostty grid must honour too. Constraints from the libghostty grid view, which this depends on:

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
| `FileSearchPreviewKind` + `FileSearchPreview` surfaces (plain text, PDF, Quick Look, media) | the preview pane (always present, focused row only, debounced) |
| `FileSearchCoordinator` actions (open, showInFinder, share, copyPath, copyName, copyFile, trash) | ⌘K actions, generalised to take one or many URLs |
| `FileSearchFilter` (type filter) | not in v1 |
| `FileSearchSession` (Spotlight) | used as is for words typed without `~`/`/` (search everywhere); not used for browsing |

New pieces:

All new code is fork-owned under `Tinycast/Features/FileNavigator/`, the same pattern as the fork's
terminal instances (docs/fork.md → Terminal instances). Upstream's Search Files files (24 upstream commits since 2026-08-01) are
**used, never edited**; a thin fork adapter maps them so an upstream API change breaks the build in
one place instead of producing merge conflicts.

- `FileNavigator/Model/FileNavigatorState.swift` — the pure reducer the prototype validates
  (folder, filter, focus, picks, panel, hidden toggle, bookmarks, recent). Foundation-only, with a
  `file-navigator-test` harness, following the `Model/` purity rule.
- `FileNavigator/Service/DirectoryLister.swift` — off-main listing with prefetched resource keys,
  streamed in chunks, cancelling stale listings; `getattrlistbulk` only if large folders measure slow.
- `FileNavigator/Service/FolderWatcher.swift` — a `DispatchSource` file-system object source on the
  visible folder only; picks keyed by path survive updates; vanished files drop out of picks.
- `FileNavigator/UI/FileNavigatorScreen.swift` + coordinator.

Upstream integration points (each `// FORK: file-navigator`, listed in docs/fork.md):
1. `PaletteMode.fileNavigator` case.
2. `RootPaletteView.screen` routing: a root query starting `~/` or `/` opens the navigator
   (Alfred's entry, beside the existing `$` → terminal hook).
3. Launcher command registration for **Browse Files**.
4. Terminal card action "Browse here" (already fork-owned code).
5. `Scripts/run-tests.sh` registers `file-navigator-test`.

No hook inside upstream's Search Files: words typed in the navigator already search everywhere.

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
2. ↵ on a file opens the ⌘K actions; ↵ again (Edit in Fresh) opens a terminal view in its folder
   running Fresh on it, usable inside the grid (renders, saves with ⌃S, quits).
8. The preview pane shows the focused row by default (text, PDF, Quick Look) without stalling navigation.
3. Picks made in two folders survive navigation and reach ⌘K → Hand to an agent as file context.
4. A 10,000-entry folder lists without blocking the main thread; typing stays responsive.
5. ⌘. reveals `.git`, `.env`, `node_modules`; ⌘. again hides them.
6. A file deleted on disk while visible disappears from the list and from picks.
7. Harness `file-navigator-test` covers the reducer cases in the prototype's walkthroughs.

## Decisions (2026-10-11)

1. Interaction: Script Kit model — the input is the path (nnn's folder + filter rejected).
2. Default editor: **Fresh** (`${EDITOR:-fresh}`, overridable).
3. Matching: **`ForkFzf` only, no Rust fuzzy libraries.** Subtree candidates (⌘F, search below this
   folder) come from a **Swift `FileManager`
   enumerator**: prefetched resource keys, streamed in batches, cancelled on the next keystroke,
   skipping hidden entries, package contents and `FileSearchIgnoreList`, capped by depth and count.
   No bundled `fd`/`rg` in v1; add a bundled `fd` only if a benchmark on `~/work` shows first rows
   clearly slower than Spotlight. `.gitignore` files are not read in v1. Content search is out of v1.
4. No Search Files hook (redundant with the navigator's global search; upstream churn).
5. ↵ on a file opens the ⌘K actions (revisit when a Monaco view exists).
6. Preview pane on by default.
