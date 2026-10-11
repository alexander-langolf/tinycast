## Invariants

- This experiment changes candidate generation only. `ForkFzf` and `ForkSearch` remain the matcher;
  no Rust library, bundled executable, content search or on-disk index is added.
- AppCore owns one `ForkRipgrepIndex`. Both production file sessions use it through the existing
  `// FORK: search` seam. Injected harness operations and blank-query recents retain upstream behavior.
- The engine preference lives in Settings → File Navigator as **File search engine** and in
  `fileNavigator.searchEngine` in settings.json (`spotlight` / `ripgrep`). Unset chooses ripgrep when
  available, otherwise Spotlight. The experimental, machine-dependent choice stays out of backups.
- Discovery runs without a shell: `/opt/homebrew/bin/rg`, `/usr/local/bin/rg`, then PATH entries.
  Missing ripgrep uses Spotlight; the pane reports that fallback even if ripgrep is selected.
- Indexing starts on the first nonblank file search. After first use, palette opening refreshes an
  index older than two minutes. A refresh serves the old immutable snapshot, then swaps the whole
  array on the main actor. Changed engine/ignore settings invalidate it and cancel the old producer.
- Processes, pipe reads, NUL-delimited chunk parsing, exclusions and ranking run off-main. Owned
  cancellation terminates the child and waits on `ProcessExit`; app termination cancels the index.
  Query cancellation never cancels a shared index build needed by another session.
- Hidden paths, ignored trees and package descendants stay excluded recursively, regardless of the
  navigator's direct-listing reveal toggle. Root access/package validation precedes subtree scanning.
- A ready home index replaces both Spotlight passes. Until it is ready, Search Files and navigator
  global words use the existing Spotlight path, then publish the indexed answer for the same request.
  Scopes outside home use Spotlight for the whole query. Recent files always use Spotlight.

## Candidate sources

The home command is `rg --files --no-messages --null`, with cwd home, anchored exclusions for
`Library/` and `.Trash/`, and case-insensitive negative globs from the compiled defaults and safe
user patterns. Name patterns and absolute patterns rooted inside the scan directory can prune the
walk. Patterns whose glob semantics cannot safely be translated remain enforced by the original
`FileSearchIgnoreList` on absolute paths. The compiled six exclusions cannot be disabled.

Ripgrep's own ignore rules, including `.gitignore`, apply. Hidden files remain suppressed and symlinks
are not followed. Home Library/cloud content and external roots are absent from this index; select
Spotlight to retrieve them. A manually configured Library scope therefore stays excluded in ripgrep
mode. Parent directories are derived from emitted files, deduplicated and marked with a trailing `/`
inside the index so folder filtering can run before the scoring cap. Empty directories have no source
file and are unavailable. Directory markers are removed before scoring or creating row values.

The navigator's ⌘F scanner runs the same executable with its absolute folder argument, cwd that folder,
and `--max-depth 8`. It streams into the existing batch receiver, with 500 rows per batch and a cap of
50,000 emitted file/derived-directory rows. Ripgrep does not expose visited-entry counts, so this cap
counts visible candidates rather than every visited entry as the Swift walker does. Package ancestors
are checked with `DirectoryLister`, including package types beyond `.app` / `.pkg`. Direct listings
continue to use Swift and their existing hidden/ignored reveal behavior.
Subtree scanning emits a package ancestor once as an opaque file row and rejects its descendant rows;
rg can still enumerate those descendants internally. Empty packages, like empty directories, have no
emitted file from which to derive a row.

## Query and cancellation

Each positive parsed word must pass a case-insensitive path subsequence prefilter; extended syntax is
then judged by `ForkSearch.hit`. Negated terms still apply to filenames only. ASCII prefiltering scans
bytes; Unicode paths/words fall back to the existing case/diacritic folding. `ForkFzf`'s optional path
scheme uses slash delimiters, the base whitespace bonus and a delimiter initial boundary; other surfaces
retain its standard scheme. Existing filename/folder weights (1 / 0.6) remain, followed by filename
length and incoming index as tie breakers. The same fzf alignment implementation handles both schemes.
Scheme constants follow [fzf's algorithm source](https://github.com/junegunn/fzf/blob/master/src/algo/algo.go).

A bounded worst-first heap keeps the top `FileSearchQuery.candidateLimit` (1,000) paths. Only those
paths fetch resource values or become `FileSearchResult`s; up to 200 verified rows publish. Folder
markers filter before the heap, while content-type filters use filesystem metadata afterward. Type
filters can return fewer rows when higher-scoring files of other types occupy the candidate cap.

The fork service owns each query task. New input cancels it immediately; cancellation propagates to
its detached scorer. Cancellation is checked at entry, every 128 index paths and each metadata read.
Publications validate the service revision and the upstream session's revision/query/filter. Removed
rows cannot reappear in a late batch. The upstream 120 ms debounce remains; query latency estimates
below exclude that debounce.

`ForkRipgrepProcess` has one off-main stdout reader. Its lock protects start/cancel and the child
lifecycle; the documented unchecked Sendable boundary never exposes the mutable parsing buffer to
another reader. Cancellation handlers are Sendable closures and only call that locked cancellation
method. There are no readability handlers or DispatchSource callbacks. The termination callback comes
from the existing nonisolated `Process.runObservingExit()` helper and signals its Sendable semaphore.
Navigator batch delivery is explicitly `@MainActor @Sendable`, and the receiver retains its existing
request/destination checks. Index publication tasks are main-actor isolated.

## Fallbacks and omissions

Missing or unlaunchable ripgrep and a failed first index build keep the Spotlight source. A failed
refresh retains its prior snapshot and logs the failure; the next palette opening can retry. Ripgrep
exit 1 is an empty listing. Exit 2 with emitted paths keeps those usable paths because unreadable
subdirectories commonly produce that status; exit 2 without paths and other exit statuses fail.
No content, diagnostics or permission grant is persisted. A failed subtree process clears any partial
rows and restarts the Swift walker; selecting Spotlight uses that walker directly. Cancellation never
starts a fallback. Spotlight's synchronous MDQuery work itself remains uninterruptible.

## Measurements and expectations

Sasha's Mac, 2026-10-11, `/opt/homebrew/bin/rg` 15.2.0:

| Command/source | Time | Files |
| --- | --- | --- |
| `rg --files`, cwd `~` | 3.5 s | 796k (564k under Library) |
| `rg --files -g '!Library/' -g '!.Trash/'`, cwd `~` | 0.83 s | 233k |
| `fzf --filter agentkit --scheme=path` over that list | 0.19 s | — |
| `rg --files`, cwd `~/work` | 0.69 s | 166k |

An implementation-session shell scan with `--null --no-messages` and anchored home exclusions took
0.708 s for 232,782 files, with 17,703,762 relative-path UTF-8 bytes (76.1 bytes/path), exit 2. It did
not run the app or Swift query implementation. Absolute prefixes add about 6.8 MB; String array
headers, allocations and derived directories suggest roughly **40–55 MB** for a settled snapshot.
Refresh holds old and new snapshots, plus its directory set: expect **80–120 MB of index-related peak
memory**, before the app baseline. The requested retained index therefore needs measurement against
the repository's usual 100 MB resident budget; it also intentionally survives palette closure.

Selective multi-letter queries are expected around **30–100 ms** in optimized Swift on Apple silicon,
but have not been benchmarked. Broad short queries may exceed 100 ms because more paths reach fzf's
alignment work; Unicode folding and metadata IO also vary. These are estimates, not acceptance proof.

## Verification handoff

Implementation-session verification is limited to source parsing and XcodeGen generation. Swift 6
type checking, runtime cancellation/isolation, memory, TCC omissions and latency remain for Claude.
No tests, builds, lint, fork audit, app launch or commits were requested or performed.

Potentially affected harnesses: `file-search-test`, `file-search-session-test`, `fork-search-test`,
`file-navigator-test`, `settings-file-test`, `settings-backup-test` and `settings-history-test`.
The session harness source list needs the index/query/policy/process/engine files and `ProcessExit`;
the index accepts configuration values without an AppSettings dependency. Any settings-schema stubs
may need the engine property and its mirror conformance. Harness sources and runner remain unchanged.
