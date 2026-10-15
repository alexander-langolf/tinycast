## Why

File search has two candidate engines, Spotlight (`MDQuery`) and an in-memory ripgrep home index, plus a
Swift fzf port to rank the ripgrep output. That is about 2,500 lines of fork and feature code. It also
carries a long list of workarounds: a 1,000-candidate cap, a 120 s index refresh, provisional Spotlight
rows while the index builds, and hidden-file and Library carve-outs. `fsearch` is already installed on
this machine as a daemon-backed, always-warm index of the whole disk. It answers a query in about 4 ms,
ranks it itself, and understands inline filters (`*.md`, `src/`, `!build/`, `git:modified`). One engine
that is already warm replaces the two that Tinycast has to build and refresh.

## What Changes

- Add an `fsearch` candidate source that talks to a long-lived `fsearch stdio` child. It sends JSON-line
  requests and reads `hits` with `path`, `kind`, `mtime` and `size`. The daemon is started on demand by
  `fsearch` itself.
- Route Search Files and File Navigator global (word) search through it. fsearch's own score and order
  replace `ForkRipgrepQuery` ranking and the Spotlight fuzzy re-rank.
- Translate the type filter (All Types, Folders, Documents, Images, Audio, Videos, Archives), scopes and
  ignore patterns into fsearch inline filters, with a local post-filter for anything fsearch cannot say.
  Keep the structural drops (application bundles) and the 200-row cap.
- **BREAKING**: remove the `ForkFileSearchEngine` choice (Spotlight / ripgrep), its Settings row and the
  `fileNavigator.searchEngine` settings.json key. Delete `ForkRipgrepIndex`, `ForkRipgrepQuery`,
  `ForkRipgrepProcess`, `ForkFileSearchService`, the `FileSearchService` Spotlight candidate path and the
  index lifecycle hooks in `AppCore`.
- **BREAKING**: `fsearch` becomes a runtime prerequisite at `~/.local/bin/fsearch`. When it is missing or
  fails to start, Search Files reports "File search is unavailable" inline and does not fall back to
  another engine.
- Keep `ForkSearch` and `ForkFzf` where the launcher, clipboard, snippets and the navigator's in-folder
  name filter use them.
- Out of scope and unchanged: the navigator's folder listing and ⌘F subtree scanner
  (`RipgrepSubtreeScanner`, `SubtreeWalker`), the preview, Quick Look and action rows, and the
  blank-screen Recently Used list (see design for the open question).

## Capabilities

### New Capabilities
- `fsearch-file-search`: how Tinycast talks to the `fsearch` daemon: process lifecycle, request/response
  contract, filter translation, cancellation and the unavailable state.

### Modified Capabilities
- `search`: file search stops selecting between Spotlight and ripgrep; the engine, extended-term, bounded
  results, home-indexing and shared-index-lifecycle requirements are replaced by fsearch-backed ones.
  Launcher ranking, File Navigator word/path routing and subtree search requirements are unchanged.

## Impact

- Code: `Tinycast/Features/FileSearch/Service/` (`FileSearchService`, `FileSearchSession`),
  `Tinycast/Fork/Search/` (index, ripgrep and service files deleted; engine enum removed),
  `Tinycast/App/AppCore.swift`, `Tinycast/Features/FileNavigator/` (settings pane, global search wiring),
  `Tinycast/Features/Settings/AppSettings*`, `SettingsFileSchema`.
- Tests: `Tests/file-search-test.swift`, `file-search-session-test.swift`, `file-search-performance.swift`,
  `ripgrep-ranking-test.swift`, `fork-search-test.swift`, and `Scripts/run-tests.sh` change. A new
  harness covers the fsearch client against a fake stdio child.
- Docs: `docs/features/file-search.md`, `ripgrep-search.md` (removed), `file-navigator.md`,
  `docs/fork.md`, `docs/architecture.md`, and `openspec/specs/search/spec.md` at archive.
- Dependencies: a runtime dependency on a locally installed tool, not a linked library. This is a
  deliberate exception to "no third-party dependencies", recorded in the design.
- Permissions: fsearch reports `full_disk_access: false` today, so its index coverage depends on a grant
  made to `~/.local/bin/fsearch`, not to Tinycast. The "Tinycast asks for no file permission" invariant
  stays true, but results may be thinner than Spotlight's until fsearch has access.
