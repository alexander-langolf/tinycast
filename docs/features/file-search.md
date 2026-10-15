# Search Files

Search Files is an on-demand palette screen for opening files and folders from the folders the user
configures. Typed queries are answered by the local `fsearch` daemon; the blank
screen lists recent files through Spotlight. It is reached from the built-in Search Files launcher command
— or its own global shortcut — after the feature is enabled in Settings.

## Invariants

- **`fsearch` is the only source for typed queries.** `FSearchClient` owns one long-lived `fsearch stdio`
  child, started on the first nonblank query and terminated by `AppCore.prepareForTermination`. The
  palette session and File Navigator's global search share it. Tinycast builds no file index.
- **fsearch's order is the ranking.** Rows are only ever dropped, never re-scored: application bundles,
  hidden components (unless `Search hidden files` is on; `.git` and `.Trash` always), ignore-list matches,
  paths outside the scopes, and rows the type filter rejects. Then at most 200 are published.
- **Everything under `Model/` stays Foundation-only and pure.** `FSearchProtocol`, `FSearchQuery` and
  `FSearchLocator` take every environment fact as a parameter; `fsearch-client-test` runs the client
  against a fake `fsearch` child.
- **The filter belongs to the query, not to the rows.** `FileSearchSession` keys its de-dup and its
  supersession check on the query and the filter together, so narrowing re-runs the same words.
- **Scopes are enforced locally, never pushed.** A path word is a fuzzy term to fsearch and reorders
  results, so the query text carries only the words and the `type:` filter.
- **`~/Library` is never searched by itself.** A home scope admits `Library/CloudStorage` and iCloud
  Drive only. A folder the user adds under `~/Library` by hand is admitted.
- **There is no fallback engine.** A missing executable, a failed start, a dead child or an undecodable
  reply leaves the session `.failed` and the screen says "File search is unavailable". A child that exited
  is relaunched once on the next request.
- **A superseded query never publishes.** Replies are paired by request id, and the session checks its
  revision and request after the await, so a late reply cannot replace newer rows. Editing the scopes or
  the patterns cancels the session for the same reason.
- **Tinycast asks for no file permission.** fsearch's reach is whatever its own binary has been granted;
  Settings ▸ File Navigator reports `full_disk_access` from `fsearch status` and says so when it is off.
- **File Search is off by default, and off means no entry point or process.** The child is never
  started at launch.
- **Share is the one system popover, and the palette stays up under it.** Unchanged: the picker is
  retained on the coordinator and anchored to `PaletteWindowController.anchorView`.

## Query path

`FileSearchSession.search` retains the previous rows, debounces typed input for 120 ms, then drives the
operation. `FSearchClient.search` builds the query with `FSearchQuery.text` — the typed words, plus
`type:image|audio|video|doc|archive` for a typed filter — and asks for 400 hits. `FSearchQuery.rows`
turns them into rows. If a full page was filtered below 200 rows, one more request asks for 2,000.
Folders is answered from each hit's `kind`, since fsearch has no folder type.

fsearch answers in a few milliseconds; end to end, a typed query measured 7–90 ms on the developer
machine (2026-10-13). `Tests/file-search-performance.swift` reports first and repeated latency for the
blank screen and typed queries against the live daemon; it stays outside `run-tests.sh` because it depends
on the machine's index.

## Recently used

An empty query is a request of its own and skips the debounce. `FileSearchQuery.RecentStamp` names the
two Spotlight stamps it asks about — changed in the last 3 days, used in the last 30 — and the service
runs one sorted query per stamp, merging their heads by date before publishing 20. This is the one
remaining `MDQuery` use: fsearch has no `mtime` sort. The type filter and the same structural drops
apply.

## Type filter

`FileSearchFilter` is the header's **All Types** pop-up: All Types, Folders, Documents, Images, Audio,
Videos, Archives. Each case names its fsearch `type:` word (`fsearchType`) and answers `admits(isDirectory:)`;
its `UTType`s are kept for the Spotlight recents path. The filter lives on `PaletteState`, resets on every
summon and is never persisted. ⌘P and the header button open it through `PaletteFilterAction`.

## Scopes and ignore patterns

`FileSearchPolicy` is the resolved answer to "what does this scope list mean": the roots, the compiled
ignore list and `showsHidden`. It is rebuilt when a setting changes, never per keystroke. Scopes are stored
tilde-abbreviated in `fileSearchScopes`; an empty list searches nothing.

`FileSearchIgnoreList` compiles each pattern once into one of three buckets:

| Pattern shape | Matched against | Example |
| --- | --- | --- |
| no `/`, no metacharacters | any path component, case-folded, via a `Set` | `node_modules` |
| no `/`, has `*` `?` `[` | any path component, via `fnmatch` | `*.tmp` |
| contains `/` | the whole absolute path, via `fnmatch` | `**/[Cc]ache/**` |

`fnmatch` runs with `FNM_CASEFOLD` and without `FNM_PATHNAME`, so `*` spans `/`. The shipped rules
(`node_modules`, `DerivedData`, `build`, `dist`, `target`, `Pods`) are compiled in and never persisted, so
they cannot be switched off. fsearch does not exclude build output itself, which is why over-fetching
matters.

## Palette and actions

Unchanged by the engine: `FileSearchScreen.rows` is the flat selection order rendered by `FileSearchList`,
beside a preview pane (Name, Where, Type, Size, Created, Modified) whose stage is `FileSearchPreviewKind`'s
surface — media player, PDFKit, plain text or QuickLook. Quick Look (⌘Y) draws inside the panel and
Escape is answered by `PalettePanel.onEscape`.

| Row | Chord | What it does |
| --- | --- | --- |
| Open File / Open Folder | ↵ | A folder opens in the File Navigator (fork hook); a file uses `NSWorkspace` |
| Show in Finder | ⌘↵ | reveals and dismisses |
| Quick Look | ⌘Y | the in-panel overlay |
| Share… | — | `NSSharingServicePicker`, anchored to the palette's trailing edge |
| Copy File | ⇧⌘C | the file itself on the pasteboard through `PasteboardFiles.write` |
| Copy Name | ⌥⌘C | through `Paster`, palette stays open |
| Copy Path | ⌃⌘C | the standardized path, palette stays open |
| Paste File to … | ⇧⌘V | `Paster.pasteFile` into the app the palette was summoned over |
| Move to Trash | ⌃X | `FileManager.trashItem` off the main actor, then the row leaves the session |

A row drags its file out as a copy through `onRowClick(drag:)` ([clipboard.md](clipboard.md#dragging-out)).
The first in-flight query says nothing; an empty completed query says what the active filter admits;
a blank screen with no recents says "Type to search files and folders".

## Invocation

Settings ▸ File Search owns the `fileSearchEnabled` switch (off when absent), the scope list, the ignore
patterns and the Search Files command row; all are ordinary settings carried by backups. `AppCore`
observes the switch and asks `FileSearchCoordinator` to project `CommandID.searchFiles` into the launcher.
The coordinator guards entry into `.fileSearch`, so neither a stale command nor the global shortcut can open
the screen once disabled. `SettingsTab.ownedCommands` names the pane as the command's only one.
