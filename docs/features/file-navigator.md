# File Navigator

The [ripgrep search experiment](ripgrep-search.md) now selects the candidate source for global words
and ⌘F. The original Swift/Spotlight decisions below remain historical where that document supersedes
them. Direct folder listings and their reveal toggle are unchanged.

A fork-owned keyboard folder browser in `Tinycast/Features/FileNavigator/`. Implementation is on
`al/file-navigator`; the settled 2026-10-11 decisions are preserved below. Compilation, harness execution
and rendered acceptance remain for Claude's verification pass.

## Invariants

- The input is the path: `~/github/agentkit/li` lists that folder, filtered by `li`. Words use an
  independent upstream `FileSearchSession` with the configured Search Files scopes, even when the
  Search Files launcher command is off. Missing folders have no rows; no closest-folder guessing.
- `Model/` imports Foundation only. Home, known folders and rows are injected. `ForkSearch` terms
  and `ForkFzf` hits supply extended matching; no dependency, Rust component or helper binary is added.
- AppCore owns the lazy coordinator. Views receive it through the palette environment; no feature
  singleton is introduced. All new feature code is fork-owned; upstream `Features/FileSearch/` is reused
  with one marked action-menu hook for Show in File Navigator.
- Listings and ranking run off-main. Every batch, ranking result and preview checks the current request
  identity, destination and cancellation before publishing. Leaving or hiding cancels owned work and
  the folder watcher. External actions validate the same destination and target set after suspension.
- Picks are absolute logical paths and survive navigation within an open navigator. A visible-folder
  refresh drops only paths proven missing; hiding entries does not clear picks. Closing releases picks
  and listing memory. Actions revalidate targets and report unavailable items through Tinycast's HUD,
  retaining the current screen.
- Application and installer packages are file rows. Logical symlink paths are preserved; canonical
  ancestor cycles are rejected and recursive traversal tracks canonical directories. Hidden and
  ignored entries are suppressed by default; ⌘⇧. admits them in direct listings only. Subtree walks
  always exclude hidden entries and ignored folders, including excluded roots; package roots cannot
  be browsed and package descendants stay excluded.
- Only the visible folder is watched. Recursive scans stop at depth 8 and publish batches of 500.
  Swift counts 50,000 visited entries; ripgrep caps 50,000 emitted/derived rows and respects `.gitignore`.
  File contents are not searched.
- Preview is on by default, focused-row only, debounced 90 ms, and uses upstream preview surfaces.
  ⌘Y toggles that pane; Quick Look is a separate action using the upstream in-palette overlay.
- Bookmarks and recent folders use bundle-scoped defaults. Editor preference uses AppSettings,
  `SettingsFileKey` and the existing schema. Editor commands stay device-local in backups.
- Hand to an agent v1 copies context only. It never dispatches an agent or sends a message.

## Entry points

- Typing `~` or `/` in the launcher: either opens the navigator at `~/`; these are its only two
  trigger characters. A longer `~/…` or `/…` (a paste) opens that path; the filesystem root is
  reached with ⇧Tab up from home or by pasting a path such as `/usr`.
- Launcher command **Browse Files** (and an optional global shortcut), starting in the last folder
  browsed, else `~`.
- From a **terminal view**: a card action opens the navigator in that instance's current directory
  (OSC 7 cwd the session already tracks).
- From **Search Files**: ⌘K → Show in File Navigator opens the result's parent folder with the
  file or folder row focused after loading.
- Typing a path (`~/…` or `/…`) in the root palette routes here, as `$` routes to terminals.

## Interaction model

Follows Script Kit Next's File Search (`src/file_search/directory.rs`): **the input is the path.**
`~/github/agentkit/li` lists `~/github/agentkit/` filtered by `li`; input that does not start with
`~` or `/` searches everywhere. Single list (no Miller columns — the palette is narrow) plus an
preview pane, **on by default** (⌘Y hides it). The input owns letters, so commands use arrows, Tab
and modifiers.

| Key | Action |
|---|---|
| type | edits the path; the last segment fuzzy-filters its folder (`ForkFzf`, fzf syntax: `'exact`, `^prefix`, `!exclude`) |
| words without `~`/`/` | global words through Search Files' session and the selected candidate engine |
| `/` | descends into the folder the input names |
| ⌫ | edits the input; across a `/` it lands in the parent, already filtered by the folder you left; clearing the whole input returns to the launcher root |
| Tab | completes the focused row into the input (a folder descends) |
| ⇧Tab | parent folder, with the folder you came from focused (from a mistyped path: back to the last real folder) |
| ↑ ↓ | move focus |
| ↵ | folder: descend. File, or any picks: **open the ⌘K action panel** (first action: Edit in Fresh) |
| Space | pick / unpick (the pick list survives folder changes, nnn-style) |
| ⌘A | pick every visible row |
| ⌘K | action panel for the picked files, else the focused row |
| ⌘B | bookmarks + recent folders |
| ⌘Y | hide / show the preview pane (shown by default) |
| ⌘⇧. | show hidden and ignored entries in direct listings; recursive exclusions remain enforced |
| ⌘O | Ghostty app tab in the current folder |
| ⌘T | Open Ghostty here: an embedded Ghostty terminal view in the current folder |
| ⌘F | search below this folder: streamed ripgrep or Swift walk + `ForkFzf`; ⌘F again returns to the folder listing |
| ⌃G | close and `cd` the originating terminal view into the current folder |
| Esc | trim to the folder → clear picks → close (one step per press) |

A mistyped folder (`~/nope/x`) shows "No folder ~/nope" and no rows; nothing is guessed. nnn's
auto-enter does not apply in this model.

Known-folder caches do not establish the recovery destination. The coordinator separately remembers
the last folder verified by a successful listing. If a cached path has vanished, its input and missing
status remain visible with no rows or preview; Shift-Tab or Escape returns to that verified folder.
If the verified folder itself is gone, recovery uses home. Recovery validation runs off-main and checks
request identity and cancellation before changing state. Permission denial retains the grant-access
row instead of claiming a folder is missing.

An empty Bookmarks & Recent panel shows a disabled "No bookmarks or recent folders yet" row.

⌘K actions: **Edit in Fresh** (files only; terminal view), Open with default app, Open Ghostty here
(embedded terminal view, not the Ghostty app), Open in Ghostty app, Quick Look, Copy path(s), Copy
relative path(s), Reveal in Finder, Show in File Navigator (one target in global or ⌘F subtree search
only; no shortcut), Search below this folder, Hand to an agent (copy absolute-path context), Bookmark
folder. Show in File Navigator replaces the input with the target's parent folder, leaves subtree
search, and focuses the target after loading; plain folder listings omit it. Picks and terminal origin
survive this navigation.

## Edit in a terminal view

Edit in Fresh is the first action for targets containing files; folders are excluded from its arguments.
The first file's parent is the working folder; all file arguments are paths relative to it, single-quoted
with embedded apostrophes escaped. The command is `${EDITOR:-fresh}` followed by those arguments.
**Settings → File Navigator → Editor command** can override the command, including shell arguments;
blank restores `$EDITOR` / Fresh. The settings mirror exposes `fileNavigator.editor` and
`fileNavigator.commands`. Install the default with `brew install fresh-editor`; if absent, the login
shell's own command-not-found error appears in the terminal output.

**File search engine** shares this pane. `fileNavigator.searchEngine` mirrors `spotlight` / `ripgrep`;
the latter defaults on when found. A missing binary is explained in the pane and uses Spotlight.

`TerminalInstancesCoordinator.open(command:directory:isEditor:)` marks the instance before starting
its shell. Editor instances use the existing palette width and request up to 680 scaled points of
output, bounded by screen height; columns and rows use the existing measured monospaced faces.
Normal terminals retain their 340-point output cap. Font/theme changes resize each instance according
to its role. Actual Fresh usability and geometry on different screens remain unverified.

The editor grid translates ⌘S/Z/X/C/V/A/F to the corresponding Ctrl letters, through Ghostty's encoder.
⌘⇧Z sends Ctrl-Y: that is redo in Fresh's current **default** keymap, not Ctrl-Shift-Z. Ctrl-C in an
editor reaches Fresh rather than the terminal coordinator's interrupt action. Other Command keys keep
their app meaning (including ⌘W closing the terminal card); quit Fresh with Ctrl-Q. The grid's
`performKeyEquivalent` also claims these keys ahead of AppKit's menu actions.

Bindings were read on 2026-10-11 from Fresh's [README](https://github.com/sinelaw/fresh),
[keyboard documentation](https://getfresh.dev/docs/configuration/keyboard) and
[default keymap](https://github.com/sinelaw/fresh/blob/master/crates/fresh-editor-core/keymaps/default.json).
The [macOS keymap](https://github.com/sinelaw/fresh/blob/master/crates/fresh-editor-core/keymaps/macos.json)
changes redo to Ctrl-R and Ctrl-A to line start; the adapter deliberately targets the default map.
User-selected macOS/custom keymaps or another editor may need their own bindings; Tinycast does not
rewrite editor configuration.

Fresh recommends Ghostty `macos-option-as-alt = left`. The embedded grid already prefixes printable
Option input with Escape and encodes Option on special keys as Alt. It treats **both** Option keys
this way; it does not reproduce left-only Option handling. Direct Ctrl/Shift letters still use the
existing raw-byte path, whereas mapped Command letters go through the protocol-aware encoder.
Mouse selection, clipboard integration and Kitty-protocol behavior require runtime review.

With `forkTerminalGhostty = NO`, Edit in Fresh sends the same quoted command to real Ghostty using
`zsh -ilc`: AppleScript's surface `command` when Ghostty is running, `-e /bin/zsh -ilc` at cold launch.
The [Ghostty AppleScript docs](https://ghostty.org/docs/features/applescript) and installed
`Ghostty.sdef` declare that surface field. The launched surface waits after command exit to keep
missing-editor errors visible. No editor is run in the old log renderer.

## Reuse from Search Files

| Piece | Reused as |
|---|---|
| `FileSearchResult` (url, name, parent, isDirectory, home-abbreviated path) | the row value, built from a directory listing instead of Spotlight |
| fork-owned `ForkFzf` / `ForkSearch` (`Tinycast/Fork/Search/`, fzf v2 + extended syntax) | the in-folder filter ranking, same syntax as every other list |
| `FileSearchIgnoreList` (+ structural hidden / bundle rules) | default hiding; ⌘⇧. reveals only in direct listings; recursive exclusions always apply |
| `FileSearchPreviewKind` + `FileSearchPreview` surfaces (plain text, PDF, Quick Look, media) | the preview pane (always present, focused row only, debounced) |
| `FileSearchCoordinator` actions (open, showInFinder, share, copyPath, copyName, copyFile, trash) | ⌘K actions, generalised to take one or many URLs |
| `FileSearchFilter` (type filter) | not in v1 |
| `FileSearchSession` | selected global candidate engine for words without `~`/`/`; not used for browsing |

New pieces:

All new code is fork-owned under `Tinycast/Features/FileNavigator/`, the same pattern as the fork's
terminal instances (docs/fork.md → Terminal instances). Upstream's Search Files files (24 upstream commits since 2026-08-01) are
reused through thin fork adapters. The only navigator hook in Search Files adds a fork-owned menu
action; listing, search and preview behavior remain upstream.

- `FileNavigator/Model/FileNavigatorState.swift` — the pure path reducer the prototype validates
  (folder, filter, focus, picks, panel, hidden toggle, bookmarks, recent). Foundation-only, with a
  `file-navigator-test` harness, following the `Model/` purity rule.
- `FileNavigator/Service/DirectoryLister.swift` — off-main listing with prefetched resource keys,
  streamed in chunks, cancelling stale listings and ranking. No `getattrlistbulk` optimisation in v1.
- `FileNavigator/Service/FolderWatcher.swift` — a `DispatchSource` file-system object source on the
  visible folder only; picks keyed by path survive updates; vanished files drop out of picks.
- `FileNavigator/UI/` — screen, coordinator, list and preview composition; `Settings/` owns the editor pane.

Upstream integration points (each `// FORK: file-navigator`, listed in docs/fork.md):
1. `PaletteMode.fileNavigator` case.
2. `RootPaletteView.screen` routing: a root query of `~` or `/` opens the navigator at `~/`; a longer
   `~/…` or `/…` opens that path
   (Alfred's entry, beside the existing `$` → terminal hook).
3. Launcher command registration for **Browse Files**.
4. Terminal card action "Browse here" (already fork-owned code).
5. `Scripts/run-tests.sh` registers `file-navigator-test`.
6. `FileSearchActionsMenu` adds the fork-owned Show in File Navigator action.

The Search Files hook only enters the navigator; words typed in the navigator still use its own session.

## Lifecycle and actions

The watcher uses a DispatchSource over the visible folder's descriptor, debounced 150 ms. A refresh
rechecks picked paths across folders; recursive descendants are not separately watched. Navigation
or ⌘F starts a fresh cancellable request. Global words use the upstream session's own supersession
rules and a revision-scoped observation bridge. Scope/ignore preference changes re-run the active query.
Direct listings and subtree walks share root resource-value validation, including package rejection
and permission-error classification. The recursive reveal policy is independent of `showHidden`.

Actions use `FileNavigatorActionsAdapter` for multi-target open, reveal and copy, retaining upstream
single-target actions. Relative copies compute paths from the current folder (including `../`).
Show in File Navigator seeds `state.pendingFocus` with the target's absolute logical path and forces
a direct listing; the existing batch receiver applies that focus and clears it on the final batch.
Quick Look opens the first target in the upstream overlay; the preview still follows only the focused
row. Agent context is a short header and one absolute path per line; a HUD says
“Context copied — paste into an agent”. No prompt or direct dispatch is included in v1.

Browse here retains a weak reference to the originating terminal instance. Ctrl-G revalidates the
folder and instance, then sends a quoted `cd --` only when that shell accepts a command, hides the
palette and focuses that terminal. A busy or closed origin produces a HUD and leaves navigation open.

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
3. Picks made in two folders survive navigation and reach ⌘K → Hand to an agent as copied file context.
4. A 10,000-entry folder lists without blocking the main thread; typing stays responsive.
5. In direct listings, ⌘⇧. reveals `.git`, `.env`, `node_modules`; ⌘⇧. again hides them. Subtree walks
   skip hidden/ignored entries and package contents regardless of that toggle.
6. A file deleted on disk while visible disappears from the list and from picks.
7. Harness `file-navigator-test` covers the reducer cases in the prototype's walkthroughs.
8. The preview pane shows the focused row by default (text, PDF, Quick Look) without stalling navigation.

## Verification handoff

The model harness is registered as `file-navigator-test` but has not been executed. It covers the
prototype path walkthroughs, actual picks from two folders and their shared action-target policy,
empty-input Backspace, actions, missing folders, parent focus, disappearance, ordering,
extended filters, shell quoting, relative paths and the editor key policy.
Only XcodeGen generation and `swiftc -parse` are permitted in the implementation session; neither
proves Swift 6 type checking, Observation expansion, runtime behavior or layout.

Claude should run fork audit, the full harness runner, lint, model purity check and a clean Debug
build, then Dev acceptance 1–8. Check denied TCC access, 10,000-entry responsiveness, cancellation
while typing or hiding, live deletion, bookmarks across relaunches, origin cd, multi-folder editor
arguments, editor override, Fresh render/save/quit and default keybindings, preview types, and the
real Ghostty fallback with its renderer disabled. The plan records pre-existing form-input-test and
settings-history-test failures; verify their actual current status rather than assuming it.
Also verify recursive exclusions with reveal enabled, denied/package roots, cached folders deleted
before revisiting, deletion of the recovery folder, empty-input Backspace routing, and the first-use
empty bookmarks panel. No correction-session harness or runtime checks were executed.

## Decisions (2026-10-11)

1. Interaction: Script Kit model — the input is the path (nnn's folder + filter rejected).
2. Default editor: **Fresh** (`${EDITOR:-fresh}`, overridable).
3. Matching: **`ForkFzf` only, no Rust fuzzy libraries.** Subtree candidates (⌘F, search below this
   folder) come from a **Swift `FileManager`
   enumerator**: prefetched resource keys, streamed in batches, cancelled on the next keystroke,
   skipping hidden entries, package contents and `FileSearchIgnoreList`, capped by depth and count.
   No bundled `fd`/`rg` in v1; add a bundled `fd` only if a benchmark on `~/work` shows first rows
   clearly slower than Spotlight. `.gitignore` files are not read in v1. Content search is out of v1.
4. Search Files gets one small Show in File Navigator action hook; search itself stays upstream.
5. ↵ on a file opens the ⌘K actions (revisit when a Monaco view exists).
6. Preview pane on by default.
