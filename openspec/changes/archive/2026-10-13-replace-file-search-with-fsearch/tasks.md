## 1. Verify the fsearch contract

- [x] 1.1 Probe the installed binary: `kind:`/extension filters, scope prefixes, `!` negations, a per-request `limit`, an `mtime` sort, and `ok:false` shapes. Record the findings in design.md, including whether recents can move.
- [x] 1.2 Capture top-5 results from the current engine for ~15 representative queries (names, paths, dotfiles, folders, multi-term) as the ranking comparison baseline.

## 2. fsearch client

- [x] 2.1 Add `FSearchLocator` (`~/.local/bin/fsearch`, then `PATH`, no shell) and unit-test it with injected paths.
- [x] 2.2 Add `FSearchClient` in `Features/FileSearch/Service/`: lazy `fsearch stdio` launch, id-keyed requests, one off-main reader, single relaunch, termination on app exit.
- [x] 2.3 Add a pure `FSearchRequest` / `FSearchResponse` model under `Features/FileSearch/Model/` (Foundation-only, injected parameters) with decoding that fails a request, not the app.
- [x] 2.4 Add `Tests/fsearch-client-test.swift` against a fake stdio child: id matching, out-of-order replies, malformed line, child death and relaunch, `ok:false`.

## 3. Query translation and post-filtering

- [x] 3.1 Build the query string from words, scopes, type filter and expressible ignore patterns; keep inexpressible patterns in `FileSearchIgnoreList`.
- [x] 3.2 Implement the post-filter sequence: application bundles, hidden components (honoring `Search hidden files`), ignore list, type filter, then the 200-row cap, preserving fsearch order.
- [x] 3.3 Add the over-fetch and single bounded re-query when filtering leaves a full page short.
- [x] 3.4 Update `Tests/file-search-test.swift` for query translation, filter order and the cap.

## 4. Wire the session and navigator

- [x] 4.1 Make `FileSearchSession` use the client as its production `SearchOperation`, keeping the injectable seam, the 120 ms debounce, no debounce for blank, and the revision/request/filter staleness checks.
- [x] 4.2 Route File Navigator global (word) search through the same client and ordering.
- [x] 4.3 Show "File search is unavailable" for a missing executable, failed start or decode failure; no fallback engine.
- [x] 4.4 Keep the blank-screen Recently Used list on its existing Spotlight path, trimming `FileSearchService` down to recents and scope resolution.
- [x] 4.5 Update `Tests/file-search-session-test.swift` for the new operation, supersession and the failed state.

## 5. Remove the old engines

- [x] 5.1 Delete `ForkRipgrepIndex`, `ForkRipgrepQuery`, `ForkRipgrepProcess`, `ForkFileSearchService` and `ForkFileSearchEngine` (+ `+SettingsFile`), keeping what the subtree scanner and `DirectoryLister` still need from `ForkRipgrepPolicy`.
- [x] 5.2 Remove `fileSearchEngine`, its `SettingsFileKey` binding and `fileNavigator.searchEngine`; remove the index lifecycle hooks (`paletteOpened`, `configure`, `useForkIndex`) from `AppCore` and the sessions.
- [x] 5.3 Replace the engine row in the File Navigator settings pane with fsearch status: discovered path, running or not, and the Full Disk Access note.
- [x] 5.4 Delete or rewrite `Tests/ripgrep-ranking-test.swift` and the index portions of `Tests/fork-search-test.swift`; update `Tests/file-search-performance.swift` to benchmark the client. Update `Scripts/run-tests.sh`, and run `xcodegen generate` if files moved.

## 6. Docs and verification

- [x] 6.1 Rewrite `docs/features/file-search.md`, delete `docs/features/ripgrep-search.md`, and update `file-navigator.md`, `docs/fork.md` (record the external-tool exception), `docs/architecture.md` and `docs/README.md`.
- [x] 6.2 Compare the new results to the 1.2 baseline and note any accepted ranking differences.
- [x] 6.3 Run `./Scripts/run-tests.sh`, `./Scripts/lint.sh` and the Debug build with no new warnings, and confirm `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` returns nothing.
- [ ] 6.4 Launch the Dev build: Search Files, the type filter, navigator word search, a missing-executable run (rename the binary), and a killed-daemon run.
