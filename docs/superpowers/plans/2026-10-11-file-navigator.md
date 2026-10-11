# File Navigator — implementation plan

Spec: [docs/features/file-navigator.md](../../features/file-navigator.md) (decisions settled 2026-10-11).
Branch: `al/file-navigator` from `main`. Throwaway prototype (state model reference only):
`docs/prototypes/file-navigator.prototype.html` on branch `proto/file-navigator`
(`git show proto/file-navigator:docs/prototypes/file-navigator.prototype.html`) — its `Nav` module's
`parseInput` / `reducePath` / `actionsFor` are the validated behaviour to port, path model only.

Rules: `AGENTS.md`, `docs/fork.md` (fork-owned feature folder, `// FORK: file-navigator` on every
upstream hook, hooks listed in the Upstream hooks table, `Scripts/fork-audit.sh` must pass), Swift 6
strict concurrency, `Model/` stays Foundation-only. Upstream Search Files files are **used, never edited.**

## Task 1 — Pure state model + harness

- `Tinycast/Features/FileNavigator/Model/FileNavigatorPath.swift` — parse the input
  (`~`/`/` → folder + last-segment filter; otherwise a global words query; missing folder → `.missing`),
  tilde expansion against a passed-in home path, parent, display form. Pure.
- `Tinycast/Features/FileNavigator/Model/FileNavigatorState.swift` — value type + reducer:
  input, folder, filter, focus, picks (paths, survive folder changes), panel (`actions`,
  `bookmarks`), preview flag (default on), showHidden, subtree mode (⌘F), bookmarks, recent.
  Actions per the spec's key table: type, backspace (crossing `/` → parent filtered by the left
  folder), tab (complete focused; folder descends), shiftTab (parent, focus the folder you came
  from; from `.missing` → last real folder), up/down, enter (folder descends; file or any picks →
  open actions), space, selectAll, esc ladder (trim to folder → clear picks → close), toggles.
  Rows are an input (the listing), sorted folders-first then name; with a filter, scored by
  `ForkSearch`/`ForkFzf` (the fork scorer, extended syntax).
- `FileNavigatorAction.swift` — the ⌘K action list for the targets (picks, else focused row):
  Edit in Fresh (files only), Open with default app, Open Ghostty here, New terminal here,
  Quick Look, Copy path(s), Copy relative path(s), Reveal in Finder, Search below this folder,
  Hand to an agent, Bookmark folder.
- `Tests/file-navigator-test.swift` — one case per prototype walkthrough (path is the input,
  words search everywhere, picks across folders → actions, hidden toggle, esc ladder, mistyped
  folder, vanished file drops from picks). Register in `Scripts/run-tests.sh` with the shipped
  model files and the fork search sources (`// FORK: file-navigator`).

## Task 2 — Listing, subtree walk, watcher (Service)

- `Service/DirectoryLister.swift` — off-main `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)`
  with only displayed keys (isDirectory, isSymbolicLink, isHidden, isPackage, contentModificationDate,
  fileSize), returns `FileSearchResult` values (reuse the upstream type, don't edit it). Packages are
  files. Hidden entries and `FileSearchIgnoreList` matches only when showHidden. Cancellable; stale
  results never publish (same supersession rule as Search Files).
- `Service/SubtreeWalker.swift` — ⌘F: `FileManager.enumerator` from the current folder, skipping
  hidden, package descendants and ignore-list folders, depth cap 8, entry cap 50,000, streaming
  batches (e.g. 500) to the caller, cancelled on the next keystroke; rows show their subfolder.
- `Service/FolderWatcher.swift` — `DispatchSource.makeFileSystemObjectSource(.write)` on the visible
  folder only, debounced (~150 ms), triggering a re-list; picks keyed by path, vanished paths dropped.
- TCC-denied folder (`EPERM`) → a single "grant access" row (opens Privacy settings), never empty.
- Global words query: reuse upstream `FileSearchSession`/`FileSearchService` as is (Spotlight).

## Task 3 — Screen, coordinator, preview, actions (UI)

- `UI/FileNavigatorScreen.swift` (a `PaletteScreen`) + `UI/FileNavigatorCoordinator.swift`
  (owned lazily by `AppCore`, like the terminal instances coordinator). The input shows the path;
  the list uses the palette's existing row look (follow `FileSearchList`); preview pane on the
  right, on by default, ⌘Y toggles, focused row only, debounced, reusing upstream
  `FileSearchPreview` / surfaces as is.
- ⌘K action panel: reuse the palette's existing action-panel pattern (as Search Files' actions do).
  Actions call existing code: `FileSearchCoordinator` open/showInFinder/copyPath/copyName for single
  targets (generalise via a small fork adapter for many URLs — do not edit the upstream coordinator),
  `TerminalGhosttyLauncher.openShell(in:)`, `TerminalInstancesCoordinator.open(command:directory:)`,
  Quick Look via the existing `FileSearchQuickLook`.
- **Hand to an agent (v1):** copy an agent-ready context block (absolute paths, one per line, with
  a short header) to the clipboard and show a notice "Context copied — paste into an agent".
  Direct dispatch through the agentkit MCP is a later step (it needs a prompt field).
- Bookmarks + recent: persisted in `UserDefaults` under the bundle id (fork-owned keys).
- Entry points (each a hook, table in docs/fork.md):
  1. `PaletteMode.fileNavigator`.
  2. `RootPaletteView.screen`: a launcher query starting `~/` or `/` routes to the navigator with that
     input (next to the `$` terminal hook).
  3. Launcher command `Browse Files` (`CommandID`, `CommandCatalog`) starting in the last folder, else `~`.
  4. Terminal card action "Browse here" (fork-owned card) opening at the instance's cwd.

## Task 4 — Edit in Fresh

- Edit in Fresh = `TerminalInstancesCoordinator.open(command: "fresh <quoted files>",
  directory: <file's folder>)`, files relative to that folder, single-quoted.
- Mark such instances as editor instances; give them the largest grid layout `TerminalInstanceMetrics`
  allows.
- `GhosttyGridView.keyDown` drops ⌘ combos. For editor instances only, map ⌘S ⌘Z ⌘⇧Z ⌘X ⌘C ⌘V ⌘A ⌘F
  to the ⌃ equivalents Fresh uses (check Fresh's default keymap in its docs/README:
  https://github.com/sinelaw/fresh, https://getfresh.dev/docs/configuration/keyboard) and send them
  through the grid's key encoder. Other ⌘ keys keep their app meaning.
- If the editor isn't installed (`command -v` fails in the shell) the shell's own error shows; add
  a one-line hint in the feature doc (`brew install fresh-editor`). Option-as-Alt: note in the doc
  that Fresh expects Ghostty's `macos-option-as-alt`; make the grid send ⌥ as Esc-prefix (it already
  does for printable keys) and note any gap.

## Task 5 — Docs and fork bookkeeping

- `docs/features/file-navigator.md`: turn the spec into the feature doc (invariants first, like
  `file-search.md`), keep the decisions section.
- `docs/fork.md`: a "File navigator" section + every hook in the Upstream hooks table.
- `xcodegen generate` after adding files (per docs/development.md); never hand-edit pbxproj.

## Verification (Claude, after implementation)

`Scripts/fork-audit.sh`, `./Scripts/run-tests.sh` (expect the two pre-existing failures
form-input-test and settings-history-test only), `./Scripts/lint.sh`, purity grep, clean Debug
build, then Dev: spec acceptance criteria 1–8.
